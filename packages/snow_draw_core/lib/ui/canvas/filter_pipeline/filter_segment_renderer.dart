import 'dart:math' as math;
import 'dart:typed_data';
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
  static const _fullQualityBlurDownsampleFactor = 1.0;
  static const _interactiveBlurDownsampleFactor = 0.75;
  static const _aggressiveBlurDownsampleFactor = 0.55;
  static const _fullQualityBlurPixelBudget = 1073741824.0;
  static const _interactiveBlurPixelBudget = 420000;
  static const _aggressiveBlurPixelBudget = 240000;
  static const _fullQualityColorMatrixPixelBudget = 1073741824.0;
  static const _interactiveColorMatrixPixelBudget = 640000;
  static const _aggressiveColorMatrixPixelBudget = 360000;
  static const _largeFilterCoverageThreshold = 0.35;
  static const _hugeFilterCoverageThreshold = 0.72;
  static const _largeCoverageViewportOutsetScale = 0.8;
  static const _hugeCoverageViewportOutsetScale = 0.65;
  static const _largeCoverageSigmaScale = 0.82;
  static const _hugeCoverageSigmaScale = 0.66;
  static const _largeCoverageBlurDownsampleScale = 0.82;
  static const _hugeCoverageBlurDownsampleScale = 0.64;
  static const _largeCoveragePixelBudgetScale = 0.86;
  static const _hugeCoveragePixelBudgetScale = 0.62;
  static const _largeCoverageColorMatrixDownsample = 0.72;
  static const _hugeCoverageColorMatrixDownsample = 0.58;
  static const _largeCoverageQuantizationScale = 1.5;
  static const _hugeCoverageQuantizationScale = 2.0;
  static const _fingerprintSeed = 17;
  static const _identityFingerprintSeed = 23;
  static const _hashMask = 0x1fffffff;

  final FilterSegmentBuilder _segmentBuilder;
  final FilterKernelFactory _kernelFactory;
  final _clipInfoCache = LruCache<_FilterClipCacheKey, _ClipInfo>(
    maxEntries: _clipInfoCacheLimit,
  );
  final _filterCache = LruCache<_FilterImageCacheKey, ImageFilter>(
    maxEntries: _filterImageCacheLimit,
  );
  final _batchPictureCache = LruCache<_BatchPictureCacheKey, _CachedPicture>(
    maxEntries: _batchPictureCacheLimit,
    onEvict: (entry) => entry.markEvicted(),
  );
  final _prefixSceneCache = LruCache<_PrefixSceneCacheKey, _CachedPicture>(
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
    final runtimePolicy = _resolveRuntimePolicy(renderHints);

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

    final lastFilterSegmentIndex = _findLastFilterSegmentIndex(segments);
    if (lastFilterSegmentIndex < 0) {
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
        runtimePolicy: runtimePolicy,
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
            identityFingerprint: segment.identityFingerprint,
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
            runtimePolicy: runtimePolicy,
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
          runtimePolicy: runtimePolicy,
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
        if (segmentIndex == lastFilterSegmentIndex) {
          _paintMergedFilterDirectlyToCanvas(
            canvas: canvas,
            scene: scene.picture,
            merged: segment,
            visibleBounds: visibleBounds,
            dynamicElementIds: dynamicElementIds,
            runtimePolicy: runtimePolicy,
          );
          scene.release();
          continue;
        }
        final filtered = _applyMergedFilter(
          scene: scene.picture,
          merged: segment,
          visibleBounds: visibleBounds,
          dynamicElementIds: dynamicElementIds,
          runtimePolicy: runtimePolicy,
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
    return switch (segment) {
      ElementBatchSegment(:final elements) => elements.any(
        (element) => dynamicElementIds.contains(element.id),
      ),
      FilterSegment(:final filterElement) => dynamicElementIds.contains(
        filterElement.id,
      ),
      MergedFilterSegment(:final filters) => filters.any(
        (filter) => dynamicElementIds.contains(filter.filterElement.id),
      ),
    };
  }

  _ScenePictureRef? _resolveCachedPrefixScene({
    required List<RenderSegment> segments,
    required int endSegmentIndex,
    required SceneElementPainter paintElement,
    required FilterRenderCacheContext cacheContext,
    required Rect? visibleBounds,
    required _FilterRuntimePolicy runtimePolicy,
  }) {
    if (endSegmentIndex <= 0) {
      return null;
    }

    final rangeSignature = _buildSegmentRangeSignature(
      segments: segments,
      start: 0,
      end: endSegmentIndex,
    );
    if (rangeSignature.elementCount == 0) {
      return null;
    }

    final cacheKey = _PrefixSceneCacheKey(
      contextSignature: _BatchPictureContextSignature.fromContext(cacheContext),
      idFingerprint: rangeSignature.idFingerprint,
      identityFingerprint: rangeSignature.identityFingerprint,
      elementCount: rangeSignature.elementCount,
      segmentCount: rangeSignature.segmentCount,
      visibleBoundsSignature: _VisibleBoundsSignature.fromRect(visibleBounds),
      interactionPreview: runtimePolicy.preferFastCpuFallback,
      aggressiveCpuFallback: runtimePolicy.aggressiveCpuFallback,
    );
    final cached = _prefixSceneCache.get(cacheKey);
    if (cached != null) {
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
      runtimePolicy: runtimePolicy,
    );
    final cachedEntry = _CachedPicture(picture: picture)..retain();
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
    required _FilterRuntimePolicy runtimePolicy,
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
            identityFingerprint: segment.identityFingerprint,
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
          runtimePolicy: runtimePolicy,
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
          runtimePolicy: runtimePolicy,
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

  _SegmentRangeSignature _buildSegmentRangeSignature({
    required List<RenderSegment> segments,
    required int start,
    required int end,
  }) {
    var idFingerprint = _fingerprintSeed;
    var identityFingerprint = _identityFingerprintSeed;
    var elementCount = 0;
    var segmentCount = 0;
    for (var index = start; index < end; index++) {
      final segment = segments[index];
      idFingerprint = _appendFingerprint(
        idFingerprint,
        _resolveSegmentIdFingerprint(segment),
      );
      identityFingerprint = _appendFingerprint(
        identityFingerprint,
        _resolveSegmentIdentityFingerprint(segment),
      );
      elementCount += _resolveSegmentElementCount(segment);
      segmentCount += 1;
    }
    return _SegmentRangeSignature(
      idFingerprint: idFingerprint,
      identityFingerprint: identityFingerprint,
      elementCount: elementCount,
      segmentCount: segmentCount,
    );
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
    required int? identityFingerprint,
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
        idFingerprint: idFingerprint ?? _batchFingerprint(elements),
        identityFingerprint:
            identityFingerprint ?? _batchIdentityFingerprint(elements),
        elementCount: elements.length,
      );
      final cached = _batchPictureCache.get(cacheKey);
      if (cached != null) {
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
      final cachedEntry = _CachedPicture(picture: picture)..retain();
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
    required _FilterRuntimePolicy runtimePolicy,
  }) {
    final prepared = _prepareFilterPass(
      filterElement: filterElement,
      data: data,
      visibleBounds: visibleBounds,
      useClipCache: useClipCache,
      runtimePolicy: runtimePolicy,
    );
    if (prepared == null) {
      return scene;
    }
    return _applyPreparedFilter(
      scene: scene,
      pass: prepared,
      runtimePolicy: runtimePolicy,
    );
  }

  Picture _applyMergedFilter({
    required Picture scene,
    required MergedFilterSegment merged,
    required Rect? visibleBounds,
    required Set<String> dynamicElementIds,
    required _FilterRuntimePolicy runtimePolicy,
  }) {
    final prepared = _prepareMergedFilterPasses(
      merged: merged,
      visibleBounds: visibleBounds,
      dynamicElementIds: dynamicElementIds,
      runtimePolicy: runtimePolicy,
    );
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
        runtimePolicy: runtimePolicy,
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
    required _FilterRuntimePolicy runtimePolicy,
  }) {
    final prepared = _prepareFilterPass(
      filterElement: filterElement,
      data: data,
      visibleBounds: visibleBounds,
      useClipCache: useClipCache,
      runtimePolicy: runtimePolicy,
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
      coverageRatio: prepared.coverageRatio,
      runtimePolicy: runtimePolicy,
    );
    _diagnostics.markFilterPass();
  }

  void _paintMergedFilterDirectlyToCanvas({
    required Canvas canvas,
    required Picture scene,
    required MergedFilterSegment merged,
    required Rect? visibleBounds,
    required Set<String> dynamicElementIds,
    required _FilterRuntimePolicy runtimePolicy,
  }) {
    final prepared = _prepareMergedFilterPasses(
      merged: merged,
      visibleBounds: visibleBounds,
      dynamicElementIds: dynamicElementIds,
      runtimePolicy: runtimePolicy,
    );
    if (prepared.isEmpty) {
      canvas.drawPicture(scene);
      return;
    }
    if (_hasOverlappingPreparedPasses(prepared)) {
      final filteredScene = _applyPreparedFilterSequence(
        scene: scene,
        passes: prepared,
        runtimePolicy: runtimePolicy,
      );
      canvas.drawPicture(filteredScene);
      if (!identical(filteredScene, scene)) {
        filteredScene.dispose();
      }
      return;
    }

    canvas.drawPicture(scene);
    for (final pass in prepared) {
      _applyClippedFilter(
        canvas: canvas,
        scene: scene,
        clip: pass.clip,
        data: pass.data,
        layerBounds: pass.layerBounds,
        opacity: pass.opacity,
        coverageRatio: pass.coverageRatio,
        runtimePolicy: runtimePolicy,
      );
      _diagnostics.markFilterPass();
    }
  }

  // Prepared filter passes.
  List<_PreparedFilterPass> _prepareMergedFilterPasses({
    required MergedFilterSegment merged,
    required Rect? visibleBounds,
    required Set<String> dynamicElementIds,
    required _FilterRuntimePolicy runtimePolicy,
  }) {
    final prepared = <_PreparedFilterPass>[];
    for (final filter in merged.filters) {
      final pass = _prepareFilterPass(
        filterElement: filter.filterElement,
        data: filter.filterData,
        visibleBounds: visibleBounds,
        useClipCache: !dynamicElementIds.contains(filter.filterElement.id),
        runtimePolicy: runtimePolicy,
      );
      if (pass != null) {
        prepared.add(pass);
      }
    }
    return prepared;
  }

  _PreparedFilterPass? _prepareFilterPass({
    required ElementState filterElement,
    required FilterData data,
    required Rect? visibleBounds,
    required bool useClipCache,
    required _FilterRuntimePolicy runtimePolicy,
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
    final clipCoverageRatio = _resolveCoverageRatio(
      region: clip.bounds,
      visibleBounds: visibleBounds,
    );
    final layerBounds = _resolveVisibleLayerBounds(
      clipBounds: clip.bounds,
      visibleBounds: visibleBounds,
      data: data,
      coverageRatio: clipCoverageRatio,
      runtimePolicy: runtimePolicy,
    );
    if (layerBounds.isEmpty) {
      return null;
    }

    return _PreparedFilterPass(
      data: data,
      clip: clip,
      layerBounds: layerBounds,
      opacity: opacity,
      coverageRatio: clipCoverageRatio,
    );
  }

  Picture _applyPreparedFilter({
    required Picture scene,
    required _PreparedFilterPass pass,
    required _FilterRuntimePolicy runtimePolicy,
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
      coverageRatio: pass.coverageRatio,
      runtimePolicy: runtimePolicy,
    );

    _diagnostics.markFilterPass();
    return recorder.endRecording();
  }

  Picture _applyPreparedMergedGroup({
    required Picture scene,
    required List<_PreparedFilterPass> group,
    required _FilterRuntimePolicy runtimePolicy,
  }) {
    if (group.isEmpty) {
      return scene;
    }
    if (group.length == 1) {
      return _applyPreparedFilter(
        scene: scene,
        pass: group.first,
        runtimePolicy: runtimePolicy,
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
        coverageRatio: pass.coverageRatio,
        runtimePolicy: runtimePolicy,
      );
      _diagnostics.markFilterPass();
    }

    return recorder.endRecording();
  }

  Picture _applyPreparedFilterSequence({
    required Picture scene,
    required List<_PreparedFilterPass> passes,
    required _FilterRuntimePolicy runtimePolicy,
  }) {
    if (passes.isEmpty) {
      return scene;
    }
    var currentScene = scene;
    for (final pass in passes) {
      final nextScene = _applyPreparedFilter(
        scene: currentScene,
        pass: pass,
        runtimePolicy: runtimePolicy,
      );
      if (!identical(nextScene, currentScene) &&
          !identical(currentScene, scene)) {
        currentScene.dispose();
      }
      currentScene = nextScene;
    }
    return currentScene;
  }

  bool _hasOverlappingPreparedPasses(List<_PreparedFilterPass> passes) {
    if (passes.length < 2) {
      return false;
    }
    for (var index = 1; index < passes.length; index++) {
      final candidate = passes[index];
      for (var previous = 0; previous < index; previous++) {
        if (_boundsOverlap(
          candidate.layerBounds,
          passes[previous].layerBounds,
        )) {
          return true;
        }
      }
    }
    return false;
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
    required double coverageRatio,
    required _FilterRuntimePolicy runtimePolicy,
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
      coverageRatio: coverageRatio,
      runtimePolicy: runtimePolicy,
    );
    canvas.restore();
  }

  // Filter type dispatch.

  void _paintFilteredLayer({
    required Canvas canvas,
    required Picture scene,
    required FilterData data,
    required Rect filterBounds,
    required Rect layerBounds,
    required double opacity,
    required double coverageRatio,
    required _FilterRuntimePolicy runtimePolicy,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    switch (data.type) {
      case CanvasFilterType.mosaic:
        _paintMosaicFilter(
          canvas,
          scene,
          data,
          filterBounds,
          layerBounds,
          opacity,
          coverageRatio: coverageRatio,
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
          coverageRatio: coverageRatio,
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
          coverageRatio: coverageRatio,
          runtimePolicy: runtimePolicy,
          cacheType: CanvasFilterType.grayscale,
          blendMode: blendMode,
        );
      case CanvasFilterType.inversion:
        _paintColorMatrixFilter(
          canvas,
          scene,
          _inversionColorFilter,
          layerBounds,
          opacity,
          coverageRatio: coverageRatio,
          runtimePolicy: runtimePolicy,
          cacheType: CanvasFilterType.inversion,
          blendMode: blendMode,
        );
    }
  }

  // Individual filter painters.

  void _paintMosaicFilter(
    Canvas canvas,
    Picture scene,
    FilterData data,
    Rect filterBounds,
    Rect layerBounds,
    double opacity, {
    required double coverageRatio,
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
        coverageRatio: coverageRatio,
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
      coverageRatio: coverageRatio,
    );
    final mosaicOrigin = filterBounds.topLeft;
    final normalizedOffsetX = _positiveModulo(
      runtimePolicy.quantizeMosaicOffset(
        _positiveModulo(mosaicOrigin.dx, mosaicBlockSize),
        coverageRatio: coverageRatio,
      ),
      mosaicBlockSize,
    );
    final normalizedOffsetY = _positiveModulo(
      runtimePolicy.quantizeMosaicOffset(
        _positiveModulo(mosaicOrigin.dy, mosaicBlockSize),
        coverageRatio: coverageRatio,
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
      coverageRatio: coverageRatio,
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
    required double coverageRatio,
    required _FilterRuntimePolicy runtimePolicy,
    double minSigma = 0.5,
    double maxSigma = 12,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    final effectiveMinSigma = runtimePolicy.resolveAdaptiveMinSigma(
      baseMinSigma: minSigma,
      coverageRatio: coverageRatio,
    );
    final effectiveMaxSigma = runtimePolicy.resolveAdaptiveMaxSigma(
      baseMaxSigma: maxSigma,
      coverageRatio: coverageRatio,
    );
    final logicalSigma = runtimePolicy.quantizeSigma(
      _mapStrength(
        strength: data.strength,
        minValue: effectiveMinSigma,
        maxValue: effectiveMaxSigma,
      ),
      coverageRatio: coverageRatio,
    );
    final downsampleFactor = runtimePolicy.resolveBlurDownsampleFactor(
      coverageRatio: coverageRatio,
      layerBounds: layerBounds,
    );
    final blurSigma = runtimePolicy.quantizeSigma(
      runtimePolicy.resolveBlurKernelSigma(
        logicalSigma,
        downsampleFactor: downsampleFactor,
      ),
      coverageRatio: coverageRatio,
    );
    final cacheKey = _FilterImageCacheKey(
      type: CanvasFilterType.gaussianBlur,
      param0: logicalSigma,
      param1: blurSigma,
      param2: downsampleFactor,
    );
    final imageFilter = _filterCache.getOrCreate(
      cacheKey,
      () => _buildBlurImageFilter(
        blurSigma: blurSigma,
        downsampleFactor: downsampleFactor,
      ),
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

  ImageFilter _buildBlurImageFilter({
    required double blurSigma,
    required double downsampleFactor,
  }) {
    final normalizedDownsample = downsampleFactor.clamp(0.1, 1.0);
    if (normalizedDownsample >= 1) {
      return ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma);
    }

    final downsampleFilter = _buildScaleImageFilter(
      scaleX: normalizedDownsample,
      scaleY: normalizedDownsample,
    );
    final blurFilter = ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma);
    final upsampleFilter = _buildScaleImageFilter(
      scaleX: 1 / normalizedDownsample,
      scaleY: 1 / normalizedDownsample,
    );
    return ImageFilter.compose(
      outer: upsampleFilter,
      inner: ImageFilter.compose(outer: blurFilter, inner: downsampleFilter),
    );
  }

  ImageFilter _buildResampleImageFilter({required double downsampleFactor}) {
    final normalizedDownsample = downsampleFactor.clamp(0.1, 1.0);
    if (normalizedDownsample >= 1) {
      return _buildScaleImageFilter(scaleX: 1, scaleY: 1);
    }

    final downsampleFilter = _buildScaleImageFilter(
      scaleX: normalizedDownsample,
      scaleY: normalizedDownsample,
    );
    final upsampleFilter = _buildScaleImageFilter(
      scaleX: 1 / normalizedDownsample,
      scaleY: 1 / normalizedDownsample,
    );
    return ImageFilter.compose(outer: upsampleFilter, inner: downsampleFilter);
  }

  ImageFilter _buildScaleImageFilter({
    required double scaleX,
    required double scaleY,
  }) => ImageFilter.matrix(
    _buildScaleMatrix(scaleX: scaleX, scaleY: scaleY),
    filterQuality: FilterQuality.none,
  );

  void _paintColorMatrixFilter(
    Canvas canvas,
    Picture scene,
    ColorFilter colorFilter,
    Rect layerBounds,
    double opacity, {
    required double coverageRatio,
    required _FilterRuntimePolicy runtimePolicy,
    required CanvasFilterType cacheType,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    final downsampleFactor = runtimePolicy.resolveColorMatrixDownsampleFactor(
      coverageRatio: coverageRatio,
      layerBounds: layerBounds,
    );
    final imageFilter = downsampleFactor >= 1
        ? null
        : _filterCache.getOrCreate(
            _FilterImageCacheKey(
              type: cacheType,
              param0: downsampleFactor,
              param1: -1,
            ),
            () => _buildResampleImageFilter(downsampleFactor: downsampleFactor),
          );

    _diagnostics.markSaveLayer();
    _resetLayerPaint(
      opacity: opacity,
      colorFilter: colorFilter,
      imageFilter: imageFilter,
      blendMode: blendMode,
    );
    canvas
      ..saveLayer(layerBounds, _layerPaint)
      ..drawPicture(scene)
      ..restore();
  }

  // Helpers.

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
    required double coverageRatio,
    required _FilterRuntimePolicy runtimePolicy,
  }) {
    if (visibleBounds == null) {
      return clipBounds;
    }
    final viewportOutset = _resolveFilterViewportOutset(
      data: data,
      clipBounds: clipBounds,
      coverageRatio: coverageRatio,
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
    required double coverageRatio,
    required _FilterRuntimePolicy runtimePolicy,
  }) {
    final maxViewportOutset = runtimePolicy.resolveViewportOutsetCap(
      coverageRatio: coverageRatio,
    );
    switch (data.type) {
      case CanvasFilterType.gaussianBlur:
        final sigma = runtimePolicy.quantizeSigma(
          _mapStrength(
            strength: data.strength,
            minValue: runtimePolicy.gaussianMinSigma,
            maxValue: runtimePolicy.gaussianMaxSigma,
          ),
          coverageRatio: coverageRatio,
        );
        final blurRadius = (sigma * 3) + 2;
        return math.min(blurRadius, maxViewportOutset);
      case CanvasFilterType.mosaic:
        if (runtimePolicy.useFastMosaicApproximation) {
          final sigma = runtimePolicy.quantizeSigma(
            _mapStrength(
              strength: data.strength,
              minValue: runtimePolicy.mosaicPreviewMinSigma,
              maxValue: runtimePolicy.mosaicPreviewMaxSigma,
            ),
            coverageRatio: coverageRatio,
          );
          final blurRadius = (sigma * 3) + 2;
          return math.min(blurRadius, maxViewportOutset);
        }
        final blockSize = runtimePolicy.quantizeMosaicBlockSize(
          _kernelFactory.resolveMosaicBlockSize(
            strength: data.strength,
            regionSize: clipBounds.size,
          ),
          coverageRatio: coverageRatio,
        );
        return math.min(math.max(blockSize, 8), maxViewportOutset);
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
    final blurDownsampleFactor = aggressiveCpuFallback
        ? _aggressiveBlurDownsampleFactor
        : preferFastCpuFallback
        ? _interactiveBlurDownsampleFactor
        : _fullQualityBlurDownsampleFactor;
    final blurPixelBudget = aggressiveCpuFallback
        ? _aggressiveBlurPixelBudget.toDouble()
        : preferFastCpuFallback
        ? _interactiveBlurPixelBudget.toDouble()
        : _fullQualityBlurPixelBudget;
    final colorMatrixPixelBudget = aggressiveCpuFallback
        ? _aggressiveColorMatrixPixelBudget.toDouble()
        : preferFastCpuFallback
        ? _interactiveColorMatrixPixelBudget.toDouble()
        : _fullQualityColorMatrixPixelBudget;

    return _FilterRuntimePolicy(
      preferFastCpuFallback: preferFastCpuFallback,
      aggressiveCpuFallback: aggressiveCpuFallback,
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
      blurDownsampleFactor: blurDownsampleFactor,
      blurPixelBudget: blurPixelBudget,
      colorMatrixPixelBudget: colorMatrixPixelBudget,
      largeCoverageThreshold: _largeFilterCoverageThreshold,
      hugeCoverageThreshold: _hugeFilterCoverageThreshold,
      largeCoverageViewportOutsetScale: _largeCoverageViewportOutsetScale,
      hugeCoverageViewportOutsetScale: _hugeCoverageViewportOutsetScale,
      largeCoverageSigmaScale: _largeCoverageSigmaScale,
      hugeCoverageSigmaScale: _hugeCoverageSigmaScale,
      largeCoverageBlurDownsampleScale: _largeCoverageBlurDownsampleScale,
      hugeCoverageBlurDownsampleScale: _hugeCoverageBlurDownsampleScale,
      largeCoveragePixelBudgetScale: _largeCoveragePixelBudgetScale,
      hugeCoveragePixelBudgetScale: _hugeCoveragePixelBudgetScale,
      largeCoverageColorMatrixDownsample: _largeCoverageColorMatrixDownsample,
      hugeCoverageColorMatrixDownsample: _hugeCoverageColorMatrixDownsample,
      largeCoverageQuantizationScale: _largeCoverageQuantizationScale,
      hugeCoverageQuantizationScale: _hugeCoverageQuantizationScale,
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
    var hash = _fingerprintSeed;
    for (final element in elements) {
      hash = _appendFingerprint(hash, element.id.hashCode);
    }
    return hash;
  }

  int _batchIdentityFingerprint(List<ElementState> elements) {
    var hash = _identityFingerprintSeed;
    for (final element in elements) {
      hash = _appendFingerprint(hash, identityHashCode(element));
    }
    return hash;
  }

  int _appendFingerprint(int current, int value) =>
      _hashMask & ((current * 31) + value);

  int _resolveSegmentElementCount(RenderSegment segment) => switch (segment) {
    ElementBatchSegment(:final elements) => elements.length,
    FilterSegment() => 1,
    MergedFilterSegment(:final filters) => filters.length,
  };

  int _resolveSegmentIdFingerprint(RenderSegment segment) => switch (segment) {
    ElementBatchSegment(:final elements, :final idFingerprint) =>
      idFingerprint ?? _batchFingerprint(elements),
    FilterSegment(:final filterElement, :final idFingerprint) =>
      idFingerprint ??
          _appendFingerprint(_fingerprintSeed, filterElement.id.hashCode),
    MergedFilterSegment(:final filters, :final idFingerprint) =>
      idFingerprint ??
          filters.fold<int>(
            _fingerprintSeed,
            (hash, filter) =>
                _appendFingerprint(hash, _resolveSegmentIdFingerprint(filter)),
          ),
  };

  int _resolveSegmentIdentityFingerprint(RenderSegment segment) =>
      switch (segment) {
        ElementBatchSegment(:final elements, :final identityFingerprint) =>
          identityFingerprint ?? _batchIdentityFingerprint(elements),
        FilterSegment(:final filterElement, :final identityFingerprint) =>
          identityFingerprint ??
              _appendFingerprint(
                _identityFingerprintSeed,
                identityHashCode(filterElement),
              ),
        MergedFilterSegment(:final filters, :final identityFingerprint) =>
          identityFingerprint ??
              filters.fold<int>(
                _identityFingerprintSeed,
                (hash, filter) => _appendFingerprint(
                  hash,
                  _resolveSegmentIdentityFingerprint(filter),
                ),
              ),
      };

  double _resolveCoverageRatio({
    required Rect region,
    required Rect? visibleBounds,
  }) {
    if (region.isEmpty) {
      return 0;
    }
    final regionArea = region.width * region.height;
    if (regionArea <= 0) {
      return 0;
    }
    if (visibleBounds == null || visibleBounds.isEmpty) {
      return 1;
    }
    final visibleArea = visibleBounds.width * visibleBounds.height;
    if (visibleArea <= 0) {
      return 1;
    }
    final referenceArea = math.max(regionArea, visibleArea);
    return (regionArea / referenceArea).clamp(0.0, 1.0);
  }

  double _mapStrength({
    required double strength,
    required double minValue,
    required double maxValue,
  }) {
    final normalized = strength.clamp(0.0, 1.0);
    return minValue + (maxValue - minValue) * normalized;
  }

  Float64List _buildScaleMatrix({
    required double scaleX,
    required double scaleY,
  }) => Float64List.fromList(<double>[
    scaleX,
    0,
    0,
    0,
    0,
    scaleY,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);

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

enum _FilterCoverageTier { compact, large, huge }

@immutable
class _FilterRuntimePolicy {
  const _FilterRuntimePolicy({
    required this.preferFastCpuFallback,
    required this.aggressiveCpuFallback,
    required this.canUseMosaicShader,
    required this.gaussianMinSigma,
    required this.gaussianMaxSigma,
    required this.mosaicPreviewMinSigma,
    required this.mosaicPreviewMaxSigma,
    required this.maxViewportOutset,
    required this.sigmaQuantizationStep,
    required this.mosaicSizeQuantizationStep,
    required this.mosaicOffsetQuantizationStep,
    required this.blurDownsampleFactor,
    required this.blurPixelBudget,
    required this.colorMatrixPixelBudget,
    required this.largeCoverageThreshold,
    required this.hugeCoverageThreshold,
    required this.largeCoverageViewportOutsetScale,
    required this.hugeCoverageViewportOutsetScale,
    required this.largeCoverageSigmaScale,
    required this.hugeCoverageSigmaScale,
    required this.largeCoverageBlurDownsampleScale,
    required this.hugeCoverageBlurDownsampleScale,
    required this.largeCoveragePixelBudgetScale,
    required this.hugeCoveragePixelBudgetScale,
    required this.largeCoverageColorMatrixDownsample,
    required this.hugeCoverageColorMatrixDownsample,
    required this.largeCoverageQuantizationScale,
    required this.hugeCoverageQuantizationScale,
  });

  final bool preferFastCpuFallback;
  final bool aggressiveCpuFallback;
  final bool canUseMosaicShader;
  final double gaussianMinSigma;
  final double gaussianMaxSigma;
  final double mosaicPreviewMinSigma;
  final double mosaicPreviewMaxSigma;
  final double maxViewportOutset;
  final double sigmaQuantizationStep;
  final double mosaicSizeQuantizationStep;
  final double mosaicOffsetQuantizationStep;
  final double blurDownsampleFactor;
  final double blurPixelBudget;
  final double colorMatrixPixelBudget;
  final double largeCoverageThreshold;
  final double hugeCoverageThreshold;
  final double largeCoverageViewportOutsetScale;
  final double hugeCoverageViewportOutsetScale;
  final double largeCoverageSigmaScale;
  final double hugeCoverageSigmaScale;
  final double largeCoverageBlurDownsampleScale;
  final double hugeCoverageBlurDownsampleScale;
  final double largeCoveragePixelBudgetScale;
  final double hugeCoveragePixelBudgetScale;
  final double largeCoverageColorMatrixDownsample;
  final double hugeCoverageColorMatrixDownsample;
  final double largeCoverageQuantizationScale;
  final double hugeCoverageQuantizationScale;

  bool get useFastMosaicApproximation =>
      preferFastCpuFallback && !canUseMosaicShader;

  double resolveViewportOutsetCap({required double coverageRatio}) {
    if (!preferFastCpuFallback) {
      return maxViewportOutset;
    }
    final scale = switch (_resolveCoverageTier(coverageRatio)) {
      _FilterCoverageTier.compact => 1.0,
      _FilterCoverageTier.large => largeCoverageViewportOutsetScale,
      _FilterCoverageTier.huge => hugeCoverageViewportOutsetScale,
    };
    return _clampPositive(
      maxViewportOutset * scale,
      fallback: maxViewportOutset,
    );
  }

  double resolveAdaptiveMinSigma({
    required double baseMinSigma,
    required double coverageRatio,
  }) {
    final maxSigma = resolveAdaptiveMaxSigma(
      baseMaxSigma: baseMinSigma,
      coverageRatio: coverageRatio,
    );
    return math.min(baseMinSigma, maxSigma);
  }

  double resolveAdaptiveMaxSigma({
    required double baseMaxSigma,
    required double coverageRatio,
  }) {
    if (!preferFastCpuFallback) {
      return baseMaxSigma;
    }
    final scale = switch (_resolveCoverageTier(coverageRatio)) {
      _FilterCoverageTier.compact => 1.0,
      _FilterCoverageTier.large => largeCoverageSigmaScale,
      _FilterCoverageTier.huge => hugeCoverageSigmaScale,
    };
    return _clampPositive(baseMaxSigma * scale, fallback: baseMaxSigma);
  }

  double resolveBlurDownsampleFactor({
    required double coverageRatio,
    Rect? layerBounds,
  }) {
    final baseFactor = _resolveBlurDownsampleFactorBase(
      coverageRatio: coverageRatio,
    );
    final targetPixels = _resolveTargetPixels(
      coverageRatio: coverageRatio,
      baseBudget: blurPixelBudget,
    );
    return _applyAreaDownsampleBudget(
      downsampleFactor: baseFactor,
      layerBounds: layerBounds,
      targetPixels: targetPixels,
    );
  }

  double resolveColorMatrixDownsampleFactor({
    required double coverageRatio,
    Rect? layerBounds,
  }) {
    final baseFactor = _resolveColorMatrixDownsampleFactorBase(
      coverageRatio: coverageRatio,
    );
    final targetPixels = _resolveTargetPixels(
      coverageRatio: coverageRatio,
      baseBudget: colorMatrixPixelBudget,
    );
    return _applyAreaDownsampleBudget(
      downsampleFactor: baseFactor,
      layerBounds: layerBounds,
      targetPixels: targetPixels,
    );
  }

  double quantizeSigma(double sigma, {double coverageRatio = 0}) => _quantize(
    sigma,
    sigmaQuantizationStep * _resolveQuantizationScale(coverageRatio),
  );

  double quantizeMosaicBlockSize(double value, {double coverageRatio = 0}) {
    final quantized = _quantize(
      value,
      mosaicSizeQuantizationStep * _resolveQuantizationScale(coverageRatio),
    );
    if (quantized.isFinite && quantized > 0) {
      return quantized;
    }
    if (value.isFinite && value > 0) {
      return value;
    }
    return 1;
  }

  double quantizeMosaicOffset(double value, {double coverageRatio = 0}) =>
      _quantize(
        value,
        mosaicOffsetQuantizationStep * _resolveQuantizationScale(coverageRatio),
      );

  double resolveBlurKernelSigma(
    double logicalSigma, {
    required double downsampleFactor,
  }) {
    final downsample = downsampleFactor;
    if (downsample >= 1 || !downsample.isFinite) {
      return logicalSigma;
    }
    return logicalSigma * downsample;
  }

  _FilterCoverageTier _resolveCoverageTier(double coverageRatio) {
    if (coverageRatio >= hugeCoverageThreshold) {
      return _FilterCoverageTier.huge;
    }
    if (coverageRatio >= largeCoverageThreshold) {
      return _FilterCoverageTier.large;
    }
    return _FilterCoverageTier.compact;
  }

  double _resolveQuantizationScale(double coverageRatio) {
    if (!preferFastCpuFallback) {
      return 1;
    }
    return switch (_resolveCoverageTier(coverageRatio)) {
      _FilterCoverageTier.compact => 1,
      _FilterCoverageTier.large => largeCoverageQuantizationScale,
      _FilterCoverageTier.huge => hugeCoverageQuantizationScale,
    };
  }

  double _resolveBlurDownsampleFactorBase({required double coverageRatio}) {
    if (!preferFastCpuFallback) {
      return blurDownsampleFactor.clamp(0.1, 1.0);
    }
    final scale = switch (_resolveCoverageTier(coverageRatio)) {
      _FilterCoverageTier.compact => 1.0,
      _FilterCoverageTier.large => largeCoverageBlurDownsampleScale,
      _FilterCoverageTier.huge => hugeCoverageBlurDownsampleScale,
    };
    final scaled = blurDownsampleFactor * scale;
    final lowerBound = aggressiveCpuFallback ? 0.25 : 0.4;
    return scaled.clamp(lowerBound, 1.0);
  }

  double _resolveColorMatrixDownsampleFactorBase({
    required double coverageRatio,
  }) {
    if (!preferFastCpuFallback) {
      return 1;
    }
    return switch (_resolveCoverageTier(coverageRatio)) {
      _FilterCoverageTier.compact => 1,
      _FilterCoverageTier.large => largeCoverageColorMatrixDownsample,
      _FilterCoverageTier.huge => hugeCoverageColorMatrixDownsample,
    };
  }

  double _resolveTargetPixels({
    required double coverageRatio,
    required double baseBudget,
  }) {
    if (!baseBudget.isFinite || baseBudget <= 0) {
      return baseBudget;
    }
    return baseBudget * _resolvePixelBudgetScale(coverageRatio);
  }

  double _resolvePixelBudgetScale(double coverageRatio) =>
      switch (_resolveCoverageTier(coverageRatio)) {
        _FilterCoverageTier.compact => 1.0,
        _FilterCoverageTier.large => largeCoveragePixelBudgetScale,
        _FilterCoverageTier.huge => hugeCoveragePixelBudgetScale,
      };

  double _applyAreaDownsampleBudget({
    required double downsampleFactor,
    required Rect? layerBounds,
    required double targetPixels,
  }) {
    final normalizedFactor = downsampleFactor.clamp(0.1, 1.0);
    if (!targetPixels.isFinite ||
        targetPixels <= 0 ||
        layerBounds == null ||
        layerBounds.isEmpty) {
      return normalizedFactor;
    }
    final layerArea = layerBounds.width * layerBounds.height;
    if (!layerArea.isFinite || layerArea <= 0) {
      return normalizedFactor;
    }
    final areaBudgetFactor = math.sqrt(targetPixels / layerArea);
    if (!areaBudgetFactor.isFinite || areaBudgetFactor <= 0) {
      return normalizedFactor;
    }
    return math.min(normalizedFactor, areaBudgetFactor.clamp(0.1, 1.0));
  }

  double _clampPositive(double value, {required double fallback}) {
    if (value.isFinite && value > 0) {
      return value;
    }
    return fallback;
  }

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

// Cache keys.

@immutable
class _SegmentRangeSignature {
  const _SegmentRangeSignature({
    required this.idFingerprint,
    required this.identityFingerprint,
    required this.elementCount,
    required this.segmentCount,
  });

  final int idFingerprint;
  final int identityFingerprint;
  final int elementCount;
  final int segmentCount;
}

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
    required this.idFingerprint,
    required this.identityFingerprint,
    required this.elementCount,
  });

  /// Signature intentionally excludes document version so stable non-filter
  /// batches survive filter-only document updates (for example strength drags).
  final _BatchPictureContextSignature contextSignature;

  /// Stable-id fingerprint for the batch element order.
  final int idFingerprint;

  /// Object-identity fingerprint for the batch element snapshots.
  final int identityFingerprint;

  /// Number of elements in the batch.
  final int elementCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _BatchPictureCacheKey &&
          other.contextSignature == contextSignature &&
          other.idFingerprint == idFingerprint &&
          other.identityFingerprint == identityFingerprint &&
          other.elementCount == elementCount;

  @override
  int get hashCode => Object.hash(
    contextSignature,
    idFingerprint,
    identityFingerprint,
    elementCount,
  );
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
    required this.idFingerprint,
    required this.identityFingerprint,
    required this.elementCount,
    required this.segmentCount,
    required this.visibleBoundsSignature,
    required this.interactionPreview,
    required this.aggressiveCpuFallback,
  });

  final _BatchPictureContextSignature contextSignature;

  /// Stable-id fingerprint for all segments in the cached prefix range.
  final int idFingerprint;

  /// Object-identity fingerprint for all segments in the cached prefix range.
  final int identityFingerprint;

  /// Total number of elements represented by the prefix range.
  final int elementCount;

  /// Number of render segments represented by the prefix range.
  final int segmentCount;
  final _VisibleBoundsSignature visibleBoundsSignature;
  final bool interactionPreview;
  final bool aggressiveCpuFallback;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PrefixSceneCacheKey &&
          other.contextSignature == contextSignature &&
          other.idFingerprint == idFingerprint &&
          other.identityFingerprint == identityFingerprint &&
          other.elementCount == elementCount &&
          other.segmentCount == segmentCount &&
          other.visibleBoundsSignature == visibleBoundsSignature &&
          other.interactionPreview == interactionPreview &&
          other.aggressiveCpuFallback == aggressiveCpuFallback;

  @override
  int get hashCode => Object.hash(
    contextSignature,
    idFingerprint,
    identityFingerprint,
    elementCount,
    segmentCount,
    visibleBoundsSignature,
    interactionPreview,
    aggressiveCpuFallback,
  );
}

class _CachedPicture {
  _CachedPicture({required this.picture});

  final Picture picture;
  var _activeReaders = 0;
  var _evicted = false;
  var _disposed = false;

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
    required this.coverageRatio,
  });

  final FilterData data;
  final _ClipInfo clip;
  final Rect layerBounds;
  final double opacity;
  final double coverageRatio;
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

  /// Applies the clip to [canvas] using the cheapest available method.
  void applyTo(Canvas canvas) {
    if (path != null) {
      canvas.clipPath(path!);
    } else {
      canvas.clipRect(bounds);
    }
  }
}

// Cached color-filter constants.

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
