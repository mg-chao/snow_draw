import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

import '../../../draw/elements/types/filter/filter_data.dart';
import '../../../draw/models/element_state.dart';
import '../../../draw/types/draw_rect.dart';
import '../../../draw/types/element_style.dart';
import '../../../draw/utils/lru_cache.dart';
import '../../canvas/filter_shader_manager.dart';
import 'filter_render_diagnostics.dart';
import 'filter_segment.dart';
import 'filter_segment_builder.dart';

typedef SceneElementPainter =
    void Function(Canvas canvas, ElementState element);

/// Scope identifier used to isolate cached filter-scene batches.
enum FilterRenderCacheDomain { staticLayer, dynamicLayer }

/// Stable paint-context key used for cross-frame batch picture reuse.
@immutable
class FilterRenderCacheContext {
  const FilterRenderCacheContext({
    required this.domain,
    required this.documentVersion,
    required this.textRenderingCacheRevision,
    required this.scaleKey,
    required this.localeTag,
  });

  final FilterRenderCacheDomain domain;
  final int documentVersion;
  final int textRenderingCacheRevision;
  final int scaleKey;
  final String localeTag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterRenderCacheContext &&
          other.domain == domain &&
          other.documentVersion == documentVersion &&
          other.textRenderingCacheRevision == textRenderingCacheRevision &&
          other.scaleKey == scaleKey &&
          other.localeTag == localeTag;

  @override
  int get hashCode => Object.hash(
    domain,
    documentVersion,
    textRenderingCacheRevision,
    scaleKey,
    localeTag,
  );
}

/// Runtime hints for adaptive filter rendering.
///
/// Interaction previews can opt into lower-cost approximations to sustain
/// frame rate on backends that do not support shader-based filters.
@immutable
class FilterRenderHints {
  const FilterRenderHints({
    this.interactionPreview = false,
    this.aggressiveCpuFallback = false,
  });

  /// Whether this frame is a high-frequency interaction preview.
  final bool interactionPreview;

  /// Whether CPU-backed filters should prioritize frame rate over fidelity.
  ///
  /// This is intended for sustained interactions (for example dragging a
  /// filter-strength slider on backends without shader support) where keeping
  /// input latency low is more important than precise filter output.
  final bool aggressiveCpuFallback;
}

/// Factory interface for creating filter kernels.
///
/// This indirection keeps [FilterSegmentRenderer] decoupled from the singleton
/// shader manager and makes fallback behavior testable.
abstract interface class FilterKernelFactory {
  const FilterKernelFactory();

  /// Whether high-quality shader-based mosaic filtering is currently available.
  bool get canUseMosaicShader;

  /// Resolves mosaic block size in logical pixels.
  double resolveMosaicBlockSize({
    required double strength,
    required Size regionSize,
  });

  /// Builds a mosaic [ImageFilter] for the specified region.
  ImageFilter? createMosaicFilter({
    required double strength,
    required Size regionSize,
    required Offset regionOffset,
    double? blockSize,
  });
}

/// Default [FilterKernelFactory] backed by [FilterShaderManager].
class DefaultFilterKernelFactory implements FilterKernelFactory {
  const DefaultFilterKernelFactory();

  @override
  bool get canUseMosaicShader =>
      FilterShaderManager.instance.canUseShaderBackedMosaic;

  @override
  double resolveMosaicBlockSize({
    required double strength,
    required Size regionSize,
  }) => FilterShaderManager.instance.resolveMosaicBlockSize(
    strength: strength,
    regionSize: regionSize,
  );

  @override
  ImageFilter? createMosaicFilter({
    required double strength,
    required Size regionSize,
    required Offset regionOffset,
    double? blockSize,
  }) => FilterShaderManager.instance.createMosaicFilter(
    strength: strength,
    regionSize: regionSize,
    regionOffset: regionOffset,
    blockSize: blockSize,
  );
}

/// Renders element scenes with filter segments.
///
/// Unlike per-element compositing, this pipeline scales with the number of
/// filter passes and contiguous element batches.
class FilterSegmentRenderer {
  FilterSegmentRenderer({
    FilterSegmentBuilder? segmentBuilder,
    FilterKernelFactory? kernelFactory,
  }) : _segmentBuilder = segmentBuilder ?? const FilterSegmentBuilder(),
       _kernelFactory = kernelFactory ?? const DefaultFilterKernelFactory();

  static const _filterImageCacheLimit = 256;
  static const _clipInfoCacheLimit = 512;
  static const _batchPictureCacheLimit = 96;
  static const _prefixSceneCacheLimit = 48;
  static const _maxViewportOutset = 72.0;
  static const _interactiveViewportOutset = 48.0;
  static const _aggressiveViewportOutset = 36.0;
  static const _interactiveGaussianMinSigma = 0.35;
  static const _interactiveGaussianMaxSigma = 7.5;
  static const _aggressiveGaussianMaxSigma = 5.5;
  static const _interactiveMosaicMinSigma = 1.5;
  static const _interactiveMosaicMaxSigma = 9.0;
  static const _aggressiveMosaicMaxSigma = 6.5;
  static const _fullQualitySigmaQuantization = 0.125;
  static const _interactiveSigmaQuantization = 0.25;
  static const _aggressiveSigmaQuantization = 0.5;
  static const _fullQualityMosaicQuantization = 0.25;
  static const _interactiveMosaicQuantization = 0.5;
  static const _aggressiveMosaicQuantization = 1.0;
  static const _fullQualityOffsetQuantization = 0.25;
  static const _interactiveOffsetQuantization = 0.5;
  static const _aggressiveOffsetQuantization = 1.0;

  final FilterSegmentBuilder _segmentBuilder;
  final FilterKernelFactory _kernelFactory;
  final _clipInfoCache = LruCache<_FilterClipCacheKey, _ClipInfo>(
    maxEntries: _clipInfoCacheLimit,
  );
  final _filterCache = LruCache<_FilterImageCacheKey, ImageFilter>(
    maxEntries: _filterImageCacheLimit,
  );
  final _batchPictureCache =
      LruCache<_BatchPictureCacheKey, _CachedBatchPicture>(
        maxEntries: _batchPictureCacheLimit,
        onEvict: (entry) => entry.markEvicted(),
      );
  final _prefixSceneCache =
      LruCache<_PrefixSceneCacheKey, _CachedPrefixScenePicture>(
        maxEntries: _prefixSceneCacheLimit,
        onEvict: (entry) => entry.markEvicted(),
      );
  final _diagnostics = FilterRenderDiagnosticsCollector();

  /// Reusable paint object for `saveLayer` calls.
  ///
  /// Avoids allocating a new [Paint] per filter pass. Properties are
  /// reset before each use via [_resetLayerPaint].
  final _layerPaint = Paint();

  /// Last completed frame diagnostics.
  FilterRenderDiagnostics get lastDiagnostics => _diagnostics.lastFrame;

  @visibleForTesting
  int get debugFilterCacheSize => _filterCache.length;

  @visibleForTesting
  int get debugFilterCacheLimit => _filterImageCacheLimit;

  @visibleForTesting
  int get debugBatchPictureCacheSize => _batchPictureCache.length;

  @visibleForTesting
  int get debugBatchPictureCacheLimit => _batchPictureCacheLimit;

  @visibleForTesting
  int get debugPrefixSceneCacheSize => _prefixSceneCache.length;

  @visibleForTesting
  int get debugPrefixSceneCacheLimit => _prefixSceneCacheLimit;

  /// Clears internal caches.
  void clearCaches() {
    _clipInfoCache.clear();
    _filterCache.clear();
    _batchPictureCache.clear();
    _prefixSceneCache.clear();
  }

  /// Paints [elements] in z-order using segmented filter
  /// composition.
  void paint({
    required Canvas canvas,
    required List<ElementState> elements,
    required SceneElementPainter paintElement,
    FilterRenderCacheContext? cacheContext,
    Rect? visibleBounds,
    Set<String> dynamicElementIds = const <String>{},
    FilterRenderHints renderHints = const FilterRenderHints(),
  }) {
    _diagnostics.beginFrame();
    if (elements.isEmpty) {
      _diagnostics.endFrame();
      return;
    }

    final baseSegments = _segmentBuilder.build(elements);
    final segments = dynamicElementIds.isEmpty
        ? baseSegments
        : _expandMergedSegmentsForDynamicElements(
            baseSegments,
            dynamicElementIds: dynamicElementIds,
          );
    if (segments.isEmpty) {
      _diagnostics.endFrame();
      return;
    }

    final hasFilter = segments.any(
      (s) => s is FilterSegment || s is MergedFilterSegment,
    );
    if (!hasFilter) {
      for (final segment in segments) {
        if (segment is! ElementBatchSegment) {
          continue;
        }
        for (final element in segment.elements) {
          paintElement(canvas, element);
        }
      }
      _diagnostics.endFrame();
      return;
    }
    final lastFilterSegmentIndex = _findLastFilterSegmentIndex(segments);

    // Accumulate batch pictures and only flatten into a single
    // scene when a filter needs to read the composited result.
    // This avoids creating intermediate PictureRecorder merges
    // between consecutive batches.
    final pending = <_ScenePictureRef>[];
    var startSegmentIndex = 0;
    final firstDynamicSegmentIndex = _findFirstDynamicSegmentIndex(
      segments,
      dynamicElementIds: dynamicElementIds,
    );
    if (cacheContext != null && firstDynamicSegmentIndex > 0) {
      final prefixScene = _resolveCachedPrefixScene(
        segments: segments,
        endSegmentIndex: firstDynamicSegmentIndex,
        paintElement: paintElement,
        cacheContext: cacheContext,
        visibleBounds: visibleBounds,
        renderHints: renderHints,
      );
      if (prefixScene != null) {
        pending.add(prefixScene);
        startSegmentIndex = firstDynamicSegmentIndex;
      }
    }

    for (
      var segmentIndex = startSegmentIndex;
      segmentIndex < segments.length;
      segmentIndex++
    ) {
      final segment = segments[segmentIndex];
      if (segment is ElementBatchSegment) {
        if (segment.elements.isEmpty) {
          continue;
        }
        _diagnostics.markBatch();
        pending.add(
          _recordBatch(
            segment.elements,
            paintElement,
            idFingerprint: segment.idFingerprint,
            cacheContext: cacheContext,
            dynamicElementIds: dynamicElementIds,
          ),
        );
        continue;
      }

      if (pending.isEmpty) {
        continue;
      }

      final scene = _flattenPendingScenes(pending);
      if (scene == null) {
        continue;
      }

      if (segment is FilterSegment) {
        if (segmentIndex == lastFilterSegmentIndex) {
          _paintFilterDirectlyToCanvas(
            canvas: canvas,
            scene: scene.picture,
            filterElement: segment.filterElement,
            data: segment.filterData,
            visibleBounds: visibleBounds,
            useClipCache: !dynamicElementIds.contains(segment.filterElement.id),
            renderHints: renderHints,
          );
          scene.release();
          continue;
        }
        final filtered = _applyFilter(
          scene: scene.picture,
          filterElement: segment.filterElement,
          data: segment.filterData,
          visibleBounds: visibleBounds,
          useClipCache: !dynamicElementIds.contains(segment.filterElement.id),
          renderHints: renderHints,
        );
        if (identical(filtered, scene.picture)) {
          pending.add(scene);
        } else {
          scene.release();
          pending.add(_ScenePictureRef.owned(filtered));
        }
        continue;
      }

      if (segment is MergedFilterSegment) {
        final filtered = _applyMergedFilter(
          scene: scene.picture,
          merged: segment,
          visibleBounds: visibleBounds,
          dynamicElementIds: dynamicElementIds,
          renderHints: renderHints,
        );
        if (identical(filtered, scene.picture)) {
          pending.add(scene);
        } else {
          scene.release();
          pending.add(_ScenePictureRef.owned(filtered));
        }
      }
    }

    _drawPendingScenes(canvas: canvas, pending: pending);
    _diagnostics.endFrame();
  }

  List<RenderSegment> _expandMergedSegmentsForDynamicElements(
    List<RenderSegment> segments, {
    required Set<String> dynamicElementIds,
  }) {
    if (segments.isEmpty || dynamicElementIds.isEmpty) {
      return segments;
    }

    List<RenderSegment>? expanded;
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      if (segment is! MergedFilterSegment || segment.filters.length < 2) {
        if (expanded != null) {
          expanded.add(segment);
        }
        continue;
      }

      final groups = _splitMergedSegmentByDynamicMembership(
        segment,
        dynamicElementIds: dynamicElementIds,
      );
      if (groups.length == 1 && identical(groups.first, segment)) {
        if (expanded != null) {
          expanded.add(segment);
        }
        continue;
      }

      expanded ??= <RenderSegment>[
        for (var existingIndex = 0; existingIndex < index; existingIndex++)
          segments[existingIndex],
      ];
      expanded.addAll(groups);
    }

    return expanded ?? segments;
  }

  List<RenderSegment> _splitMergedSegmentByDynamicMembership(
    MergedFilterSegment segment, {
    required Set<String> dynamicElementIds,
  }) {
    final filters = segment.filters;
    var hasDynamicFilter = false;
    var hasStaticFilter = false;
    for (final filter in filters) {
      if (dynamicElementIds.contains(filter.filterElement.id)) {
        hasDynamicFilter = true;
      } else {
        hasStaticFilter = true;
      }
      if (hasDynamicFilter && hasStaticFilter) {
        break;
      }
    }
    if (!hasDynamicFilter || !hasStaticFilter) {
      return <RenderSegment>[segment];
    }

    final split = <RenderSegment>[];
    final run = <FilterSegment>[];
    bool? currentIsDynamic;

    void flushRun() {
      if (run.isEmpty) {
        return;
      }
      if (run.length == 1) {
        split.add(run.first);
      } else {
        split.add(
          MergedFilterSegment(filters: List<FilterSegment>.unmodifiable(run)),
        );
      }
      run.clear();
    }

    for (final filter in filters) {
      final isDynamic = dynamicElementIds.contains(filter.filterElement.id);
      if (currentIsDynamic != null && currentIsDynamic != isDynamic) {
        flushRun();
      }
      currentIsDynamic = isDynamic;
      run.add(filter);
    }
    flushRun();
    return split;
  }

  int _findLastFilterSegmentIndex(List<RenderSegment> segments) {
    for (var index = segments.length - 1; index >= 0; index--) {
      final segment = segments[index];
      if (segment is FilterSegment || segment is MergedFilterSegment) {
        return index;
      }
    }
    return -1;
  }

  int _findFirstDynamicSegmentIndex(
    List<RenderSegment> segments, {
    required Set<String> dynamicElementIds,
  }) {
    if (segments.isEmpty || dynamicElementIds.isEmpty) {
      return -1;
    }
    for (var index = 0; index < segments.length; index++) {
      if (_segmentContainsDynamicElement(
        segments[index],
        dynamicElementIds: dynamicElementIds,
      )) {
        return index;
      }
    }
    return -1;
  }

  bool _segmentContainsDynamicElement(
    RenderSegment segment, {
    required Set<String> dynamicElementIds,
  }) {
    if (dynamicElementIds.isEmpty) {
      return false;
    }
    if (segment is ElementBatchSegment) {
      for (final element in segment.elements) {
        if (dynamicElementIds.contains(element.id)) {
          return true;
        }
      }
      return false;
    }
    if (segment is FilterSegment) {
      return dynamicElementIds.contains(segment.filterElement.id);
    }
    if (segment is MergedFilterSegment) {
      for (final filter in segment.filters) {
        if (dynamicElementIds.contains(filter.filterElement.id)) {
          return true;
        }
      }
    }
    return false;
  }

  _ScenePictureRef? _resolveCachedPrefixScene({
    required List<RenderSegment> segments,
    required int endSegmentIndex,
    required SceneElementPainter paintElement,
    required FilterRenderCacheContext cacheContext,
    required Rect? visibleBounds,
    required FilterRenderHints renderHints,
  }) {
    if (endSegmentIndex <= 0) {
      return null;
    }

    final prefixElements = _collectElementsInSegmentRange(
      segments: segments,
      start: 0,
      end: endSegmentIndex,
    );
    if (prefixElements.isEmpty) {
      return null;
    }

    final cacheKey = _PrefixSceneCacheKey(
      contextSignature: _BatchPictureContextSignature.fromContext(cacheContext),
      fingerprint: _batchFingerprint(prefixElements),
      length: prefixElements.length,
      visibleBoundsSignature: _VisibleBoundsSignature.fromRect(visibleBounds),
      interactionPreview: renderHints.interactionPreview,
    );
    final cached = _prefixSceneCache.get(cacheKey);
    if (cached != null && cached.matches(prefixElements)) {
      _diagnostics.markPrefixSceneCacheHit();
      cached.retain();
      return _ScenePictureRef.shared(
        picture: cached.picture,
        onRelease: cached.release,
      );
    }

    _diagnostics.markPrefixSceneCacheMiss();
    final picture = _composeScenePictureForSegmentRange(
      segments: segments,
      startSegmentIndex: 0,
      endSegmentIndex: endSegmentIndex,
      paintElement: paintElement,
      cacheContext: cacheContext,
      visibleBounds: visibleBounds,
      dynamicElementIds: const <String>{},
      renderHints: renderHints,
    );
    final cachedEntry = _CachedPrefixScenePicture(
      picture: picture,
      elementRefs: prefixElements,
    )..retain();
    _prefixSceneCache.put(cacheKey, cachedEntry);
    return _ScenePictureRef.shared(
      picture: picture,
      onRelease: cachedEntry.release,
    );
  }

  Picture _composeScenePictureForSegmentRange({
    required List<RenderSegment> segments,
    required int startSegmentIndex,
    required int endSegmentIndex,
    required SceneElementPainter paintElement,
    required FilterRenderCacheContext? cacheContext,
    required Rect? visibleBounds,
    required Set<String> dynamicElementIds,
    required FilterRenderHints renderHints,
  }) {
    if (startSegmentIndex >= endSegmentIndex) {
      return _recordEmptyPicture();
    }

    final pending = <_ScenePictureRef>[];
    for (
      var segmentIndex = startSegmentIndex;
      segmentIndex < endSegmentIndex;
      segmentIndex++
    ) {
      final segment = segments[segmentIndex];
      if (segment is ElementBatchSegment) {
        if (segment.elements.isEmpty) {
          continue;
        }
        _diagnostics.markBatch();
        pending.add(
          _recordBatch(
            segment.elements,
            paintElement,
            idFingerprint: segment.idFingerprint,
            cacheContext: cacheContext,
            dynamicElementIds: dynamicElementIds,
          ),
        );
        continue;
      }

      if (pending.isEmpty) {
        continue;
      }

      final scene = _flattenPendingScenes(pending);
      if (scene == null) {
        continue;
      }

      if (segment is FilterSegment) {
        final filtered = _applyFilter(
          scene: scene.picture,
          filterElement: segment.filterElement,
          data: segment.filterData,
          visibleBounds: visibleBounds,
          useClipCache: !dynamicElementIds.contains(segment.filterElement.id),
          renderHints: renderHints,
        );
        if (identical(filtered, scene.picture)) {
          pending.add(scene);
        } else {
          scene.release();
          pending.add(_ScenePictureRef.owned(filtered));
        }
        continue;
      }

      if (segment is MergedFilterSegment) {
        final filtered = _applyMergedFilter(
          scene: scene.picture,
          merged: segment,
          visibleBounds: visibleBounds,
          dynamicElementIds: dynamicElementIds,
          renderHints: renderHints,
        );
        if (identical(filtered, scene.picture)) {
          pending.add(scene);
        } else {
          scene.release();
          pending.add(_ScenePictureRef.owned(filtered));
        }
      }
    }

    final flattened = _flattenPendingScenes(pending, forceOwned: true);
    if (flattened == null) {
      return _recordEmptyPicture();
    }
    return flattened.picture;
  }

  List<ElementState> _collectElementsInSegmentRange({
    required List<RenderSegment> segments,
    required int start,
    required int end,
  }) {
    final collected = <ElementState>[];
    for (var index = start; index < end; index++) {
      final segment = segments[index];
      if (segment is ElementBatchSegment) {
        collected.addAll(segment.elements);
      } else if (segment is FilterSegment) {
        collected.add(segment.filterElement);
      } else if (segment is MergedFilterSegment) {
        for (final filter in segment.filters) {
          collected.add(filter.filterElement);
        }
      }
    }
    return List<ElementState>.unmodifiable(collected);
  }

  _ScenePictureRef? _flattenPendingScenes(
    List<_ScenePictureRef> pending, {
    bool forceOwned = false,
  }) {
    if (pending.isEmpty) {
      return null;
    }
    if (!forceOwned && pending.length == 1) {
      return pending.removeLast();
    }

    _diagnostics.markPictureRecorder();
    final recorder = PictureRecorder();
    final mergeCanvas = Canvas(recorder);
    for (final scene in pending) {
      mergeCanvas.drawPicture(scene.picture);
      scene.release();
    }
    pending.clear();
    return _ScenePictureRef.owned(recorder.endRecording());
  }

  void _drawPendingScenes({
    required Canvas canvas,
    required List<_ScenePictureRef> pending,
  }) {
    for (final scene in pending) {
      canvas.drawPicture(scene.picture);
      scene.release();
    }
    pending.clear();
  }

  Picture _recordEmptyPicture() {
    _diagnostics.markPictureRecorder();
    return PictureRecorder().endRecording();
  }

  _ScenePictureRef _recordBatch(
    List<ElementState> elements,
    SceneElementPainter paintElement, {
    required int? idFingerprint,
    required FilterRenderCacheContext? cacheContext,
    required Set<String> dynamicElementIds,
  }) {
    final canUseCache =
        cacheContext != null &&
        _isBatchCacheEligible(elements, dynamicElementIds);
    if (canUseCache) {
      final cacheKey = _BatchPictureCacheKey(
        contextSignature: _BatchPictureContextSignature.fromContext(
          cacheContext,
        ),
        fingerprint: idFingerprint ?? _batchFingerprint(elements),
        length: elements.length,
      );
      final cached = _batchPictureCache.get(cacheKey);
      if (cached != null && cached.matches(elements)) {
        _diagnostics.markBatchCacheHit();
        cached.retain();
        return _ScenePictureRef.shared(
          picture: cached.picture,
          onRelease: cached.release,
        );
      }
      _diagnostics
        ..markBatchCacheMiss()
        ..markPictureRecorder();
      final recorder = PictureRecorder();
      final batchCanvas = Canvas(recorder);
      for (final element in elements) {
        paintElement(batchCanvas, element);
      }
      final picture = recorder.endRecording();
      final cachedEntry = _CachedBatchPicture(
        picture: picture,
        elementRefs: List<ElementState>.of(elements, growable: false),
      )..retain();
      _batchPictureCache.put(cacheKey, cachedEntry);
      return _ScenePictureRef.shared(
        picture: picture,
        onRelease: cachedEntry.release,
      );
    }

    _diagnostics.markPictureRecorder();
    final recorder = PictureRecorder();
    final batchCanvas = Canvas(recorder);
    for (final element in elements) {
      paintElement(batchCanvas, element);
    }
    return _ScenePictureRef.owned(recorder.endRecording());
  }

  Picture _applyFilter({
    required Picture scene,
    required ElementState filterElement,
    required FilterData data,
    required Rect? visibleBounds,
    required bool useClipCache,
    required FilterRenderHints renderHints,
  }) {
    final prepared = _prepareFilterPass(
      filterElement: filterElement,
      data: data,
      visibleBounds: visibleBounds,
      useClipCache: useClipCache,
      renderHints: renderHints,
    );
    if (prepared == null) {
      return scene;
    }
    return _applyPreparedFilter(
      scene: scene,
      pass: prepared,
      renderHints: renderHints,
    );
  }

  Picture _applyMergedFilter({
    required Picture scene,
    required MergedFilterSegment merged,
    required Rect? visibleBounds,
    required Set<String> dynamicElementIds,
    required FilterRenderHints renderHints,
  }) {
    final prepared = <_PreparedFilterPass>[];
    for (final filter in merged.filters) {
      final pass = _prepareFilterPass(
        filterElement: filter.filterElement,
        data: filter.filterData,
        visibleBounds: visibleBounds,
        useClipCache: !dynamicElementIds.contains(filter.filterElement.id),
        renderHints: renderHints,
      );
      if (pass != null) {
        prepared.add(pass);
      }
    }
    if (prepared.isEmpty) {
      return scene;
    }

    var currentScene = scene;
    final pendingGroup = <_PreparedFilterPass>[];

    void flushPendingGroup() {
      if (pendingGroup.isEmpty) {
        return;
      }
      final nextScene = _applyPreparedMergedGroup(
        scene: currentScene,
        group: pendingGroup,
        renderHints: renderHints,
      );
      if (!identical(nextScene, currentScene) &&
          !identical(currentScene, scene)) {
        currentScene.dispose();
      }
      pendingGroup.clear();
      currentScene = nextScene;
    }

    for (final pass in prepared) {
      if (pendingGroup.isNotEmpty && _overlapsAny(pass, pendingGroup)) {
        flushPendingGroup();
      }
      pendingGroup.add(pass);
    }
    flushPendingGroup();
    return currentScene;
  }

  void _paintFilterDirectlyToCanvas({
    required Canvas canvas,
    required Picture scene,
    required ElementState filterElement,
    required FilterData data,
    required Rect? visibleBounds,
    required bool useClipCache,
    required FilterRenderHints renderHints,
  }) {
    final prepared = _prepareFilterPass(
      filterElement: filterElement,
      data: data,
      visibleBounds: visibleBounds,
      useClipCache: useClipCache,
      renderHints: renderHints,
    );
    canvas.drawPicture(scene);
    if (prepared == null) {
      return;
    }
    _applyClippedFilter(
      canvas: canvas,
      scene: scene,
      clip: prepared.clip,
      data: prepared.data,
      layerBounds: prepared.layerBounds,
      opacity: prepared.opacity,
      renderHints: renderHints,
    );
    _diagnostics.markFilterPass();
  }

  // Prepared filter passes.
  _PreparedFilterPass? _prepareFilterPass({
    required ElementState filterElement,
    required FilterData data,
    required Rect? visibleBounds,
    required bool useClipCache,
    required FilterRenderHints renderHints,
  }) {
    final rect = filterElement.rect;
    if (rect.width <= 0 || rect.height <= 0) {
      return null;
    }

    final opacity = filterElement.opacity.clamp(0.0, 1.0);
    if (opacity <= 0) {
      return null;
    }

    final clip = _resolveClipInfo(filterElement, useCache: useClipCache);
    final layerBounds = _resolveVisibleLayerBounds(
      clipBounds: clip.bounds,
      visibleBounds: visibleBounds,
      data: data,
      renderHints: renderHints,
    );
    if (layerBounds.isEmpty) {
      return null;
    }

    return _PreparedFilterPass(
      data: data,
      clip: clip,
      layerBounds: layerBounds,
      opacity: opacity,
    );
  }

  Picture _applyPreparedFilter({
    required Picture scene,
    required _PreparedFilterPass pass,
    required FilterRenderHints renderHints,
  }) {
    _diagnostics.markPictureRecorder();
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)..drawPicture(scene);

    _applyClippedFilter(
      canvas: canvas,
      scene: scene,
      clip: pass.clip,
      data: pass.data,
      layerBounds: pass.layerBounds,
      opacity: pass.opacity,
      renderHints: renderHints,
    );

    _diagnostics.markFilterPass();
    return recorder.endRecording();
  }

  Picture _applyPreparedMergedGroup({
    required Picture scene,
    required List<_PreparedFilterPass> group,
    required FilterRenderHints renderHints,
  }) {
    if (group.isEmpty) {
      return scene;
    }
    if (group.length == 1) {
      return _applyPreparedFilter(
        scene: scene,
        pass: group.first,
        renderHints: renderHints,
      );
    }

    _diagnostics.markPictureRecorder();
    final recorder = PictureRecorder();
    final outputCanvas = Canvas(recorder)..drawPicture(scene);

    for (final pass in group) {
      _applyClippedFilter(
        canvas: outputCanvas,
        scene: scene,
        clip: pass.clip,
        data: pass.data,
        layerBounds: pass.layerBounds,
        opacity: pass.opacity,
        renderHints: renderHints,
      );
      _diagnostics.markFilterPass();
    }

    return recorder.endRecording();
  }

  bool _overlapsAny(_PreparedFilterPass pass, List<_PreparedFilterPass> group) {
    for (final candidate in group) {
      if (_boundsOverlap(pass.layerBounds, candidate.layerBounds)) {
        return true;
      }
    }
    return false;
  }

  bool _boundsOverlap(Rect a, Rect b) {
    if (a.left >= b.right || b.left >= a.right) {
      return false;
    }
    if (a.top >= b.bottom || b.top >= a.bottom) {
      return false;
    }
    return true;
  }

  // Clipped filter application.

  /// Applies a single filter within a clip region.
  ///
  /// Composites the filtered scene over the clipped source region
  /// using source-over blending.
  /// Uses `clipRect` for axis-aligned clips to avoid the more
  /// expensive `clipPath` rasterization.
  void _applyClippedFilter({
    required Canvas canvas,
    required Picture scene,
    required _ClipInfo clip,
    required FilterData data,
    required Rect layerBounds,
    required double opacity,
    required FilterRenderHints renderHints,
  }) {
    canvas.save();
    clip.applyTo(canvas);
    _paintFilteredLayer(
      canvas: canvas,
      scene: scene,
      data: data,
      filterBounds: clip.bounds,
      layerBounds: layerBounds,
      opacity: opacity,
      renderHints: renderHints,
    );
    canvas.restore();
  }

  // ── Filter type dispatch ────────────────────────────────

  void _paintFilteredLayer({
    required Canvas canvas,
    required Picture scene,
    required FilterData data,
    required Rect filterBounds,
    required Rect layerBounds,
    required double opacity,
    required FilterRenderHints renderHints,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    final runtimePolicy = _resolveRuntimePolicy(renderHints);
    switch (data.type) {
      case CanvasFilterType.mosaic:
        _paintMosaicFilter(
          canvas,
          scene,
          data,
          filterBounds,
          layerBounds,
          opacity,
          runtimePolicy: runtimePolicy,
          blendMode: blendMode,
        );
      case CanvasFilterType.gaussianBlur:
        _paintBlurFilter(
          canvas,
          scene,
          layerBounds,
          opacity,
          data,
          runtimePolicy: runtimePolicy,
          minSigma: runtimePolicy.gaussianMinSigma,
          maxSigma: runtimePolicy.gaussianMaxSigma,
          blendMode: blendMode,
        );
      case CanvasFilterType.grayscale:
        _paintColorMatrixFilter(
          canvas,
          scene,
          _grayscaleColorFilter,
          layerBounds,
          opacity,
          blendMode: blendMode,
        );
      case CanvasFilterType.inversion:
        _paintColorMatrixFilter(
          canvas,
          scene,
          _inversionColorFilter,
          layerBounds,
          opacity,
          blendMode: blendMode,
        );
    }
  }

  // ── Individual filter painters ──────────────────────────

  void _paintMosaicFilter(
    Canvas canvas,
    Picture scene,
    FilterData data,
    Rect filterBounds,
    Rect layerBounds,
    double opacity, {
    required _FilterRuntimePolicy runtimePolicy,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    if (runtimePolicy.useFastMosaicApproximation) {
      _paintBlurFilter(
        canvas,
        scene,
        layerBounds,
        opacity,
        data,
        runtimePolicy: runtimePolicy,
        minSigma: runtimePolicy.mosaicPreviewMinSigma,
        maxSigma: runtimePolicy.mosaicPreviewMaxSigma,
        blendMode: blendMode,
      );
      return;
    }

    final mosaicBlockSize = runtimePolicy.quantizeMosaicBlockSize(
      _kernelFactory.resolveMosaicBlockSize(
        strength: data.strength,
        regionSize: filterBounds.size,
      ),
    );
    final mosaicOrigin = filterBounds.topLeft;
    final normalizedOffsetX = _positiveModulo(
      runtimePolicy.quantizeMosaicOffset(
        _positiveModulo(mosaicOrigin.dx, mosaicBlockSize),
      ),
      mosaicBlockSize,
    );
    final normalizedOffsetY = _positiveModulo(
      runtimePolicy.quantizeMosaicOffset(
        _positiveModulo(mosaicOrigin.dy, mosaicBlockSize),
      ),
      mosaicBlockSize,
    );
    final cacheKey = _FilterImageCacheKey(
      type: CanvasFilterType.mosaic,
      param0: mosaicBlockSize,
      param1: layerBounds.width,
      param2: layerBounds.height,
      param3: normalizedOffsetX,
      param4: normalizedOffsetY,
    );
    final shaderFilter =
        _filterCache.get(cacheKey) ??
        _kernelFactory.createMosaicFilter(
          strength: data.strength,
          regionSize: layerBounds.size,
          regionOffset: mosaicOrigin,
          blockSize: mosaicBlockSize,
        );
    if (shaderFilter != null) {
      _filterCache.put(cacheKey, shaderFilter);
      _diagnostics.markSaveLayer();
      _resetLayerPaint(
        opacity: opacity,
        imageFilter: shaderFilter,
        blendMode: blendMode,
      );
      canvas
        ..saveLayer(layerBounds, _layerPaint)
        ..drawPicture(scene)
        ..restore();
      return;
    }

    _paintBlurFilter(
      canvas,
      scene,
      layerBounds,
      opacity,
      data,
      runtimePolicy: runtimePolicy,
      minSigma: 4,
      maxSigma: 24,
      blendMode: blendMode,
    );
  }

  void _paintBlurFilter(
    Canvas canvas,
    Picture scene,
    Rect layerBounds,
    double opacity,
    FilterData data, {
    required _FilterRuntimePolicy runtimePolicy,
    double minSigma = 0.5,
    double maxSigma = 12,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    final sigma = runtimePolicy.quantizeSigma(
      _mapStrength(
        strength: data.strength,
        minValue: minSigma,
        maxValue: maxSigma,
      ),
    );
    final cacheKey = _FilterImageCacheKey(
      type: CanvasFilterType.gaussianBlur,
      param0: sigma,
      param1: sigma,
    );
    final imageFilter = _filterCache.getOrCreate(
      cacheKey,
      () => ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );

    _diagnostics.markSaveLayer();
    _resetLayerPaint(
      opacity: opacity,
      imageFilter: imageFilter,
      blendMode: blendMode,
    );
    canvas
      ..saveLayer(layerBounds, _layerPaint)
      ..drawPicture(scene)
      ..restore();
  }

  void _paintColorMatrixFilter(
    Canvas canvas,
    Picture scene,
    ColorFilter colorFilter,
    Rect layerBounds,
    double opacity, {
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    _diagnostics.markSaveLayer();
    _resetLayerPaint(
      opacity: opacity,
      colorFilter: colorFilter,
      blendMode: blendMode,
    );
    canvas
      ..saveLayer(layerBounds, _layerPaint)
      ..drawPicture(scene)
      ..restore();
  }

  // ── Helpers ─────────────────────────────────────────────

  /// Configures [_layerPaint] for the next `saveLayer` call.
  ///
  /// Resets all filter-related properties so stale values from a
  /// previous pass don't leak through.
  void _resetLayerPaint({
    required double opacity,
    ImageFilter? imageFilter,
    ColorFilter? colorFilter,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    _layerPaint
      ..imageFilter = imageFilter
      ..colorFilter = colorFilter
      ..blendMode = blendMode
      ..color = opacity < 1
          ? Color.fromRGBO(255, 255, 255, opacity)
          : const Color(0xFFFFFFFF);
  }

  Rect _resolveVisibleLayerBounds({
    required Rect clipBounds,
    required Rect? visibleBounds,
    required FilterData data,
    required FilterRenderHints renderHints,
  }) {
    if (visibleBounds == null) {
      return clipBounds;
    }
    final runtimePolicy = _resolveRuntimePolicy(renderHints);
    final viewportOutset = _resolveFilterViewportOutset(
      data: data,
      clipBounds: clipBounds,
      runtimePolicy: runtimePolicy,
    );
    final expandedVisible = Rect.fromLTRB(
      visibleBounds.left - viewportOutset,
      visibleBounds.top - viewportOutset,
      visibleBounds.right + viewportOutset,
      visibleBounds.bottom + viewportOutset,
    );
    return Rect.fromLTRB(
      math.max(clipBounds.left, expandedVisible.left),
      math.max(clipBounds.top, expandedVisible.top),
      math.min(clipBounds.right, expandedVisible.right),
      math.min(clipBounds.bottom, expandedVisible.bottom),
    );
  }

  double _resolveFilterViewportOutset({
    required FilterData data,
    required Rect clipBounds,
    required _FilterRuntimePolicy runtimePolicy,
  }) {
    switch (data.type) {
      case CanvasFilterType.gaussianBlur:
        final sigma = runtimePolicy.quantizeSigma(
          _mapStrength(
            strength: data.strength,
            minValue: runtimePolicy.gaussianMinSigma,
            maxValue: runtimePolicy.gaussianMaxSigma,
          ),
        );
        final blurRadius = (sigma * 3) + 2;
        return math.min(blurRadius, runtimePolicy.maxViewportOutset);
      case CanvasFilterType.mosaic:
        if (runtimePolicy.useFastMosaicApproximation) {
          final sigma = runtimePolicy.quantizeSigma(
            _mapStrength(
              strength: data.strength,
              minValue: runtimePolicy.mosaicPreviewMinSigma,
              maxValue: runtimePolicy.mosaicPreviewMaxSigma,
            ),
          );
          final blurRadius = (sigma * 3) + 2;
          return math.min(blurRadius, runtimePolicy.maxViewportOutset);
        }
        final blockSize = runtimePolicy.quantizeMosaicBlockSize(
          _kernelFactory.resolveMosaicBlockSize(
            strength: data.strength,
            regionSize: clipBounds.size,
          ),
        );
        return math.min(
          math.max(blockSize, 8),
          runtimePolicy.maxViewportOutset,
        );
      case CanvasFilterType.grayscale:
      case CanvasFilterType.inversion:
        return 0;
    }
  }

  _FilterRuntimePolicy _resolveRuntimePolicy(FilterRenderHints renderHints) {
    final preferFastCpuFallback =
        renderHints.interactionPreview || renderHints.aggressiveCpuFallback;
    final aggressiveCpuFallback =
        preferFastCpuFallback && renderHints.aggressiveCpuFallback;
    final sigmaQuantizationStep = aggressiveCpuFallback
        ? _aggressiveSigmaQuantization
        : preferFastCpuFallback
        ? _interactiveSigmaQuantization
        : _fullQualitySigmaQuantization;
    final mosaicQuantizationStep = aggressiveCpuFallback
        ? _aggressiveMosaicQuantization
        : preferFastCpuFallback
        ? _interactiveMosaicQuantization
        : _fullQualityMosaicQuantization;
    final offsetQuantizationStep = aggressiveCpuFallback
        ? _aggressiveOffsetQuantization
        : preferFastCpuFallback
        ? _interactiveOffsetQuantization
        : _fullQualityOffsetQuantization;
    final gaussianMaxSigma = aggressiveCpuFallback
        ? _aggressiveGaussianMaxSigma
        : preferFastCpuFallback
        ? _interactiveGaussianMaxSigma
        : 12.0;
    final mosaicMaxSigma = aggressiveCpuFallback
        ? _aggressiveMosaicMaxSigma
        : _interactiveMosaicMaxSigma;
    final maxViewportOutset = aggressiveCpuFallback
        ? _aggressiveViewportOutset
        : preferFastCpuFallback
        ? _interactiveViewportOutset
        : _maxViewportOutset;

    return _FilterRuntimePolicy(
      preferFastCpuFallback: preferFastCpuFallback,
      canUseMosaicShader: _kernelFactory.canUseMosaicShader,
      gaussianMinSigma: preferFastCpuFallback
          ? _interactiveGaussianMinSigma
          : 0.5,
      gaussianMaxSigma: gaussianMaxSigma,
      mosaicPreviewMinSigma: _interactiveMosaicMinSigma,
      mosaicPreviewMaxSigma: mosaicMaxSigma,
      maxViewportOutset: maxViewportOutset,
      sigmaQuantizationStep: sigmaQuantizationStep,
      mosaicSizeQuantizationStep: mosaicQuantizationStep,
      mosaicOffsetQuantizationStep: offsetQuantizationStep,
    );
  }

  _ClipInfo _resolveClipInfo(ElementState element, {required bool useCache}) {
    if (!useCache) {
      return _buildClipInfo(element);
    }
    final key = _FilterClipCacheKey(
      id: element.id,
      rect: element.rect,
      rotation: element.rotation,
    );
    return _clipInfoCache.getOrCreate(key, () => _buildClipInfo(element));
  }

  _ClipInfo _buildClipInfo(ElementState element) {
    final rect = element.rect;
    final uiRect = Rect.fromLTWH(rect.minX, rect.minY, rect.width, rect.height);
    if (element.rotation == 0) {
      return _ClipInfo(bounds: uiRect);
    }

    final sinRotation = math.sin(element.rotation);
    final cosRotation = math.cos(element.rotation);
    final centerX = rect.centerX;
    final centerY = rect.centerY;

    Offset rotatePoint(double x, double y) {
      final localX = x - centerX;
      final localY = y - centerY;
      return Offset(
        centerX + (localX * cosRotation) - (localY * sinRotation),
        centerY + (localX * sinRotation) + (localY * cosRotation),
      );
    }

    final topLeft = rotatePoint(rect.minX, rect.minY);
    final topRight = rotatePoint(rect.maxX, rect.minY);
    final bottomRight = rotatePoint(rect.maxX, rect.maxY);
    final bottomLeft = rotatePoint(rect.minX, rect.maxY);

    final path = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..close();

    return _ClipInfo(bounds: path.getBounds(), path: path);
  }

  bool _isBatchCacheEligible(
    List<ElementState> elements,
    Set<String> dynamicElementIds,
  ) {
    if (elements.isEmpty) {
      return false;
    }
    if (dynamicElementIds.isEmpty) {
      return true;
    }
    for (final element in elements) {
      if (dynamicElementIds.contains(element.id)) {
        return false;
      }
    }
    return true;
  }

  int _batchFingerprint(List<ElementState> elements) {
    var hash = 17;
    for (final element in elements) {
      hash = 0x1fffffff & (hash * 31 + element.id.hashCode);
    }
    return hash;
  }

  double _mapStrength({
    required double strength,
    required double minValue,
    required double maxValue,
  }) {
    final normalized = strength.clamp(0.0, 1.0);
    return minValue + (maxValue - minValue) * normalized;
  }

  double _positiveModulo(double value, double period) {
    if (period <= 0) {
      return value;
    }
    final remainder = value % period;
    if (remainder < 0) {
      return remainder + period;
    }
    return remainder;
  }
}

@immutable
class _FilterRuntimePolicy {
  const _FilterRuntimePolicy({
    required this.preferFastCpuFallback,
    required this.canUseMosaicShader,
    required this.gaussianMinSigma,
    required this.gaussianMaxSigma,
    required this.mosaicPreviewMinSigma,
    required this.mosaicPreviewMaxSigma,
    required this.maxViewportOutset,
    required this.sigmaQuantizationStep,
    required this.mosaicSizeQuantizationStep,
    required this.mosaicOffsetQuantizationStep,
  });

  final bool preferFastCpuFallback;
  final bool canUseMosaicShader;
  final double gaussianMinSigma;
  final double gaussianMaxSigma;
  final double mosaicPreviewMinSigma;
  final double mosaicPreviewMaxSigma;
  final double maxViewportOutset;
  final double sigmaQuantizationStep;
  final double mosaicSizeQuantizationStep;
  final double mosaicOffsetQuantizationStep;

  bool get useFastMosaicApproximation =>
      preferFastCpuFallback && !canUseMosaicShader;

  double quantizeSigma(double sigma) => _quantize(sigma, sigmaQuantizationStep);

  double quantizeMosaicBlockSize(double value) {
    final quantized = _quantize(value, mosaicSizeQuantizationStep);
    if (quantized.isFinite && quantized > 0) {
      return quantized;
    }
    if (value.isFinite && value > 0) {
      return value;
    }
    return 1;
  }

  double quantizeMosaicOffset(double value) =>
      _quantize(value, mosaicOffsetQuantizationStep);

  double _quantize(double value, double step) {
    if (step <= 0 || !value.isFinite) {
      return value;
    }
    final quantized = (value / step).roundToDouble() * step;
    if (quantized == 0) {
      return 0;
    }
    return quantized;
  }
}

// ── Cache keys ──────────────────────────────────────────

@immutable
class _ScenePictureRef {
  const _ScenePictureRef._({
    required this.picture,
    required this.isOwned,
    this.onRelease,
  });

  const _ScenePictureRef.owned(Picture picture)
    : this._(picture: picture, isOwned: true);

  const _ScenePictureRef.shared({
    required Picture picture,
    required void Function() onRelease,
  }) : this._(picture: picture, isOwned: false, onRelease: onRelease);

  final Picture picture;
  final bool isOwned;
  final void Function()? onRelease;

  void release() {
    if (isOwned) {
      picture.dispose();
      return;
    }
    onRelease?.call();
  }
}

@immutable
class _BatchPictureContextSignature {
  const _BatchPictureContextSignature({
    required this.domain,
    required this.textRenderingCacheRevision,
    required this.scaleKey,
    required this.localeTag,
  });

  factory _BatchPictureContextSignature.fromContext(
    FilterRenderCacheContext context,
  ) => _BatchPictureContextSignature(
    domain: context.domain,
    textRenderingCacheRevision: context.textRenderingCacheRevision,
    scaleKey: context.scaleKey,
    localeTag: context.localeTag,
  );

  final FilterRenderCacheDomain domain;
  final int textRenderingCacheRevision;
  final int scaleKey;
  final String localeTag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _BatchPictureContextSignature &&
          other.domain == domain &&
          other.textRenderingCacheRevision == textRenderingCacheRevision &&
          other.scaleKey == scaleKey &&
          other.localeTag == localeTag;

  @override
  int get hashCode =>
      Object.hash(domain, textRenderingCacheRevision, scaleKey, localeTag);
}

@immutable
class _BatchPictureCacheKey {
  const _BatchPictureCacheKey({
    required this.contextSignature,
    required this.fingerprint,
    required this.length,
  });

  /// Signature intentionally excludes document version so stable non-filter
  /// batches survive filter-only document updates (for example strength drags).
  final _BatchPictureContextSignature contextSignature;
  final int fingerprint;
  final int length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _BatchPictureCacheKey &&
          other.contextSignature == contextSignature &&
          other.fingerprint == fingerprint &&
          other.length == length;

  @override
  int get hashCode => Object.hash(contextSignature, fingerprint, length);
}

@immutable
class _VisibleBoundsSignature {
  const _VisibleBoundsSignature._({
    required this.hasBounds,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  factory _VisibleBoundsSignature.fromRect(Rect? bounds) {
    if (bounds == null) {
      return const _VisibleBoundsSignature._(
        hasBounds: false,
        left: 0,
        top: 0,
        right: 0,
        bottom: 0,
      );
    }
    return _VisibleBoundsSignature._(
      hasBounds: true,
      left: (bounds.left * 100).round(),
      top: (bounds.top * 100).round(),
      right: (bounds.right * 100).round(),
      bottom: (bounds.bottom * 100).round(),
    );
  }

  final bool hasBounds;
  final int left;
  final int top;
  final int right;
  final int bottom;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _VisibleBoundsSignature &&
          other.hasBounds == hasBounds &&
          other.left == left &&
          other.top == top &&
          other.right == right &&
          other.bottom == bottom;

  @override
  int get hashCode => Object.hash(hasBounds, left, top, right, bottom);
}

@immutable
class _PrefixSceneCacheKey {
  const _PrefixSceneCacheKey({
    required this.contextSignature,
    required this.fingerprint,
    required this.length,
    required this.visibleBoundsSignature,
    required this.interactionPreview,
  });

  final _BatchPictureContextSignature contextSignature;
  final int fingerprint;
  final int length;
  final _VisibleBoundsSignature visibleBoundsSignature;
  final bool interactionPreview;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PrefixSceneCacheKey &&
          other.contextSignature == contextSignature &&
          other.fingerprint == fingerprint &&
          other.length == length &&
          other.visibleBoundsSignature == visibleBoundsSignature &&
          other.interactionPreview == interactionPreview;

  @override
  int get hashCode => Object.hash(
    contextSignature,
    fingerprint,
    length,
    visibleBoundsSignature,
    interactionPreview,
  );
}

class _CachedBatchPicture {
  _CachedBatchPicture({required this.picture, required this.elementRefs});

  final Picture picture;
  final List<ElementState> elementRefs;
  var _activeReaders = 0;
  var _evicted = false;
  var _disposed = false;

  bool matches(List<ElementState> elements) {
    if (elements.length != elementRefs.length) {
      return false;
    }
    for (var index = 0; index < elements.length; index++) {
      if (!identical(elements[index], elementRefs[index])) {
        return false;
      }
    }
    return true;
  }

  void retain() {
    _activeReaders += 1;
  }

  void release() {
    if (_activeReaders == 0) {
      return;
    }
    _activeReaders -= 1;
    if (_activeReaders == 0 && _evicted) {
      _dispose();
    }
  }

  void markEvicted() {
    _evicted = true;
    if (_activeReaders == 0) {
      _dispose();
    }
  }

  void _dispose() {
    if (_disposed) {
      return;
    }
    picture.dispose();
    _disposed = true;
  }
}

class _CachedPrefixScenePicture {
  _CachedPrefixScenePicture({required this.picture, required this.elementRefs});

  final Picture picture;
  final List<ElementState> elementRefs;
  var _activeReaders = 0;
  var _evicted = false;
  var _disposed = false;

  bool matches(List<ElementState> elements) {
    if (elements.length != elementRefs.length) {
      return false;
    }
    for (var index = 0; index < elements.length; index++) {
      if (!identical(elements[index], elementRefs[index])) {
        return false;
      }
    }
    return true;
  }

  void retain() {
    _activeReaders += 1;
  }

  void release() {
    if (_activeReaders == 0) {
      return;
    }
    _activeReaders -= 1;
    if (_activeReaders == 0 && _evicted) {
      _dispose();
    }
  }

  void markEvicted() {
    _evicted = true;
    if (_activeReaders == 0) {
      _dispose();
    }
  }

  void _dispose() {
    if (_disposed) {
      return;
    }
    picture.dispose();
    _disposed = true;
  }
}

@immutable
class _PreparedFilterPass {
  const _PreparedFilterPass({
    required this.data,
    required this.clip,
    required this.layerBounds,
    required this.opacity,
  });

  final FilterData data;
  final _ClipInfo clip;
  final Rect layerBounds;
  final double opacity;
}

@immutable
class _FilterClipCacheKey {
  const _FilterClipCacheKey({
    required this.id,
    required this.rect,
    required this.rotation,
  });

  final String id;
  final DrawRect rect;
  final double rotation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FilterClipCacheKey &&
          other.id == id &&
          other.rect == rect &&
          other.rotation == rotation;

  @override
  int get hashCode => Object.hash(id, rect, rotation);
}

/// Cache key for [ImageFilter] objects.
///
/// Uses generic numeric parameters so the same key type works for blur
/// (sigma values) and mosaic (strength, region dimensions, offset).
@immutable
class _FilterImageCacheKey {
  const _FilterImageCacheKey({
    required this.type,
    this.param0 = 0,
    this.param1 = 0,
    this.param2 = 0,
    this.param3 = 0,
    this.param4 = 0,
  });

  final CanvasFilterType type;
  final double param0;
  final double param1;
  final double param2;
  final double param3;
  final double param4;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FilterImageCacheKey &&
          other.type == type &&
          other.param0 == param0 &&
          other.param1 == param1 &&
          other.param2 == param2 &&
          other.param3 == param3 &&
          other.param4 == param4;

  @override
  int get hashCode => Object.hash(type, param0, param1, param2, param3, param4);
}

/// Resolved clip geometry for a filter element.
///
/// When [path] is `null` the clip is axis-aligned and [bounds] can be
/// applied directly via `Canvas.clipRect`, which is cheaper than the
/// general `clipPath` rasterization.
@immutable
class _ClipInfo {
  const _ClipInfo({required this.bounds, this.path});

  final Rect bounds;
  final Path? path;

  /// Whether this clip is a simple axis-aligned rectangle.
  bool get isAxisAligned => path == null;

  /// Applies the clip to [canvas] using the cheapest available method.
  void applyTo(Canvas canvas) {
    if (path != null) {
      canvas.clipPath(path!);
    } else {
      canvas.clipRect(bounds);
    }
  }
}

// ── Cached color-filter constants ───────────────────────

const _grayscaleMatrix = <double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
];

const _inversionMatrix = <double>[
  -1, 0, 0, 0, 255, //
  0, -1, 0, 0, 255, //
  0, 0, -1, 0, 255, //
  0, 0, 0, 1, 0, //
];

/// Pre-built grayscale [ColorFilter] to avoid per-frame allocation.
const _grayscaleColorFilter = ColorFilter.matrix(_grayscaleMatrix);

/// Pre-built inversion [ColorFilter] to avoid per-frame allocation.
const _inversionColorFilter = ColorFilter.matrix(_inversionMatrix);
