import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/lru_cache.dart';

import '../element_type_renderer.dart';
import '../rectangle/rectangle_render_plan.dart';
import 'stroke_pattern_utils.dart';

class RectangleRenderer extends ElementTypeRenderer {
  const RectangleRenderer();

  static const _lineToSpacingRatio = 4;
  static const double _lineFillAngle = -math.pi / 4;
  static const double _crossLineFillAngle = math.pi / 4;

  // Cache expensive stroke paths by size/style to avoid per-frame rebuilds.
  // Only used for CPU fallback rendering.
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
      shaderReady: false,
    );

    if (!renderPlan.paintFill && !renderPlan.paintStroke) {
      return;
    }

    switch (renderPlan.backend) {
      case RectangleRenderBackend.solidFastPath:
        _renderSolidFastPath(canvas, element, data, renderPlan);
        return;
      case RectangleRenderBackend.shaderPattern:
      case RectangleRenderBackend.cpuPattern:
        _renderPatternFallback(canvas, element, data, renderPlan);
        return;
    }
  }

  /// Fast path for common solid-style rectangles.
  void _renderSolidFastPath(
    Canvas canvas,
    ElementState element,
    RectangleData data,
    RectangleRenderPlan renderPlan,
  ) {
    final rect = element.rect;
    final rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.minX, rect.minY, rect.width, rect.height),
      Radius.circular(data.cornerRadius),
    );

    canvas.save();
    _applyElementRotation(canvas, element);

    if (renderPlan.paintFill) {
      _setSolidFillPaint(renderPlan.fillColor);
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

    canvas.save();

    final rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, rect.width, rect.height),
      Radius.circular(data.cornerRadius),
    );

    _applyElementRotation(canvas, element);
    canvas.translate(rect.minX, rect.minY);

    if (renderPlan.paintFill) {
      _paintFill(
        canvas: canvas,
        data: data,
        fillColor: renderPlan.fillColor,
        rRect: rRect,
      );
    }

    if (renderPlan.paintStroke) {
      _paintStroke(
        canvas: canvas,
        data: data,
        strokeColor: renderPlan.strokeColor,
        rRect: rRect,
        width: rect.width,
        height: rect.height,
      );
    }

    canvas.restore();
  }

  static double _resolveFillLineWidth(double strokeWidth) =>
      (1 + (strokeWidth - 1) * 0.6).clamp(0.5, 3.0);

  static double _resolveFillLineSpacing(double lineWidth) =>
      (lineWidth * _lineToSpacingRatio).clamp(3.0, 18.0);

  void _applyElementRotation(Canvas canvas, ElementState element) {
    final rotation = element.rotation;
    if (rotation == 0) {
      return;
    }
    final rect = element.rect;
    canvas
      ..translate(rect.centerX, rect.centerY)
      ..rotate(rotation)
      ..translate(-rect.centerX, -rect.centerY);
  }

  void _setSolidFillPaint(Color color) {
    _fillPaint
      ..color = color
      ..shader = null
      ..colorFilter = null;
  }

  void _paintFill({
    required Canvas canvas,
    required RectangleData data,
    required Color fillColor,
    required RRect rRect,
  }) {
    switch (data.fillStyle) {
      case FillStyle.solid:
        _setSolidFillPaint(fillColor);
        canvas.drawRRect(rRect, _fillPaint);
        return;
      case FillStyle.line:
      case FillStyle.crossLine:
        final fillLineWidth = _resolveFillLineWidth(data.strokeWidth);
        final spacing = _resolveFillLineSpacing(fillLineWidth);
        _fillPaint
          ..color = fillColor
          ..shader = _resolveLineShader(
            spacing: spacing,
            lineWidth: fillLineWidth,
            angle: _lineFillAngle,
          )
          ..colorFilter = ColorFilter.mode(fillColor, BlendMode.modulate);
        canvas.drawRRect(rRect, _fillPaint);

        if (data.fillStyle == FillStyle.crossLine) {
          _fillPaint.shader = _resolveLineShader(
            spacing: spacing,
            lineWidth: fillLineWidth,
            angle: _crossLineFillAngle,
          );
          canvas.drawRRect(rRect, _fillPaint);
        }
        return;
    }
  }

  Shader _resolveLineShader({
    required double spacing,
    required double lineWidth,
    required double angle,
  }) => lineShaderCache.getOrCreate(
    LineShaderKey(spacing: spacing, lineWidth: lineWidth, angle: angle),
    () => buildLineShader(spacing: spacing, lineWidth: lineWidth, angle: angle),
  );

  void _paintStroke({
    required Canvas canvas,
    required RectangleData data,
    required Color strokeColor,
    required RRect rRect,
    required double width,
    required double height,
  }) {
    _strokePaint
      ..strokeWidth = data.strokeWidth
      ..color = strokeColor
      ..strokeCap = StrokeCap.butt
      ..shader = null
      ..colorFilter = null;

    switch (data.strokeStyle) {
      case StrokeStyle.solid:
        canvas.drawRRect(rRect, _strokePaint);
        return;
      case StrokeStyle.dashed:
        final dashLength = data.strokeWidth * 2.0;
        final gapLength = dashLength * 1.2;
        final dashedPath = _strokePathCache.getOrCreate(
          _StrokePathKey(
            width: width,
            height: height,
            cornerRadius: data.cornerRadius,
            strokeStyle: StrokeStyle.dashed,
            patternPrimary: dashLength,
            patternSecondary: gapLength,
          ),
          () => buildDashedPath(Path()..addRRect(rRect), dashLength, gapLength),
        );
        _strokePaint.strokeCap = StrokeCap.round;
        canvas.drawPath(dashedPath, _strokePaint);
        return;
      case StrokeStyle.dotted:
        final dotSpacing = data.strokeWidth * 2.0;
        final dotRadius = data.strokeWidth * 0.5;
        final dottedPath = _strokePathCache.getOrCreate(
          _StrokePathKey(
            width: width,
            height: height,
            cornerRadius: data.cornerRadius,
            strokeStyle: StrokeStyle.dotted,
            patternPrimary: dotSpacing,
            patternSecondary: dotRadius,
          ),
          () => buildDottedPath(Path()..addRRect(rRect), dotSpacing, dotRadius),
        );
        _dotPaint.color = strokeColor;
        canvas.drawPath(dottedPath, _dotPaint);
        return;
    }
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
