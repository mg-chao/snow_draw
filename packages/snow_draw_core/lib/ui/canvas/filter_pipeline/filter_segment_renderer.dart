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

/// Renders element scenes with filter segments.
///
/// Unlike per-element compositing, this pipeline scales with the number of
/// filter passes and contiguous element batches.
class FilterSegmentRenderer {
  FilterSegmentRenderer({FilterSegmentBuilder? segmentBuilder})
    : _segmentBuilder = segmentBuilder ?? const FilterSegmentBuilder();

  static const _filterImageCacheLimit = 256;
  static const _clipInfoCacheLimit = 512;

  final FilterSegmentBuilder _segmentBuilder;
  final _clipInfoCache = LruCache<_FilterClipCacheKey, _ClipInfo>(
    maxEntries: _clipInfoCacheLimit,
  );
  final _filterCache = LruCache<_FilterImageCacheKey, ImageFilter>(
    maxEntries: _filterImageCacheLimit,
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

  /// Clears internal caches.
  void clearCaches() {
    _clipInfoCache.clear();
    _filterCache.clear();
  }

  /// Paints [elements] in z-order using segmented filter
  /// composition.
  void paint({
    required Canvas canvas,
    required List<ElementState> elements,
    required SceneElementPainter paintElement,
  }) {
    _diagnostics.beginFrame();
    if (elements.isEmpty) {
      _diagnostics.endFrame();
      return;
    }

    final segments = _segmentBuilder.build(elements);
    if (segments.isEmpty) {
      _diagnostics.endFrame();
      return;
    }

    final hasFilter = segments.any(
      (s) => s is FilterSegment || s is MergedFilterSegment,
    );
    if (!hasFilter) {
      final first = segments.isEmpty ? null : segments.first;
      if (first is ElementBatchSegment) {
        for (final element in first.elements) {
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
    final pending = <Picture>[];

    Picture flattenPending() {
      assert(pending.isNotEmpty, 'pending must not be empty');
      if (pending.length == 1) {
        return pending.removeAt(0);
      }
      _diagnostics.markPictureRecorder();
      final recorder = PictureRecorder();
      final mergeCanvas = Canvas(recorder);
      for (final p in pending) {
        mergeCanvas.drawPicture(p);
      }
      pending.clear();
      return recorder.endRecording();
    }

    for (final segment in segments) {
      if (segment is ElementBatchSegment) {
        if (segment.elements.isEmpty) {
          continue;
        }
        _diagnostics.markBatch();
        pending.add(_recordBatch(segment.elements, paintElement));
        continue;
      }

      if (pending.isEmpty) {
        continue;
      }

      final scene = flattenPending();

      if (segment is FilterSegment) {
        pending.add(
          _applyFilter(
            scene: scene,
            filterElement: segment.filterElement,
            data: segment.filterData,
          ),
        );
        continue;
      }

      if (segment is MergedFilterSegment) {
        pending.add(
          _applyMergedFilter(scene: scene, merged: segment),
        );
      }
    }

    for (final p in pending) {
      canvas.drawPicture(p);
    }
    _diagnostics.endFrame();
  }

  Picture _recordBatch(
    List<ElementState> elements,
    SceneElementPainter paintElement,
  ) {
    _diagnostics.markPictureRecorder();
    final recorder = PictureRecorder();
    final batchCanvas = Canvas(recorder);
    for (final element in elements) {
      paintElement(batchCanvas, element);
    }
    return recorder.endRecording();
  }

  // ── Single-filter pass ──────────────────────────────────

  Picture _applyFilter({
    required Picture scene,
    required ElementState filterElement,
    required FilterData data,
  }) {
    final rect = filterElement.rect;
    if (rect.width <= 0 || rect.height <= 0) {
      return scene;
    }

    final opacity = filterElement.opacity.clamp(0.0, 1.0);
    if (opacity <= 0) {
      return scene;
    }

    final clip = _resolveClipInfo(filterElement);
    final layerBounds = clip.bounds;
    if (layerBounds.isEmpty) {
      return scene;
    }

    _diagnostics.markPictureRecorder();
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)..drawPicture(scene);

    _applyClippedFilter(
      canvas: canvas,
      scene: scene,
      clip: clip,
      data: data,
      layerBounds: layerBounds,
      opacity: opacity,
    );

    _diagnostics.markFilterPass();
    return recorder.endRecording();
  }

  // ── Merged-filter pass ──────────────────────────────────

  /// Applies a group of same-type filters with fewer
  /// `PictureRecorder` allocations.
  ///
  /// Non-overlapping filters share a single recorder. When a filter
  /// overlaps a previous one in the group, the accumulated picture
  /// is finalized so the next filter sees the correct intermediate
  /// result (important for idempotent filters like double-inversion).
  Picture _applyMergedFilter({
    required Picture scene,
    required MergedFilterSegment merged,
  }) {
    var currentScene = scene;
    PictureRecorder? recorder;
    Canvas? canvas;

    // Track individual filter bounds instead of a single expanding
    // rect. This avoids false-positive overlaps when two distant
    // filters are separated by a third that expanded the union rect
    // to cover both.
    final coveredRegions = <Rect>[];

    void finishRecorder() {
      if (recorder == null) {
        return;
      }
      currentScene = recorder!.endRecording();
      recorder = null;
      canvas = null;
      coveredRegions.clear();
    }

    void ensureRecorder() {
      if (recorder != null) {
        return;
      }
      _diagnostics.markPictureRecorder();
      recorder = PictureRecorder();
      canvas = Canvas(recorder!)..drawPicture(currentScene);
    }

    for (final filter in merged.filters) {
      final element = filter.filterElement;
      final data = filter.filterData;
      final rect = element.rect;
      if (rect.width <= 0 || rect.height <= 0) {
        continue;
      }

      final opacity = element.opacity.clamp(0.0, 1.0);
      if (opacity <= 0) {
        continue;
      }

      final clip = _resolveClipInfo(element);
      final layerBounds = clip.bounds;
      if (layerBounds.isEmpty) {
        continue;
      }

      // Overlapping regions need a fresh recorder so the
      // second filter reads the result of the first.
      if (_anyOverlaps(coveredRegions, layerBounds)) {
        finishRecorder();
      }

      ensureRecorder();

      _applyClippedFilter(
        canvas: canvas!,
        scene: currentScene,
        clip: clip,
        data: data,
        layerBounds: layerBounds,
        opacity: opacity,
      );

      _diagnostics.markFilterPass();
      coveredRegions.add(layerBounds);
    }

    finishRecorder();
    return currentScene;
  }

  // ── Clipped filter application ────────────────────────

  /// Applies a single filter within a clip region.
  ///
  /// When [opacity] is 1.0, uses `BlendMode.src` inside the
  /// `saveLayer` to replace the clipped region in one pass instead
  /// of the dstOut + plus two-pass compositing.
  /// Uses `clipRect` for axis-aligned clips to avoid the more
  /// expensive `clipPath` rasterization.
  void _applyClippedFilter({
    required Canvas canvas,
    required Picture scene,
    required _ClipInfo clip,
    required FilterData data,
    required Rect layerBounds,
    required double opacity,
  }) {
    if (opacity >= 1.0) {
      // Fast path: full opacity — a single saveLayer with src blend
      // replaces the clipped region without a separate dstOut pass.
      canvas.save();
      clip.applyTo(canvas);
      _paintFilteredLayer(
        canvas: canvas,
        scene: scene,
        data: data,
        layerBounds: layerBounds,
        opacity: 1,
        blendMode: BlendMode.src,
      );
      canvas.restore();
      return;
    }

    // Partial opacity: punch a hole with dstOut, then composite
    // the filtered result with plus.
    canvas.save();
    clip.applyTo(canvas);
    canvas.drawColor(
      Color.fromRGBO(0, 0, 0, opacity),
      BlendMode.dstOut,
    );
    _paintFilteredLayer(
      canvas: canvas,
      scene: scene,
      data: data,
      layerBounds: layerBounds,
      opacity: opacity,
      blendMode: BlendMode.plus,
    );
    canvas.restore();
  }

  // ── Filter type dispatch ────────────────────────────────

  void _paintFilteredLayer({
    required Canvas canvas,
    required Picture scene,
    required FilterData data,
    required Rect layerBounds,
    required double opacity,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    switch (data.type) {
      case CanvasFilterType.mosaic:
        _paintMosaicFilter(
          canvas,
          scene,
          data,
          layerBounds,
          opacity,
          blendMode: blendMode,
        );
      case CanvasFilterType.gaussianBlur:
        _paintBlurFilter(
          canvas,
          scene,
          layerBounds,
          opacity,
          data,
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
    Rect layerBounds,
    double opacity, {
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    final cacheKey = _FilterImageCacheKey(
      type: CanvasFilterType.mosaic,
      param0: data.strength,
      param1: layerBounds.width,
      param2: layerBounds.height,
      param3: layerBounds.left,
      param4: layerBounds.top,
    );
    final shaderFilter = _filterCache.get(cacheKey) ??
        FilterShaderManager.instance.createMosaicFilter(
          strength: data.strength,
          regionSize: layerBounds.size,
          regionOffset: layerBounds.topLeft,
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
    double minSigma = 0.5,
    double maxSigma = 12,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    final sigma = _mapStrength(
      strength: data.strength,
      minValue: minSigma,
      maxValue: maxSigma,
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

  /// Returns `true` when [candidate] overlaps any rect in [regions].
  ///
  /// Linear scan is fine here because merged filter groups are
  /// typically small (single digits).
  static bool _anyOverlaps(List<Rect> regions, Rect candidate) {
    for (final r in regions) {
      if (r.overlaps(candidate)) {
        return true;
      }
    }
    return false;
  }

  _ClipInfo _resolveClipInfo(ElementState element) {
    final key = _FilterClipCacheKey(
      id: element.id,
      rect: element.rect,
      rotation: element.rotation,
    );
    return _clipInfoCache.getOrCreate(
      key,
      () => _buildClipInfo(element),
    );
  }

  _ClipInfo _buildClipInfo(ElementState element) {
    final rect = element.rect;
    final uiRect = Rect.fromLTWH(
      rect.minX,
      rect.minY,
      rect.width,
      rect.height,
    );
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

  double _mapStrength({
    required double strength,
    required double minValue,
    required double maxValue,
  }) {
    final normalized = strength.clamp(0.0, 1.0);
    return minValue + (maxValue - minValue) * normalized;
  }
}

// ── Cache keys ──────────────────────────────────────────

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
  int get hashCode =>
      Object.hash(type, param0, param1, param2, param3, param4);
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
