import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

import '../../../draw/elements/types/filter/filter_data.dart';
import '../../../draw/models/element_state.dart';
import '../../../draw/types/draw_rect.dart';
import '../../../draw/types/element_style.dart';
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

  final FilterSegmentBuilder _segmentBuilder;
  final _clipPathCache = <_FilterClipCacheKey, Path>{};
  final _filterCache = <_FilterImageCacheKey, ImageFilter>{};
  final _diagnostics = FilterRenderDiagnosticsCollector();

  /// Last completed frame diagnostics.
  FilterRenderDiagnostics get lastDiagnostics => _diagnostics.lastFrame;

  /// Clears internal caches.
  void clearCaches() {
    _clipPathCache.clear();
    _filterCache.clear();
  }

  /// Paints [elements] in z-order using segmented filter composition.
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

    final hasFilter = segments.any((segment) => segment is FilterSegment);
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

    Picture? accumulated;
    for (final segment in segments) {
      if (segment is ElementBatchSegment) {
        if (segment.elements.isEmpty) {
          continue;
        }
        _diagnostics.markBatch();
        final batchPicture = _recordBatch(segment.elements, paintElement);
        accumulated = _mergeScene(base: accumulated, overlay: batchPicture);
        continue;
      }

      if (segment is FilterSegment && accumulated != null) {
        accumulated = _applyFilter(
          scene: accumulated,
          filterElement: segment.filterElement,
          data: segment.filterData,
        );
      }
    }

    if (accumulated != null) {
      canvas.drawPicture(accumulated);
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

  Picture _mergeScene({required Picture? base, required Picture overlay}) {
    if (base == null) {
      return overlay;
    }
    _diagnostics.markPictureRecorder();
    final recorder = PictureRecorder();
    Canvas(recorder)
      ..drawPicture(base)
      ..drawPicture(overlay);
    return recorder.endRecording();
  }

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

    final clipPath = _resolveClipPath(filterElement);
    final layerBounds = clipPath.getBounds();
    if (layerBounds.isEmpty) {
      return scene;
    }

    _diagnostics.markPictureRecorder();
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawPicture(scene)
      ..save()
      ..clipPath(clipPath);

    switch (data.type) {
      case CanvasFilterType.mosaic:
        _paintMosaicFilter(canvas, scene, data, layerBounds, opacity);
      case CanvasFilterType.gaussianBlur:
        _paintBlurFilter(canvas, scene, layerBounds, opacity, data);
      case CanvasFilterType.grayscale:
        _paintColorMatrixFilter(
          canvas,
          scene,
          _grayscaleMatrix,
          layerBounds,
          opacity,
        );
      case CanvasFilterType.inversion:
        _paintColorMatrixFilter(
          canvas,
          scene,
          _inversionMatrix,
          layerBounds,
          opacity,
        );
    }

    canvas.restore();
    _diagnostics.markFilterPass();
    return recorder.endRecording();
  }

  void _paintMosaicFilter(
    Canvas canvas,
    Picture scene,
    FilterData data,
    Rect layerBounds,
    double opacity,
  ) {
    final shaderFilter = FilterShaderManager.instance.createMosaicFilter(
      strength: data.strength,
      regionSize: layerBounds.size,
      regionOffset: layerBounds.topLeft,
    );
    if (shaderFilter != null) {
      _diagnostics.markSaveLayer();
      canvas
        ..saveLayer(
          layerBounds,
          _buildFilteredLayerPaint(opacity: opacity, imageFilter: shaderFilter),
        )
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
  }) {
    final sigma = _mapStrength(
      strength: data.strength,
      minValue: minSigma,
      maxValue: maxSigma,
    );
    final cacheKey = _FilterImageCacheKey(
      type: CanvasFilterType.gaussianBlur,
      strength: data.strength,
      bounds: layerBounds,
      sigmaX: sigma,
      sigmaY: sigma,
      shaderSupported: FilterShaderManager.instance.isShaderFilterSupported,
    );
    final imageFilter = _filterCache.putIfAbsent(
      cacheKey,
      () => ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );

    _diagnostics.markSaveLayer();
    canvas
      ..saveLayer(
        layerBounds,
        _buildFilteredLayerPaint(opacity: opacity, imageFilter: imageFilter),
      )
      ..drawPicture(scene)
      ..restore();
  }

  void _paintColorMatrixFilter(
    Canvas canvas,
    Picture scene,
    List<double> matrix,
    Rect layerBounds,
    double opacity,
  ) {
    _diagnostics.markSaveLayer();
    canvas
      ..saveLayer(
        layerBounds,
        _buildFilteredLayerPaint(
          opacity: opacity,
          colorFilter: ColorFilter.matrix(matrix),
        ),
      )
      ..drawPicture(scene)
      ..restore();
  }

  Paint _buildFilteredLayerPaint({
    required double opacity,
    ImageFilter? imageFilter,
    ColorFilter? colorFilter,
  }) {
    final paint = Paint();
    if (imageFilter != null) {
      paint.imageFilter = imageFilter;
    }
    if (colorFilter != null) {
      paint.colorFilter = colorFilter;
    }
    if (opacity < 1) {
      paint.color = Color.fromRGBO(255, 255, 255, opacity);
    }
    return paint;
  }

  Path _resolveClipPath(ElementState element) {
    final key = _FilterClipCacheKey(
      id: element.id,
      rect: element.rect,
      rotation: element.rotation,
    );
    final cached = _clipPathCache[key];
    if (cached != null) {
      return cached;
    }
    final built = _buildFilterClipPath(element);
    _clipPathCache[key] = built;
    return built;
  }

  Path _buildFilterClipPath(ElementState element) {
    final rect = element.rect;
    if (element.rotation == 0) {
      return Path()
        ..addRect(Rect.fromLTWH(rect.minX, rect.minY, rect.width, rect.height));
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

    return Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..close();
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

@immutable
class _FilterImageCacheKey {
  const _FilterImageCacheKey({
    required this.type,
    required this.strength,
    required this.bounds,
    required this.sigmaX,
    required this.sigmaY,
    required this.shaderSupported,
  });

  final CanvasFilterType type;
  final double strength;
  final Rect bounds;
  final double sigmaX;
  final double sigmaY;
  final bool shaderSupported;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FilterImageCacheKey &&
          other.type == type &&
          other.strength == strength &&
          other.bounds == bounds &&
          other.sigmaX == sigmaX &&
          other.sigmaY == sigmaY &&
          other.shaderSupported == shaderSupported;

  @override
  int get hashCode =>
      Object.hash(type, strength, bounds, sigmaX, sigmaY, shaderSupported);
}

const _grayscaleMatrix = <double>[
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

const _inversionMatrix = <double>[
  -1,
  0,
  0,
  0,
  255,
  0,
  -1,
  0,
  0,
  255,
  0,
  0,
  -1,
  0,
  255,
  0,
  0,
  0,
  1,
  0,
];
