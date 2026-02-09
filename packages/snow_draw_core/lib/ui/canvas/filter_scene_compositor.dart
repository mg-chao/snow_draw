import 'dart:math' as math;
import 'dart:ui';

import '../../draw/elements/types/filter/filter_data.dart';
import '../../draw/models/element_state.dart';
import '../../draw/services/log/log_service.dart';
import '../../draw/types/element_style.dart';
import 'filter_shader_manager.dart';

typedef SceneElementPainter =
    void Function(Canvas canvas, ElementState element);

final ModuleLogger _filterSceneLog = LogService.fallback.render;

/// Composites element scenes while honoring true z-order semantics for filters.
class FilterSceneCompositor {
  const FilterSceneCompositor();

  void paintElements({
    required Canvas canvas,
    required List<ElementState> elements,
    required SceneElementPainter paintElement,
  }) {
    if (elements.isEmpty) {
      return;
    }

    final hasFilters = elements.any((element) => element.data is FilterData);
    if (!hasFilters) {
      for (final element in elements) {
        paintElement(canvas, element);
      }
      return;
    }

    Picture? accumulated;
    for (final element in elements) {
      final data = element.data;
      if (data is! FilterData) {
        accumulated = _appendElement(
          lowerScene: accumulated,
          element: element,
          paintElement: paintElement,
        );
        continue;
      }
      accumulated = _appendFilter(
        lowerScene: accumulated,
        element: element,
        data: data,
      );
    }

    if (accumulated != null) {
      canvas.drawPicture(accumulated);
    }
  }

  Picture _appendElement({
    required Picture? lowerScene,
    required ElementState element,
    required SceneElementPainter paintElement,
  }) {
    final recorder = PictureRecorder();
    final sceneCanvas = Canvas(recorder);
    if (lowerScene != null) {
      sceneCanvas.drawPicture(lowerScene);
    }
    paintElement(sceneCanvas, element);
    return recorder.endRecording();
  }

  Picture _appendFilter({
    required Picture? lowerScene,
    required ElementState element,
    required FilterData data,
  }) {
    final recorder = PictureRecorder();
    final sceneCanvas = Canvas(recorder);
    if (lowerScene == null) {
      return recorder.endRecording();
    }

    sceneCanvas.drawPicture(lowerScene);

    final rect = element.rect;
    if (rect.width <= 0 || rect.height <= 0) {
      return recorder.endRecording();
    }
    final opacity = element.opacity.clamp(0.0, 1.0);
    if (opacity <= 0) {
      return recorder.endRecording();
    }

    final clipPath = _buildFilterClipPath(element);
    final layerBounds = clipPath.getBounds();
    if (layerBounds.isEmpty) {
      return recorder.endRecording();
    }

    sceneCanvas.save();
    sceneCanvas.clipPath(clipPath);

    switch (data.type) {
      case CanvasFilterType.mosaic:
        _paintMosaicFilter(sceneCanvas, lowerScene, data, layerBounds, opacity);
      case CanvasFilterType.gaussianBlur:
        _paintBlurFilter(sceneCanvas, lowerScene, layerBounds, opacity, data);
      case CanvasFilterType.grayscale:
        _paintColorMatrixFilter(
          sceneCanvas,
          lowerScene,
          _grayscaleMatrix,
          layerBounds,
          opacity,
        );
      case CanvasFilterType.inversion:
        _paintColorMatrixFilter(
          sceneCanvas,
          lowerScene,
          _inversionMatrix,
          layerBounds,
          opacity,
        );
    }

    sceneCanvas.restore();
    return recorder.endRecording();
  }

  void _paintMosaicFilter(
    Canvas canvas,
    Picture lowerScene,
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
      canvas
        ..saveLayer(
          layerBounds,
          _buildFilteredLayerPaint(opacity: opacity, imageFilter: shaderFilter),
        )
        ..drawPicture(lowerScene)
        ..restore();
      return;
    }

    _paintMosaicFallback(canvas, lowerScene, data, layerBounds, opacity);
  }

  void _paintMosaicFallback(
    Canvas canvas,
    Picture lowerScene,
    FilterData data,
    Rect layerBounds,
    double opacity,
  ) {
    final width = layerBounds.width.ceil();
    final height = layerBounds.height.ceil();
    if (width <= 0 || height <= 0) {
      return;
    }

    final offset = layerBounds.topLeft;
    final imageRecorder = PictureRecorder();
    final imageCanvas = Canvas(imageRecorder);
    imageCanvas
      ..translate(-offset.dx, -offset.dy)
      ..drawPicture(lowerScene);
    final rasterPicture = imageRecorder.endRecording();

    Image sourceImage;
    try {
      sourceImage = rasterPicture.toImageSync(width, height);
    } on Exception catch (error, stackTrace) {
      _filterSceneLog.warning('Failed to rasterize mosaic fallback picture', {
        'error': error,
        'stackTrace': stackTrace,
      });
      _paintBlurFilter(
        canvas,
        lowerScene,
        layerBounds,
        opacity,
        data,
        minSigma: 4,
        maxSigma: 24,
      );
      return;
    } finally {
      rasterPicture.dispose();
    }

    final blockSize = FilterShaderManager.instance.resolveMosaicBlockSize(
      strength: data.strength,
      regionSize: layerBounds.size,
    );
    final sampledWidth = math.max(1, (width / blockSize).ceil());
    final sampledHeight = math.max(1, (height / blockSize).ceil());

    Image pixelatedImage;
    try {
      final downsampleRecorder = PictureRecorder();
      final downsampleCanvas = Canvas(downsampleRecorder);
      downsampleCanvas.drawImageRect(
        sourceImage,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Rect.fromLTWH(0, 0, sampledWidth.toDouble(), sampledHeight.toDouble()),
        Paint()..filterQuality = FilterQuality.none,
      );
      final downsamplePicture = downsampleRecorder.endRecording();
      try {
        pixelatedImage = downsamplePicture.toImageSync(
          sampledWidth,
          sampledHeight,
        );
      } finally {
        downsamplePicture.dispose();
      }
    } on Exception catch (error, stackTrace) {
      sourceImage.dispose();
      _filterSceneLog.warning('Failed to downsample mosaic fallback image', {
        'error': error,
        'stackTrace': stackTrace,
      });
      _paintBlurFilter(
        canvas,
        lowerScene,
        layerBounds,
        opacity,
        data,
        minSigma: 4,
        maxSigma: 24,
      );
      return;
    }
    sourceImage.dispose();

    canvas.saveLayer(layerBounds, _buildFilteredLayerPaint(opacity: opacity));
    try {
      final paint = Paint()..filterQuality = FilterQuality.none;
      canvas.drawImageRect(
        pixelatedImage,
        Rect.fromLTWH(0, 0, sampledWidth.toDouble(), sampledHeight.toDouble()),
        Rect.fromLTWH(
          offset.dx,
          offset.dy,
          width.toDouble(),
          height.toDouble(),
        ),
        paint,
      );
    } finally {
      canvas.restore();
      pixelatedImage.dispose();
    }
  }

  void _paintBlurFilter(
    Canvas canvas,
    Picture lowerScene,
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
    canvas
      ..saveLayer(
        layerBounds,
        _buildFilteredLayerPaint(
          opacity: opacity,
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        ),
      )
      ..drawPicture(lowerScene)
      ..restore();
  }

  void _paintColorMatrixFilter(
    Canvas canvas,
    Picture lowerScene,
    List<double> matrix,
    Rect layerBounds,
    double opacity,
  ) {
    canvas
      ..saveLayer(
        layerBounds,
        _buildFilteredLayerPaint(
          opacity: opacity,
          colorFilter: ColorFilter.matrix(matrix),
        ),
      )
      ..drawPicture(lowerScene)
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

const filterSceneCompositor = FilterSceneCompositor();
