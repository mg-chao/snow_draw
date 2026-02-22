import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:snow_draw_core/snow_draw_core.dart';

import '../extensions/draw_color_extensions.dart';
import 'patterns/stroke_pattern_utils.dart';
import 'scene/scene_primitive_renderer.dart';

final ModuleLogger _renderFallbackLog = LogService.fallback.render;

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
  static final Set<String> _reportedFallbackWarnings = <String>{};
  static const _maxFallbackWarningCacheEntries = 256;

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
  }) => canvas.drawPath(buildDashedPath(path, dashLength, gapLength), paint);

  /// Renders a single element.
  void renderElement({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    required ElementRegistry elementRegistry,
    TextMetricsService? textMetricsService,
    Locale? locale,
  }) {
    final rendered = _renderSceneIfAvailable(
      canvas: canvas,
      element: element,
      scaleFactor: scaleFactor,
      elementRegistry: elementRegistry,
      textMetricsService: textMetricsService,
      locale: locale,
    );
    if (rendered) {
      return;
    }
    _renderUnknownElement(canvas, element, scaleFactor);
  }

  bool _renderSceneIfAvailable({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    required ElementRegistry elementRegistry,
    TextMetricsService? textMetricsService,
    Locale? locale,
  }) {
    final definition = elementRegistry.getDefinitionByValue(
      element.typeId.value,
    );
    if (definition == null) {
      _logFallbackWarningOnce(
        'Unknown element type "${element.typeId}", '
        'using unknown-element fallback',
        key: 'missing:${element.typeId.value}',
        data: {'typeId': element.typeId.value},
      );
      return false;
    }
    try {
      final scene = definition.sceneEncoder.encodeScene(
        element: element,
        scaleFactor: scaleFactor,
        localeTag: locale?.toLanguageTag(),
        textMetricsService: textMetricsService,
      );
      _sceneRenderer.renderScene(canvas: canvas, scene: scene, locale: locale);
      return true;
    } on Object catch (error, stackTrace) {
      _logFallbackWarningOnce(
        'Scene renderer failed, using unknown-element fallback',
        key: 'failed:${element.typeId.value}:${error.runtimeType}',
        data: {
          'typeId': element.typeId.value,
          'error': error,
          'stackTrace': stackTrace,
        },
      );
      return false;
    }
  }

  void _logFallbackWarningOnce(
    String message, {
    required String key,
    Map<String, dynamic>? data,
  }) {
    if (_reportedFallbackWarnings.contains(key)) {
      return;
    }
    if (_reportedFallbackWarnings.length >= _maxFallbackWarningCacheEntries) {
      _reportedFallbackWarnings.remove(_reportedFallbackWarnings.first);
    }
    _reportedFallbackWarnings.add(key);
    _renderFallbackLog.warning(message, data);
  }

  @visibleForTesting
  static void clearFallbackWarningCache() {
    _reportedFallbackWarnings.clear();
  }

  @visibleForTesting
  static int get fallbackWarningCount => _reportedFallbackWarnings.length;

  @visibleForTesting
  static int get maxFallbackWarningCacheEntries =>
      _maxFallbackWarningCacheEntries;

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
