import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/element_state.dart';
import '../../draw/models/interaction_state.dart';
import '../../draw/render/element_renderer.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/utils/selection_calculator.dart';
import 'grid_shader_painter.dart';
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

    // Calculate viewport in world coordinates.
    // Viewport is (0,0) to (width, height) in screen coordinates.
    // Transform to world: (screen - translate) / scale
    final viewportRect = DrawRect(
      minX: -camera.position.x / scale,
      minY: -camera.position.y / scale,
      maxX: (size.width - camera.position.x) / scale,
      maxY: (size.height - camera.position.y) / scale,
    );

    // Try GPU-accelerated shader grid first (drawn in screen coordinates).
    final shaderUsed = _drawGridWithShader(canvas, size, scale);

    canvas
      ..save()
      ..translate(camera.position.x, camera.position.y)
      ..scale(scale, scale);

    // Fall back to CPU-based grid if shader not available.
    if (!shaderUsed) {
      _drawGridFallback(canvas, viewportRect, scale);
    }

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

  /// Draws the grid using the GPU-accelerated fragment shader.
  ///
  /// Returns true if the shader was used successfully, false if fallback
  /// rendering should be used instead.
  bool _drawGridWithShader(Canvas canvas, Size size, double scale) {
    final config = renderKey.gridConfig;
    if (!config.enabled) {
      return true; // Grid disabled, no need for fallback.
    }

    final baseSize = config.size;
    if (baseSize <= 0) {
      return true; // Invalid config, no need for fallback.
    }

    final effectiveScale = scale == 0 ? 1.0 : scale;
    if (baseSize * effectiveScale < config.minRenderSpacing) {
      return true; // Grid too small to render, no need for fallback.
    }

    final shaderManager = GridShaderManager.instance;
    if (!shaderManager.isReady) {
      return false; // Shader not ready, use fallback.
    }

    final minorOpacityRatio = _resolveMinorOpacityRatio(
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

    return shaderManager.paintGrid(
      canvas: canvas,
      size: size,
      cameraPosition: Offset(
        renderKey.camera.position.x,
        renderKey.camera.position.y,
      ),
      scale: effectiveScale,
      config: config,
      minorOpacityRatio: minorOpacityRatio,
      majorEveryFactor: majorEveryFactor,
    );
  }

  /// Fallback grid rendering using CPU-based drawRawPoints.
  ///
  /// Used when the fragment shader is not available.
  void _drawGridFallback(Canvas canvas, DrawRect viewportRect, double scale) {
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

    final minorStrokeWidth = config.lineWidth / effectiveScale;
    // Major lines are 1.5x thicker for clear visual distinction.
    final majorStrokeWidth = minorStrokeWidth * 1.5;
    final screenSpacing = baseSize * effectiveScale;
    final showMinorLines = screenSpacing >= config.minScreenSpacing;
    final minorOpacityRatio = _resolveMinorOpacityRatio(
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

    // Use solid lines with opacity and thickness differentiation for clear
    // visual distinction between major and minor grid lines.
    // Minor lines use reduced opacity (0.5x) for subtlety.
    final minorColor = config.lineColor.withValues(
      alpha: config.lineOpacity * minorOpacityRatio * 0.5,
    );
    final majorColor = config.lineColor.withValues(
      alpha: config.majorLineOpacity,
    );
    final minorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = minorStrokeWidth
      ..color = minorColor;
    final majorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = majorStrokeWidth
      ..color = majorColor;

    if (showMinorLines) {
      final step = baseSize;
      final startXIndex = (viewportRect.minX / step).floor();
      final endXIndex = (viewportRect.maxX / step).ceil();
      final startYIndex = (viewportRect.minY / step).floor();
      final endYIndex = (viewportRect.maxY / step).ceil();

      final verticalLineCount = endXIndex - startXIndex + 1;
      final horizontalLineCount = endYIndex - startYIndex + 1;

      // Count major vs minor lines for pre-allocation.
      var majorVerticalCount = 0;
      var majorHorizontalCount = 0;
      for (var ix = startXIndex; ix <= endXIndex; ix++) {
        if (_isMajorLine(ix, majorEveryFactor)) {
          majorVerticalCount++;
        }
      }
      for (var iy = startYIndex; iy <= endYIndex; iy++) {
        if (_isMajorLine(iy, majorEveryFactor)) {
          majorHorizontalCount++;
        }
      }
      final minorVerticalCount = verticalLineCount - majorVerticalCount;
      final minorHorizontalCount = horizontalLineCount - majorHorizontalCount;

      // Pre-allocate Float32Lists for maximum performance.
      // Each line needs 4 floats: x1, y1, x2, y2.
      final majorPoints = Float32List(
        (majorVerticalCount + majorHorizontalCount) * 4,
      );
      final minorPoints = Float32List(
        (minorVerticalCount + minorHorizontalCount) * 4,
      );

      var majorIdx = 0;
      var minorIdx = 0;

      // Batch vertical lines.
      for (var ix = startXIndex; ix <= endXIndex; ix++) {
        final x = ix * step;
        if (_isMajorLine(ix, majorEveryFactor)) {
          majorPoints[majorIdx++] = x;
          majorPoints[majorIdx++] = viewportRect.minY;
          majorPoints[majorIdx++] = x;
          majorPoints[majorIdx++] = viewportRect.maxY;
        } else {
          minorPoints[minorIdx++] = x;
          minorPoints[minorIdx++] = viewportRect.minY;
          minorPoints[minorIdx++] = x;
          minorPoints[minorIdx++] = viewportRect.maxY;
        }
      }

      // Batch horizontal lines.
      for (var iy = startYIndex; iy <= endYIndex; iy++) {
        final y = iy * step;
        if (_isMajorLine(iy, majorEveryFactor)) {
          majorPoints[majorIdx++] = viewportRect.minX;
          majorPoints[majorIdx++] = y;
          majorPoints[majorIdx++] = viewportRect.maxX;
          majorPoints[majorIdx++] = y;
        } else {
          minorPoints[minorIdx++] = viewportRect.minX;
          minorPoints[minorIdx++] = y;
          minorPoints[minorIdx++] = viewportRect.maxX;
          minorPoints[minorIdx++] = y;
        }
      }

      // Draw all lines with just 2 GPU draw calls.
      if (minorPoints.isNotEmpty) {
        canvas.drawRawPoints(ui.PointMode.lines, minorPoints, minorPaint);
      }
      if (majorPoints.isNotEmpty) {
        canvas.drawRawPoints(ui.PointMode.lines, majorPoints, majorPaint);
      }
    } else {
      // Only major lines visible at this zoom level.
      final startXIndex = (viewportRect.minX / majorStep).floor();
      final endXIndex = (viewportRect.maxX / majorStep).ceil();
      final startYIndex = (viewportRect.minY / majorStep).floor();
      final endYIndex = (viewportRect.maxY / majorStep).ceil();

      final verticalCount = endXIndex - startXIndex + 1;
      final horizontalCount = endYIndex - startYIndex + 1;
      final majorPoints = Float32List((verticalCount + horizontalCount) * 4);

      var idx = 0;

      // Batch vertical major lines.
      for (var ix = startXIndex; ix <= endXIndex; ix++) {
        final x = ix * majorStep;
        majorPoints[idx++] = x;
        majorPoints[idx++] = viewportRect.minY;
        majorPoints[idx++] = x;
        majorPoints[idx++] = viewportRect.maxY;
      }

      // Batch horizontal major lines.
      for (var iy = startYIndex; iy <= endYIndex; iy++) {
        final y = iy * majorStep;
        majorPoints[idx++] = viewportRect.minX;
        majorPoints[idx++] = y;
        majorPoints[idx++] = viewportRect.maxX;
        majorPoints[idx++] = y;
      }

      // Single GPU draw call for all major lines.
      canvas.drawRawPoints(ui.PointMode.lines, majorPoints, majorPaint);
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

  double _resolveMinorOpacityRatio({
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
