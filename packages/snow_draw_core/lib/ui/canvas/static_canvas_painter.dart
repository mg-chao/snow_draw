import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/element_state.dart';
import '../../draw/models/interaction_state.dart';
import '../../draw/render/element_renderer.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/utils/selection_calculator.dart';
import 'render_keys.dart';

/// Static canvas painter.
///
/// Renders persistent elements with viewport culling.
/// This layer should be wrapped in a RepaintBoundary to avoid unnecessary
/// repaints.
@immutable
class StaticCanvasPainter extends CustomPainter {
  const StaticCanvasPainter({required this.renderKey, required this.stateView});

  /// Render key for precise repaint decisions.
  final StaticCanvasRenderKey renderKey;

  /// Precomputed effective state view (needed for paint).
  final DrawStateView stateView;

  @override
  void paint(Canvas canvas, Size size) {
    final state = stateView.state;
    final document = state.domain.document;
    final camera = renderKey.camera;
    final scale = renderKey.scaleFactor == 0 ? 1.0 : renderKey.scaleFactor;
    final interaction = state.application.interaction;
    final creatingElementId = interaction is CreatingState
        ? interaction.elementId
        : null;
    final previewElements = creatingElementId == null
        ? renderKey.previewElementsById
        : const <String, ElementState>{};
    final dynamicLayerStartIndex = renderKey.dynamicLayerStartIndex;

    // Draw background.
    _drawBackground(canvas, size);

    canvas
      ..save()
      ..translate(camera.position.x, camera.position.y)
      ..scale(scale, scale);

    // Calculate viewport in world coordinates.
    // Viewport is (0,0) to (width, height) in screen coordinates.
    // Transform to world: (screen - translate) / scale
    final viewportRect = DrawRect(
      minX: -camera.position.x / scale,
      minY: -camera.position.y / scale,
      maxX: (size.width - camera.position.x) / scale,
      maxY: (size.height - camera.position.y) / scale,
    );

    _drawGrid(canvas, viewportRect, scale);

    // Query visible elements. Preview elements are handled below to avoid
    // lifting them into a higher render layer.
    final visibleElements = document.getElementsInRect(viewportRect);
    if (creatingElementId != null) {
      visibleElements.removeWhere((element) => element.id == creatingElementId);
    }
    if (dynamicLayerStartIndex != null) {
      visibleElements.removeWhere((element) {
        final orderIndex = document.getOrderIndex(element.id) ?? -1;
        return orderIndex >= dynamicLayerStartIndex;
      });
    }
    if (previewElements.isNotEmpty) {
      final visibleIds = {for (final element in visibleElements) element.id};
      for (final preview in previewElements.values) {
        if (visibleIds.contains(preview.id)) {
          continue;
        }
        final aabb = SelectionCalculator.computeElementWorldAabb(preview);
        if (_rectsIntersect(aabb, viewportRect)) {
          visibleElements.add(preview);
          visibleIds.add(preview.id);
        }
      }
    }

    visibleElements.sort((a, b) {
      final indexA = document.getOrderIndex(a.id) ?? -1;
      final indexB = document.getOrderIndex(b.id) ?? -1;
      return indexA.compareTo(indexB);
    });
    // Draw visible elements in document z-order, applying preview geometry
    // without lifting elements to the top layer.
    if (previewElements.isEmpty) {
      for (final element in visibleElements) {
        elementRenderer.renderElement(
          canvas: canvas,
          element: element,
          scaleFactor: scale,
          registry: renderKey.elementRegistry,
          locale: renderKey.locale,
        );
      }
    } else {
      for (final element in visibleElements) {
        final preview = previewElements[element.id];
        final effectiveElement = preview ?? element;
        if (preview != null) {
          final aabb = SelectionCalculator.computeElementWorldAabb(
            effectiveElement,
          );
          if (!_rectsIntersect(aabb, viewportRect)) {
            continue;
          }
        }
        elementRenderer.renderElement(
          canvas: canvas,
          element: effectiveElement,
          scaleFactor: scale,
          registry: renderKey.elementRegistry,
          locale: renderKey.locale,
        );
      }
    }

    canvas.restore();
  }

  /// Draw background.
  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = renderKey.canvasConfig.backgroundColor;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _drawGrid(Canvas canvas, DrawRect viewportRect, double scale) {
    final config = renderKey.gridConfig;
    if (!config.enabled) {
      return;
    }

    final baseSize = config.size;
    if (baseSize <= 0) {
      return;
    }

    final effectiveScale = scale == 0 ? 1.0 : scale;
    if (baseSize * effectiveScale < config.minRenderSpacing) {
      return;
    }

    final strokeWidth = config.lineWidth / effectiveScale;
    final screenSpacing = baseSize * effectiveScale;
    final showMinorLines = screenSpacing >= config.minScreenSpacing;
    final dashOpacityRatio = _resolveDashOpacityRatio(
      baseSize: baseSize,
      scale: effectiveScale,
      minScreenSpacing: config.minScreenSpacing,
    );
    final majorEveryFactor = _resolveMajorEveryFactor(
      baseSize: baseSize,
      majorEvery: config.majorLineEvery,
      scale: effectiveScale,
      minSpacing: config.minScreenSpacing,
    );
    final majorStep = baseSize * majorEveryFactor;
    const minorOpacityMultiplier = 0.75;
    final minorColor = config.lineColor.withValues(
      alpha: config.lineOpacity * minorOpacityMultiplier * dashOpacityRatio,
    );
    final majorColor = config.lineColor.withValues(
      alpha: config.majorLineOpacity,
    );
    final minorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = minorColor
      ..isAntiAlias = true;
    final majorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = majorColor
      ..isAntiAlias = true;

    const dashLengthScreen = 4.0;
    const dashGapScreen = 4.0;
    final dashLength = dashLengthScreen / effectiveScale;
    final dashGap = dashGapScreen / effectiveScale;
    if (showMinorLines) {
      final step = baseSize;
      final startXIndex = (viewportRect.minX / step).floor();
      final endXIndex = (viewportRect.maxX / step).ceil();
      for (var ix = startXIndex; ix <= endXIndex; ix++) {
        final x = ix * step;
        if (_isMajorLine(ix, majorEveryFactor)) {
          canvas.drawLine(
            Offset(x, viewportRect.minY),
            Offset(x, viewportRect.maxY),
            majorPaint,
          );
        } else {
          _drawDashedVerticalLine(
            canvas,
            x,
            viewportRect.minY,
            viewportRect.maxY,
            minorPaint,
            dashLength,
            dashGap,
          );
        }
      }

      final startYIndex = (viewportRect.minY / step).floor();
      final endYIndex = (viewportRect.maxY / step).ceil();
      for (var iy = startYIndex; iy <= endYIndex; iy++) {
        final y = iy * step;
        if (_isMajorLine(iy, majorEveryFactor)) {
          canvas.drawLine(
            Offset(viewportRect.minX, y),
            Offset(viewportRect.maxX, y),
            majorPaint,
          );
        } else {
          _drawDashedHorizontalLine(
            canvas,
            y,
            viewportRect.minX,
            viewportRect.maxX,
            minorPaint,
            dashLength,
            dashGap,
          );
        }
      }
    } else {
      final startXIndex = (viewportRect.minX / majorStep).floor();
      final endXIndex = (viewportRect.maxX / majorStep).ceil();
      for (var ix = startXIndex; ix <= endXIndex; ix++) {
        final x = ix * majorStep;
        canvas.drawLine(
          Offset(x, viewportRect.minY),
          Offset(x, viewportRect.maxY),
          majorPaint,
        );
      }

      final startYIndex = (viewportRect.minY / majorStep).floor();
      final endYIndex = (viewportRect.maxY / majorStep).ceil();
      for (var iy = startYIndex; iy <= endYIndex; iy++) {
        final y = iy * majorStep;
        canvas.drawLine(
          Offset(viewportRect.minX, y),
          Offset(viewportRect.maxX, y),
          majorPaint,
        );
      }
    }
  }

  int _resolveMajorEveryFactor({
    required double baseSize,
    required int majorEvery,
    required double scale,
    required double minSpacing,
  }) {
    if (majorEvery <= 1) {
      return majorEvery;
    }
    if (scale <= 0 || minSpacing <= 0) {
      return majorEvery;
    }

    var factor = majorEvery;
    var step = baseSize * factor;
    while (step * scale < minSpacing) {
      factor *= majorEvery;
      step = baseSize * factor;
    }
    return factor;
  }

  double _resolveDashOpacityRatio({
    required double baseSize,
    required double scale,
    required double minScreenSpacing,
  }) {
    if (scale <= 0 || baseSize <= 0 || minScreenSpacing <= 0) {
      return 0;
    }
    final spacingAtScale = baseSize * scale;
    final startSpacing = baseSize;
    if (spacingAtScale >= startSpacing) {
      return 1;
    }
    if (startSpacing <= minScreenSpacing) {
      return 0;
    }
    final t = (spacingAtScale - minScreenSpacing) /
        (startSpacing - minScreenSpacing);
    return _smoothStep(t.clamp(0.0, 1.0));
  }

  double _smoothStep(double t) => t * t * (3 - 2 * t);

  bool _isMajorLine(int index, int majorEvery) =>
      majorEvery > 0 && index % majorEvery == 0;

  bool _rectsIntersect(DrawRect a, DrawRect b) =>
      a.minX <= b.maxX &&
      a.maxX >= b.minX &&
      a.minY <= b.maxY &&
      a.maxY >= b.minY;

  void _drawDashedVerticalLine(
    Canvas canvas,
    double x,
    double minY,
    double maxY,
    Paint paint,
    double dashLength,
    double gapLength,
  ) {
    if (maxY <= minY || dashLength <= 0) {
      return;
    }
    final patternLength = dashLength + gapLength;
    if (patternLength <= 0) {
      return;
    }

    final offset = _positiveModulo(minY, patternLength);
    double current;
    if (offset < dashLength) {
      final dashStart = minY - offset;
      final dashEnd = dashStart + dashLength;
      final start = math.max(minY, dashStart);
      final end = math.min(maxY, dashEnd);
      if (end > start) {
        canvas.drawLine(Offset(x, start), Offset(x, end), paint);
      }
      current = dashStart + patternLength;
    } else {
      current = minY - offset + patternLength;
    }

    for (; current < maxY; current += patternLength) {
      final dashEnd = current + dashLength;
      final start = math.max(current, minY);
      final end = math.min(dashEnd, maxY);
      if (end > start) {
        canvas.drawLine(Offset(x, start), Offset(x, end), paint);
      }
    }
  }

  void _drawDashedHorizontalLine(
    Canvas canvas,
    double y,
    double minX,
    double maxX,
    Paint paint,
    double dashLength,
    double gapLength,
  ) {
    if (maxX <= minX || dashLength <= 0) {
      return;
    }
    final patternLength = dashLength + gapLength;
    if (patternLength <= 0) {
      return;
    }

    final offset = _positiveModulo(minX, patternLength);
    double current;
    if (offset < dashLength) {
      final dashStart = minX - offset;
      final dashEnd = dashStart + dashLength;
      final start = math.max(minX, dashStart);
      final end = math.min(maxX, dashEnd);
      if (end > start) {
        canvas.drawLine(Offset(start, y), Offset(end, y), paint);
      }
      current = dashStart + patternLength;
    } else {
      current = minX - offset + patternLength;
    }

    for (; current < maxX; current += patternLength) {
      final dashEnd = current + dashLength;
      final start = math.max(current, minX);
      final end = math.min(dashEnd, maxX);
      if (end > start) {
        canvas.drawLine(Offset(start, y), Offset(end, y), paint);
      }
    }
  }

  double _positiveModulo(double value, double modulo) {
    if (modulo == 0) {
      return 0;
    }
    final result = value % modulo;
    return result < 0 ? result + modulo : result;
  }

  @override
  bool shouldRepaint(covariant StaticCanvasPainter oldDelegate) =>
      oldDelegate.renderKey != renderKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StaticCanvasPainter && other.renderKey == renderKey;

  @override
  int get hashCode => renderKey.hashCode;
}
