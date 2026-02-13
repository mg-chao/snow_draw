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

    // Try GPU shader rendering first (highest performance)
    if (_renderWithShader(canvas, element, data, scaleFactor)) {
      return;
    }

    // Fallback to CPU rendering
    _renderFallback(canvas, element, data, scaleFactor);
  }

  /// Renders the rectangle using the GPU fragment shader.
  ///
  /// Returns true if shader was used, false if fallback is needed.
  bool _renderWithShader(
    Canvas canvas,
    ElementState element,
    RectangleData data,
    double scaleFactor,
  ) {
    final shaderManager = RectangleShaderManager.instance;
    if (!shaderManager.isReady) {
      return false;
    }

    final rect = element.rect;
    final rotation = element.rotation;
    final opacity = element.opacity;
    final fillOpacity = (data.fillColor.a * opacity).clamp(0.0, 1.0);
    final strokeOpacity = (data.color.a * opacity).clamp(0.0, 1.0);

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
      center: Offset(rect.centerX, rect.centerY),
      size: Size(rect.width, rect.height),
      rotation: rotation,
      cornerRadius: data.cornerRadius,
      fillStyle: data.fillStyle,
      fillColor: data.fillColor.withValues(alpha: fillOpacity),
      fillLineWidth: fillLineWidth,
      fillLineSpacing: fillLineSpacing,
      strokeStyle: data.strokeStyle,
      strokeColor: data.color.withValues(alpha: strokeOpacity),
      strokeWidth: data.strokeWidth,
      dashLength: dashLength,
      gapLength: gapLength,
      dotSpacing: dotSpacing,
      dotRadius: dotRadius,
      aaWidth: aaWidth,
    );
  }

  /// CPU fallback rendering for platforms without shader support.
  void _renderFallback(
    Canvas canvas,
    ElementState element,
    RectangleData data,
    double scaleFactor,
  ) {
    final _ = scaleFactor;

    final rect = element.rect;
    final rotation = element.rotation;
    final opacity = element.opacity;
    final fillOpacity = (data.fillColor.a * opacity).clamp(0.0, 1.0);
    final strokeOpacity = (data.color.a * opacity).clamp(0.0, 1.0);

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

    if (fillOpacity > 0) {
      if (data.fillStyle == FillStyle.solid) {
        _fillPaint
          ..color = data.fillColor.withValues(alpha: fillOpacity)
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
          ..color = data.fillColor.withValues(alpha: fillOpacity)
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
            data.fillColor.withValues(alpha: fillOpacity),
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

    if (strokeOpacity > 0 && data.strokeWidth > 0) {
      _strokePaint
        ..strokeWidth = data.strokeWidth
        ..color = data.color.withValues(alpha: strokeOpacity)
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
