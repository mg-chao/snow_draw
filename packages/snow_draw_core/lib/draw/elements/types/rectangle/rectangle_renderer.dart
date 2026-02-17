import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../../ui/canvas/rectangle_shader_manager.dart';
import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import '../../../utils/stroke_pattern_utils.dart';
import '../../core/element_renderer.dart';
import 'rectangle_data.dart';
import 'rectangle_render_plan.dart';

class RectangleRenderer extends ElementTypeRenderer {
  const RectangleRenderer();

  // Cache expensive stroke/fill paths by size/style to avoid per-frame
  // rebuilds. Only used for CPU fallback rendering.
  static final _strokePathCache = LruCache<_StrokePathKey, Path>(
    maxEntries: 200,
  );

  /// Reusable paints for CPU fallback rendering to reduce GC pressure.
  static final _fillPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  static final _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  static final _dotPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  @override
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  }) {
    final data = element.data;
    if (data is! RectangleData) {
      throw StateError(
        'RectangleRenderer can only render RectangleData (got '
        '${data.runtimeType})',
      );
    }

    final renderPlan = RectangleRenderPlan.resolve(
      data: data,
      elementOpacity: element.opacity,
      shaderReady: RectangleShaderManager.instance.isReady,
    );

    // Prefer the shader only for pattern-heavy styles where it provides a
    // clear benefit over built-in Canvas primitives.
    if (renderPlan.shouldUseShader &&
        _renderWithShader(canvas, element, data, renderPlan, scaleFactor)) {
      return;
    }

    if (renderPlan.shouldUseSolidFastPath) {
      _renderSolidFastPath(canvas, element, data, renderPlan);
      return;
    }

    _renderPatternFallback(canvas, element, data, renderPlan);
  }

  /// Renders the rectangle using the GPU fragment shader.
  ///
  /// Returns true if shader was used, false if fallback is needed.
  bool _renderWithShader(
    Canvas canvas,
    ElementState element,
    RectangleData data,
    RectangleRenderPlan renderPlan,
    double scaleFactor,
  ) {
    final shaderManager = RectangleShaderManager.instance;
    if (!shaderManager.isReady) {
      return false;
    }
    final rect = element.rect;
    final rotation = element.rotation;

    // Calculate fill pattern parameters (matching CPU fallback logic)
    final fillLineWidth = (1 + (data.strokeWidth - 1) * 0.6).clamp(0.5, 3.0);
    const lineToSpacingRatio = 4.0;
    final fillLineSpacing = (fillLineWidth * lineToSpacingRatio).clamp(
      3.0,
      18.0,
    );

    // Calculate stroke pattern parameters (matching CPU fallback logic)
    // Dash and dot patterns are proportional to stroke width
    final dashLength = data.strokeWidth * 3.0;
    final gapLength = dashLength * 0.5;
    final dotSpacing = data.strokeWidth * 2.0;
    final dotRadius = data.strokeWidth * 0.5;

    // Scale-aware anti-aliasing width
    final aaWidth = 1.5 / (scaleFactor == 0 ? 1.0 : scaleFactor);

    return shaderManager.paintRectangle(
      canvas: canvas,
      elementId: element.id,
      center: Offset(rect.centerX, rect.centerY),
      size: Size(rect.width, rect.height),
      rotation: rotation,
      cornerRadius: data.cornerRadius,
      fillStyle: data.fillStyle,
      fillColor: renderPlan.fillColor,
      fillLineWidth: fillLineWidth,
      fillLineSpacing: fillLineSpacing,
      strokeStyle: data.strokeStyle,
      strokeColor: renderPlan.strokeColor,
      strokeWidth: data.strokeWidth,
      dashLength: dashLength,
      gapLength: gapLength,
      dotSpacing: dotSpacing,
      dotRadius: dotRadius,
      aaWidth: aaWidth,
    );
  }

  /// Fast path for common solid-style rectangles.
  void _renderSolidFastPath(
    Canvas canvas,
    ElementState element,
    RectangleData data,
    RectangleRenderPlan renderPlan,
  ) {
    if (!renderPlan.paintFill && !renderPlan.paintStroke) {
      return;
    }

    final rect = element.rect;
    final rotation = element.rotation;
    final rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.minX, rect.minY, rect.width, rect.height),
      Radius.circular(data.cornerRadius),
    );

    canvas.save();
    if (rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }

    if (renderPlan.paintFill) {
      _fillPaint
        ..color = renderPlan.fillColor
        ..shader = null
        ..colorFilter = null;
      canvas.drawRRect(rRect, _fillPaint);
    }

    if (renderPlan.paintStroke) {
      _strokePaint
        ..strokeWidth = data.strokeWidth
        ..color = renderPlan.strokeColor
        ..strokeCap = StrokeCap.butt
        ..shader = null
        ..colorFilter = null;
      canvas.drawRRect(rRect, _strokePaint);
    }

    canvas.restore();
  }

  /// CPU fallback for pattern-heavy styles when shaders are unavailable.
  void _renderPatternFallback(
    Canvas canvas,
    ElementState element,
    RectangleData data,
    RectangleRenderPlan renderPlan,
  ) {
    final rect = element.rect;
    final rotation = element.rotation;

    canvas.save();

    final size = Size(rect.width, rect.height);
    final rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, rect.width, rect.height),
      Radius.circular(data.cornerRadius),
    );

    if (rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }

    canvas.translate(rect.minX, rect.minY);

    if (renderPlan.paintFill) {
      if (data.fillStyle == FillStyle.solid) {
        _fillPaint
          ..color = renderPlan.fillColor
          ..shader = null
          ..colorFilter = null;
        canvas.drawRRect(rRect, _fillPaint);
      } else {
        final fillLineWidth = (1 + (data.strokeWidth - 1) * 0.6).clamp(
          0.5,
          3.0,
        );
        const lineToSpacingRatio = 4.0;
        final spacing = (fillLineWidth * lineToSpacingRatio).clamp(3.0, 18.0);
        const lineAngle = -math.pi / 4;
        const crossLineAngle = math.pi / 4;
        _fillPaint
          ..color = renderPlan.fillColor
          ..shader = lineShaderCache.getOrCreate(
            LineShaderKey(
              spacing: spacing,
              lineWidth: fillLineWidth,
              angle: lineAngle,
            ),
            () => buildLineShader(
              spacing: spacing,
              lineWidth: fillLineWidth,
              angle: lineAngle,
            ),
          )
          ..colorFilter = ColorFilter.mode(
            renderPlan.fillColor,
            BlendMode.modulate,
          );
        canvas.drawRRect(rRect, _fillPaint);
        if (data.fillStyle == FillStyle.crossLine) {
          _fillPaint.shader = lineShaderCache.getOrCreate(
            LineShaderKey(
              spacing: spacing,
              lineWidth: fillLineWidth,
              angle: crossLineAngle,
            ),
            () => buildLineShader(
              spacing: spacing,
              lineWidth: fillLineWidth,
              angle: crossLineAngle,
            ),
          );
          canvas.drawRRect(rRect, _fillPaint);
        }
      }
    }

    if (renderPlan.paintStroke) {
      _strokePaint
        ..strokeWidth = data.strokeWidth
        ..color = renderPlan.strokeColor
        ..strokeCap = StrokeCap.butt;

      if (data.strokeStyle == StrokeStyle.solid) {
        canvas.drawRRect(rRect, _strokePaint);
      } else {
        if (data.strokeStyle == StrokeStyle.dashed) {
          // Dash pattern proportional to stroke width
          final dashLength = data.strokeWidth * 2.0;
          final gapLength = dashLength * 1.2;
          final key = _StrokePathKey(
            width: size.width,
            height: size.height,
            cornerRadius: data.cornerRadius,
            strokeStyle: StrokeStyle.dashed,
            patternPrimary: dashLength,
            patternSecondary: gapLength,
          );
          final dashedPath = _strokePathCache.getOrCreate(
            key,
            () =>
                buildDashedPath(Path()..addRRect(rRect), dashLength, gapLength),
          );
          _strokePaint.strokeCap = StrokeCap.round;
          canvas.drawPath(dashedPath, _strokePaint);
        } else {
          // Dot pattern proportional to stroke width
          _dotPaint.color = _strokePaint.color;
          final dotSpacing = data.strokeWidth * 2.0;
          final dotRadius = data.strokeWidth * 0.5;
          final key = _StrokePathKey(
            width: size.width,
            height: size.height,
            cornerRadius: data.cornerRadius,
            strokeStyle: StrokeStyle.dotted,
            patternPrimary: dotSpacing,
            patternSecondary: dotRadius,
          );
          final dottedPath = _strokePathCache.getOrCreate(
            key,
            () =>
                buildDottedPath(Path()..addRRect(rRect), dotSpacing, dotRadius),
          );
          canvas.drawPath(dottedPath, _dotPaint);
        }
      }
    }

    canvas.restore();
  }
}

@immutable
class _StrokePathKey {
  _StrokePathKey({
    required double width,
    required double height,
    required double cornerRadius,
    required this.strokeStyle,
    required double patternPrimary,
    required double patternSecondary,
  }) : width = _quantize(width),
       height = _quantize(height),
       cornerRadius = _quantize(cornerRadius),
       patternPrimary = _quantize(patternPrimary),
       patternSecondary = _quantize(patternSecondary);

  final double width;
  final double height;
  final double cornerRadius;
  final StrokeStyle strokeStyle;
  // Dash length/gap length for dashed, dot spacing/radius for dotted.
  final double patternPrimary;
  final double patternSecondary;

  /// Quantize to 1 decimal place to improve cache hit rate
  /// by reducing floating-point precision variations
  static double _quantize(double value) => (value * 10).roundToDouble() / 10;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _StrokePathKey &&
          other.width == width &&
          other.height == height &&
          other.cornerRadius == cornerRadius &&
          other.strokeStyle == strokeStyle &&
          other.patternPrimary == patternPrimary &&
          other.patternSecondary == patternSecondary;

  @override
  int get hashCode => Object.hash(
    width,
    height,
    cornerRadius,
    strokeStyle,
    patternPrimary,
    patternSecondary,
  );
}
