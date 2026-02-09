import 'dart:ui';

import '../../draw/elements/types/filter/filter_data.dart';
import '../../draw/models/element_state.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/types/element_style.dart';
import 'filter_shader_manager.dart';

typedef SceneElementPainter =
    void Function(Canvas canvas, ElementState element);

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

    sceneCanvas.save();
    if (element.rotation != 0) {
      sceneCanvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    sceneCanvas.clipRect(
      Rect.fromLTWH(rect.minX, rect.minY, rect.width, rect.height),
    );

    switch (data.type) {
      case CanvasFilterType.mosaic:
        _paintMosaicFilter(sceneCanvas, lowerScene, data, rect);
      case CanvasFilterType.gaussianBlur:
        _paintBlurFilter(sceneCanvas, lowerScene, data);
      case CanvasFilterType.grayscale:
        _paintColorMatrixFilter(sceneCanvas, lowerScene, _grayscaleMatrix);
      case CanvasFilterType.inversion:
        _paintColorMatrixFilter(sceneCanvas, lowerScene, _inversionMatrix);
    }

    sceneCanvas.restore();
    return recorder.endRecording();
  }

  void _paintMosaicFilter(
    Canvas canvas,
    Picture lowerScene,
    FilterData data,
    DrawRect rect,
  ) {
    final shaderFilter = FilterShaderManager.instance.createMosaicFilter(
      strength: data.strength,
      regionSize: Size(rect.width, rect.height),
    );
    if (shaderFilter != null) {
      canvas
        ..saveLayer(
          Rect.fromLTWH(rect.minX, rect.minY, rect.width, rect.height),
          Paint()..imageFilter = shaderFilter,
        )
        ..drawPicture(lowerScene)
        ..restore();
      return;
    }

    _paintBlurFilter(canvas, lowerScene, data, minSigma: 4, maxSigma: 24);
  }

  void _paintBlurFilter(
    Canvas canvas,
    Picture lowerScene,
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
        null,
        Paint()..imageFilter = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      )
      ..drawPicture(lowerScene)
      ..restore();
  }

  void _paintColorMatrixFilter(
    Canvas canvas,
    Picture lowerScene,
    List<double> matrix,
  ) {
    canvas
      ..saveLayer(null, Paint()..colorFilter = ColorFilter.matrix(matrix))
      ..drawPicture(lowerScene)
      ..restore();
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
