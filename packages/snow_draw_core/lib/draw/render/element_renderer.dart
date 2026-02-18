import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../config/draw_config.dart';
import '../elements/core/element_registry_interface.dart';
import '../models/element_state.dart';
import '../services/log/log_service.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';

final ModuleLogger _renderFallbackLog = LogService.fallback.render;

/// Element renderer.
///
/// Renders elements based on their [ElementState] type.
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

  void _renderUnknownElement(
    Canvas canvas,
    ElementState element,
    double scaleFactor,
  ) {
    final rect = Rect.fromLTWH(
      element.rect.minX,
      element.rect.minY,
      element.rect.width,
      element.rect.height,
    );
    final effectiveScale = scaleFactor == 0 ? 1.0 : scaleFactor;
    final strokeWidth = (1.5 / effectiveScale).clamp(0.5, 4.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = const Color(0xFFB00020)
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
    // `Path.computeMetrics` splits a path into contiguous segments (4 edges
    // for a rect).
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
    required ElementRegistry registry,
    Locale? locale,
  }) {
    final definition = registry.getDefinition(element.typeId);
    if (definition == null) {
      final message =
          'Unknown element type "${element.typeId}" '
          'encountered during render';
      _renderFallbackLog.warning(message, {'typeId': element.typeId});
      _renderUnknownElement(canvas, element, scaleFactor);
      return;
    }
    definition.renderer.render(
      canvas: canvas,
      element: element,
      scaleFactor: scaleFactor,
      locale: locale,
    );
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
    final scale = scaleFactor == 0 ? 1.0 : scaleFactor;
    renderSelectionOutline(
      canvas: canvas,
      bounds: bounds,
      scaleFactor: scale,
      config: config,
      rotation: rotation,
      rotationCenter: rotationCenter,
      dashed: dashed,
    );

    final padding = config.padding / scale;
    final paddedBounds = DrawRect(
      minX: bounds.minX - padding,
      minY: bounds.minY - padding,
      maxX: bounds.maxX + padding,
      maxY: bounds.maxY + padding,
    );

    canvas.save();

    // Apply rotation (if any).
    if (rotation != null && rotation != 0 && rotationCenter != null) {
      // Move origin to rotation center.
      canvas
        ..translate(rotationCenter.x, rotationCenter.y)
        // Rotate.
        ..rotate(rotation)
        // Move origin back.
        ..translate(-rotationCenter.x, -rotationCenter.y);
    }

    // Apply additional offset to corner handles (for arrow elements).
    final handleOffset = cornerHandleOffset / scale;
    final handleBounds = DrawRect(
      minX: paddedBounds.minX - handleOffset,
      minY: paddedBounds.minY - handleOffset,
      maxX: paddedBounds.maxX + handleOffset,
      maxY: paddedBounds.maxY + handleOffset,
    );

    final handleFillPaint = _selectionHandleFillPaint
      ..color = config.render.cornerFillColor;
    final handleStrokePaint = _selectionHandleStrokePaint
      ..strokeWidth = config.render.strokeWidth / scale
      ..color = config.render.strokeColor;

    final handleSize = config.render.controlPointSize / scale;
    final cornerRadius = config.render.cornerRadius / scale;

    _drawSelectionCornerHandle(
      canvas: canvas,
      center: Offset(handleBounds.minX, handleBounds.minY),
      handleSize: handleSize,
      cornerRadius: cornerRadius,
      fillPaint: handleFillPaint,
      strokePaint: handleStrokePaint,
    );
    _drawSelectionCornerHandle(
      canvas: canvas,
      center: Offset(handleBounds.maxX, handleBounds.minY),
      handleSize: handleSize,
      cornerRadius: cornerRadius,
      fillPaint: handleFillPaint,
      strokePaint: handleStrokePaint,
    );
    _drawSelectionCornerHandle(
      canvas: canvas,
      center: Offset(handleBounds.maxX, handleBounds.maxY),
      handleSize: handleSize,
      cornerRadius: cornerRadius,
      fillPaint: handleFillPaint,
      strokePaint: handleStrokePaint,
    );
    _drawSelectionCornerHandle(
      canvas: canvas,
      center: Offset(handleBounds.minX, handleBounds.maxY),
      handleSize: handleSize,
      cornerRadius: cornerRadius,
      fillPaint: handleFillPaint,
      strokePaint: handleStrokePaint,
    );

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
  ///
  /// - Works for both single- and multi-select
  /// - Supports dashed/solid styles (dashed by default for the overall overlay)
  void renderSelectionOutline({
    required Canvas canvas,
    required DrawRect bounds,
    required double scaleFactor,
    required SelectionConfig config,
    double? rotation,
    DrawPoint? rotationCenter,
    bool dashed = true,
  }) {
    final scale = scaleFactor == 0 ? 1.0 : scaleFactor;
    final padding = config.padding / scale;
    final paddedBounds = DrawRect(
      minX: bounds.minX - padding,
      minY: bounds.minY - padding,
      maxX: bounds.maxX + padding,
      maxY: bounds.maxY + padding,
    );

    canvas.save();

    // Apply rotation (if any).
    if (rotation != null && rotation != 0 && rotationCenter != null) {
      // Move origin to rotation center.
      canvas
        ..translate(rotationCenter.x, rotationCenter.y)
        // Rotate.
        ..rotate(rotation)
        // Move origin back.
        ..translate(-rotationCenter.x, -rotationCenter.y);
    }

    final paint = _selectionOutlinePaint
      ..strokeWidth = config.render.strokeWidth / scale
      ..color = config.render.strokeColor;

    final rect = Rect.fromLTWH(
      paddedBounds.minX,
      paddedBounds.minY,
      paddedBounds.width,
      paddedBounds.height,
    );

    if (dashed) {
      // Selection outline: dashed.
      final path = Path()..addRect(rect);
      _drawDashedPath(
        canvas,
        path,
        paint,
        dashLength: 6.0 / scale,
        gapLength: 4.0 / scale,
      );
    } else {
      // Per-element outline: solid.
      canvas.drawRect(rect, paint);
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
    final scale = scaleFactor == 0 ? 1.0 : scaleFactor;
    final padding = config.padding / scale;
    final paddedBounds = DrawRect(
      minX: bounds.minX - padding,
      minY: bounds.minY - padding,
      maxX: bounds.maxX + padding,
      maxY: bounds.maxY + padding,
    );

    canvas.save();

    // Apply rotation (if any).
    if (rotation != null && rotation != 0 && rotationCenter != null) {
      // Move origin to rotation center.
      canvas
        ..translate(rotationCenter.x, rotationCenter.y)
        // Rotate.
        ..rotate(rotation)
        // Move origin back.
        ..translate(-rotationCenter.x, -rotationCenter.y);
    }

    // The rotation handle sits above the selection, centered horizontally.
    final margin = config.rotateHandleOffset / scale;
    final handlePosition = Offset(
      paddedBounds.centerX,
      paddedBounds.minY - margin,
    );

    final handlePaint = _selectionHandleFillPaint
      ..color = config.render.cornerFillColor;
    final handleStrokePaint = _selectionHandleStrokePaint
      ..strokeWidth = config.render.strokeWidth / scale
      ..color = config.render.strokeColor;

    final angleHandleSize = config.render.controlPointSize / (2 * scale);
    canvas
      ..drawCircle(handlePosition, angleHandleSize, handlePaint)
      ..drawCircle(handlePosition, angleHandleSize, handleStrokePaint)
      ..restore();
  }
}

const elementRenderer = ElementRenderer();
