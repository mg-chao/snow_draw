import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_layout.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/lru_cache.dart';

import 'element_type_renderer.dart';
import 'stroke_pattern_utils.dart';

class SerialNumberRenderer extends ElementTypeRenderer {
  const SerialNumberRenderer();

  static const double _lineFillAngle = -math.pi / 4;
  static const double _crossLineFillAngle = math.pi / 4;
  static const _paintScaleTolerance = 0.0001;
  static final _strokePathCache = LruCache<_StrokePathKey, Path>(
    maxEntries: 128,
  );

  /// Clears all static caches held by [SerialNumberRenderer].
  static void clearCaches() {
    _strokePathCache.clear();
  }

  @override
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  }) {
    final data = element.data;
    if (data is! SerialNumberData) {
      throw StateError(
        'SerialNumberRenderer can only render SerialNumberData (got '
        '${data.runtimeType})',
      );
    }

    final rect = element.rect;
    final fillOpacity = (data.fillColor.a * element.opacity).clamp(0.0, 1.0);
    final contentOpacity = (data.color.a * element.opacity).clamp(0.0, 1.0);
    if (fillOpacity <= 0 && contentOpacity <= 0) {
      return;
    }

    final diameter = math.min(rect.width, rect.height);
    if (diameter <= 0) {
      return;
    }

    final radius = diameter / 2;
    final center = Offset(rect.centerX, rect.centerY);
    final circleRect = Rect.fromCircle(center: center, radius: radius);

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }

    final strokeWidth = resolveSerialNumberStrokeWidth(data: data);

    if (fillOpacity > 0) {
      _paintFill(canvas, data, circleRect, fillOpacity);
    }

    if (contentOpacity > 0) {
      if (strokeWidth > 0) {
        _paintStroke(canvas, data, circleRect, contentOpacity, strokeWidth);
      }
      _paintText(canvas, data, circleRect, contentOpacity, locale);
    }

    canvas.restore();
  }

  void _paintFill(
    Canvas canvas,
    SerialNumberData data,
    Rect circleRect,
    double fillOpacity,
  ) {
    final fillColor = Color(
      data.fillColor.withValues(alpha: fillOpacity).toARGB32(),
    );
    switch (data.fillStyle) {
      case FillStyle.solid:
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = fillColor
          ..isAntiAlias = true;
        canvas.drawOval(circleRect, paint);
        return;
      case FillStyle.line:
      case FillStyle.crossLine:
        final equivalentStrokeWidth = data.fontSize / 42;
        final fillLineWidth = (1 + (equivalentStrokeWidth - 1) * 0.6).clamp(
          0.5,
          3.0,
        );
        final spacing = (fillLineWidth * 4.0).clamp(3.0, 18.0);
        final fillPaint = buildLineFillPaint(
          spacing: spacing,
          lineWidth: fillLineWidth,
          angle: _lineFillAngle,
          color: fillColor,
        );
        canvas.drawOval(circleRect, fillPaint);
        if (data.fillStyle == FillStyle.crossLine) {
          final crossPaint = buildLineFillPaint(
            spacing: spacing,
            lineWidth: fillLineWidth,
            angle: _crossLineFillAngle,
            color: fillColor,
          );
          canvas.drawOval(circleRect, crossPaint);
        }
        return;
    }
  }

  void _paintStroke(
    Canvas canvas,
    SerialNumberData data,
    Rect circleRect,
    double strokeOpacity,
    double strokeWidth,
  ) {
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = Color(data.color.withValues(alpha: strokeOpacity).toARGB32())
      ..isAntiAlias = true;

    switch (data.strokeStyle) {
      case StrokeStyle.solid:
        canvas.drawOval(circleRect, strokePaint);
        return;
      case StrokeStyle.dashed:
        final dashLength = strokeWidth * 2.0;
        final gapLength = dashLength * 1.2;
        final dashedPath = _strokePathCache.getOrCreate(
          _StrokePathKey(
            diameter: circleRect.width,
            strokeStyle: StrokeStyle.dashed,
            patternPrimary: dashLength,
            patternSecondary: gapLength,
          ),
          () => buildDashedPath(
            Path()..addOval(circleRect),
            dashLength,
            gapLength,
          ),
        );
        strokePaint.strokeCap = StrokeCap.round;
        canvas.drawPath(dashedPath, strokePaint);
        return;
      case StrokeStyle.dotted:
        final dotSpacing = strokeWidth * 2.0;
        final dotRadius = strokeWidth * 0.5;
        final dottedPath = _strokePathCache.getOrCreate(
          _StrokePathKey(
            diameter: circleRect.width,
            strokeStyle: StrokeStyle.dotted,
            patternPrimary: dotSpacing,
            patternSecondary: dotRadius,
          ),
          () => buildDottedPath(
            Path()..addOval(circleRect),
            dotSpacing,
            dotRadius,
          ),
        );
        final dotPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = strokePaint.color
          ..isAntiAlias = true;
        canvas.drawPath(dottedPath, dotPaint);
        return;
    }
  }

  void _paintText(
    Canvas canvas,
    SerialNumberData data,
    Rect circleRect,
    double textOpacity,
    Locale? locale,
  ) {
    final layout = layoutSerialNumberText(
      data: data,
      colorOverride: Color(
        data.color.withValues(alpha: textOpacity).toARGB32(),
      ),
      locale: locale,
    );
    final visualCenter =
        layout.visualBounds?.center ??
        Offset(layout.size.width / 2, layout.size.height / 2);
    final offset = Offset(
      circleRect.center.dx - visualCenter.dx,
      circleRect.center.dy - visualCenter.dy,
    );
    final paintScale = layout.paintScale;
    if (paintScale <= 0) {
      return;
    }
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    if ((paintScale - 1).abs() > _paintScaleTolerance) {
      canvas.scale(paintScale, paintScale);
    }
    layout.painter.paint(canvas, Offset.zero);
    canvas.restore();
  }
}

@immutable
class _StrokePathKey {
  _StrokePathKey({
    required double diameter,
    required this.strokeStyle,
    required double patternPrimary,
    required double patternSecondary,
  }) : diameter = _quantize(diameter),
       patternPrimary = _quantize(patternPrimary),
       patternSecondary = _quantize(patternSecondary);

  final double diameter;
  final StrokeStyle strokeStyle;
  final double patternPrimary;
  final double patternSecondary;

  static double _quantize(double value) => (value * 10).roundToDouble() / 10;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _StrokePathKey &&
          other.diameter == diameter &&
          other.strokeStyle == strokeStyle &&
          other.patternPrimary == patternPrimary &&
          other.patternSecondary == patternSecondary;

  @override
  int get hashCode =>
      Object.hash(diameter, strokeStyle, patternPrimary, patternSecondary);
}
