import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:snow_draw_core/snow_draw_core.dart';

import '../extensions/draw_color_extensions.dart';
import 'scene/scene_primitive_renderer.dart';

final ModuleLogger _renderFallbackLog = LogService.fallback.render;

enum _SceneRenderResult {
  rendered,
  missingDefinition,
  missingSceneEncoder,
  unsupported,
  failed,
}

/// Flutter element renderer.
///
/// Renders elements via backend-agnostic scene primitives.
class ElementRenderer {
  const ElementRenderer();

  static final _selectionOutlinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  static final _selectionHandleFillPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  static final _selectionHandleStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  static const _unknownElementColor = Color(0xFFB00020);
  static const _selectionDashLength = 6.0;
  static const _selectionGapLength = 4.0;
  static const _sceneRenderer = ScenePrimitiveRenderer();

  double _effectiveScale(double scaleFactor) =>
      scaleFactor == 0 ? 1.0 : scaleFactor;

  DrawRect _inflateBounds(DrawRect bounds, double amount) => DrawRect(
    minX: bounds.minX - amount,
    minY: bounds.minY - amount,
    maxX: bounds.maxX + amount,
    maxY: bounds.maxY + amount,
  );

  DrawRect _selectionBounds(
    DrawRect bounds,
    SelectionConfig config,
    double scale,
  ) => _inflateBounds(bounds, config.padding / scale);

  Rect _toRect(DrawRect rect) =>
      Rect.fromLTWH(rect.minX, rect.minY, rect.width, rect.height);

  void _applyRotation(
    Canvas canvas, {
    double? rotation,
    DrawPoint? rotationCenter,
  }) {
    if (rotation == null || rotation == 0 || rotationCenter == null) {
      return;
    }
    canvas
      ..translate(rotationCenter.x, rotationCenter.y)
      ..rotate(rotation)
      ..translate(-rotationCenter.x, -rotationCenter.y);
  }

  void _renderUnknownElement(
    Canvas canvas,
    ElementState element,
    double scaleFactor,
  ) {
    final rect = _toRect(element.rect);
    final scale = _effectiveScale(scaleFactor);
    final strokeWidth = (1.5 / scale).clamp(0.5, 4.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = _unknownElementColor
      ..isAntiAlias = true;
    canvas
      ..drawRect(rect, paint)
      ..drawLine(rect.topLeft, rect.bottomRight, paint)
      ..drawLine(rect.topRight, rect.bottomLeft, paint);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        final segment = metric.extractPath(distance, next);
        canvas.drawPath(segment, paint);
        distance = next + gapLength;
      }
    }
  }

  /// Renders a single element.
  void renderElement({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    required ElementRegistry elementRegistry,
    Locale? locale,
  }) {
    final sceneResult = _renderSceneIfAvailable(
      canvas: canvas,
      element: element,
      scaleFactor: scaleFactor,
      elementRegistry: elementRegistry,
      locale: locale,
    );
    switch (sceneResult) {
      case _SceneRenderResult.rendered:
        return;
      case _SceneRenderResult.missingDefinition:
        _renderFallbackLog.warning(
          'Unknown element type "${element.typeId}", '
          'using unknown-element fallback',
          {'typeId': element.typeId.value},
        );
      case _SceneRenderResult.missingSceneEncoder:
        _renderFallbackLog.error(
          'Registered element type is missing a scene encoder, '
          'using unknown-element fallback',
          {'typeId': element.typeId.value},
        );
      case _SceneRenderResult.unsupported:
        // Unsupported reason/details are logged by _renderSceneIfAvailable.
        break;
      case _SceneRenderResult.failed:
        // Error details are emitted by _renderSceneIfAvailable.
        break;
    }
    _renderUnknownElement(canvas, element, scaleFactor);
  }

  _SceneRenderResult _renderSceneIfAvailable({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    required ElementRegistry elementRegistry,
    Locale? locale,
  }) {
    final definition = elementRegistry.getDefinitionByValue(
      element.typeId.value,
    );
    if (definition == null) {
      return _SceneRenderResult.missingDefinition;
    }
    final sceneEncoder = definition.sceneEncoder;
    if (sceneEncoder == null) {
      return _SceneRenderResult.missingSceneEncoder;
    }
    try {
      final scene = sceneEncoder.encodeScene(
        element: element,
        scaleFactor: scaleFactor,
        localeTag: locale?.toLanguageTag(),
      );
      _sceneRenderer.renderScene(canvas: canvas, scene: scene);
      return _SceneRenderResult.rendered;
    } on SceneEncodingNotSupported catch (signal) {
      _renderFallbackLog.warning(
        'Scene encoding not supported, using unknown-element fallback',
        {'typeId': element.typeId.value, 'reason': signal.reason},
      );
      return _SceneRenderResult.unsupported;
    } on Object catch (error, stackTrace) {
      _renderFallbackLog.warning(
        'Scene renderer failed, using unknown-element fallback',
        {
          'typeId': element.typeId.value,
          'error': error,
          'stackTrace': stackTrace,
        },
      );
      return _SceneRenderResult.failed;
    }
  }

  /// Renders the selection overlay (outline + resize handles).
  void renderSelection({
    required Canvas canvas,
    required DrawRect bounds,
    required double scaleFactor,
    required SelectionConfig config,
    double? rotation,
    DrawPoint? rotationCenter,
    bool dashed = true,
    double cornerHandleOffset = 0.0,
  }) {
    final scale = _effectiveScale(scaleFactor);
    final paddedBounds = _selectionBounds(bounds, config, scale);

    renderSelectionOutline(
      canvas: canvas,
      bounds: bounds,
      scaleFactor: scale,
      config: config,
      rotation: rotation,
      rotationCenter: rotationCenter,
      dashed: dashed,
    );

    final handleBounds = _inflateBounds(
      paddedBounds,
      cornerHandleOffset / scale,
    );

    final handleFillPaint = _selectionHandleFillPaint
      ..color = config.render.cornerFillColor.toFlutterColor();
    final handleStrokePaint = _selectionHandleStrokePaint
      ..strokeWidth = config.render.strokeWidth / scale
      ..color = config.render.strokeColor.toFlutterColor();

    final handleSize = config.render.controlPointSize / scale;
    final cornerRadius = config.render.cornerRadius / scale;

    canvas.save();
    _applyRotation(canvas, rotation: rotation, rotationCenter: rotationCenter);
    for (final center in <Offset>[
      Offset(handleBounds.minX, handleBounds.minY),
      Offset(handleBounds.maxX, handleBounds.minY),
      Offset(handleBounds.maxX, handleBounds.maxY),
      Offset(handleBounds.minX, handleBounds.maxY),
    ]) {
      _drawSelectionCornerHandle(
        canvas: canvas,
        center: center,
        handleSize: handleSize,
        cornerRadius: cornerRadius,
        fillPaint: handleFillPaint,
        strokePaint: handleStrokePaint,
      );
    }
    canvas.restore();
  }

  void _drawSelectionCornerHandle({
    required Canvas canvas,
    required Offset center,
    required double handleSize,
    required double cornerRadius,
    required Paint fillPaint,
    required Paint strokePaint,
  }) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: handleSize, height: handleSize),
      Radius.circular(cornerRadius),
    );
    canvas
      ..drawRRect(rect, fillPaint)
      ..drawRRect(rect, strokePaint);
  }

  /// Renders a selection outline (no control points).
  void renderSelectionOutline({
    required Canvas canvas,
    required DrawRect bounds,
    required double scaleFactor,
    required SelectionConfig config,
    double? rotation,
    DrawPoint? rotationCenter,
    bool dashed = true,
  }) {
    final scale = _effectiveScale(scaleFactor);
    final rect = _toRect(_selectionBounds(bounds, config, scale));

    final paint = _selectionOutlinePaint
      ..strokeWidth = config.render.strokeWidth / scale
      ..color = config.render.strokeColor.toFlutterColor();

    canvas.save();
    _applyRotation(canvas, rotation: rotation, rotationCenter: rotationCenter);
    if (!dashed) {
      canvas.drawRect(rect, paint);
    } else {
      _drawDashedPath(
        canvas,
        Path()..addRect(rect),
        paint,
        dashLength: _selectionDashLength / scale,
        gapLength: _selectionGapLength / scale,
      );
    }
    canvas.restore();
  }

  /// Renders the rotation handle.
  void renderRotationHandle({
    required Canvas canvas,
    required DrawRect bounds,
    required double scaleFactor,
    required SelectionConfig config,
    double? rotation,
    DrawPoint? rotationCenter,
  }) {
    final scale = _effectiveScale(scaleFactor);
    final paddedBounds = _selectionBounds(bounds, config, scale);

    final margin = config.rotateHandleOffset / scale;
    final handlePosition = Offset(
      paddedBounds.centerX,
      paddedBounds.minY - margin,
    );

    final handlePaint = _selectionHandleFillPaint
      ..color = config.render.cornerFillColor.toFlutterColor();
    final handleStrokePaint = _selectionHandleStrokePaint
      ..strokeWidth = config.render.strokeWidth / scale
      ..color = config.render.strokeColor.toFlutterColor();

    final handleRadius = config.render.controlPointSize / (2 * scale);

    canvas.save();
    _applyRotation(canvas, rotation: rotation, rotationCenter: rotationCenter);
    canvas
      ..drawCircle(handlePosition, handleRadius, handlePaint)
      ..drawCircle(handlePosition, handleRadius, handleStrokePaint)
      ..restore();
  }
}

const elementRenderer = ElementRenderer();
