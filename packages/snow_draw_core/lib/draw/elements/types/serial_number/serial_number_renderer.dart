import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import '../../../utils/stroke_pattern_utils.dart';
import '../../core/element_renderer.dart';
import 'serial_number_data.dart';
import 'serial_number_layout.dart';

class SerialNumberRenderer extends ElementTypeRenderer {
  const SerialNumberRenderer();

  static const double _lineFillAngle = -math.pi / 4;
  static const double _crossLineFillAngle = math.pi / 4;
  static final _strokePathCache = LruCache<_StrokePathKey, Path>(
    maxEntries: 128,
  );

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
    final _ = scaleFactor;

    final rect = element.rect;
    final rotation = element.rotation;
    final opacity = element.opacity;
    final fillOpacity = (data.fillColor.a * opacity).clamp(0.0, 1.0);
    final strokeOpacity = (data.color.a * opacity).clamp(0.0, 1.0);
    final textOpacity = (data.color.a * opacity).clamp(0.0, 1.0);

    if (fillOpacity <= 0 && strokeOpacity <= 0 && textOpacity <= 0) {
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
    if (rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }

    final strokeWidth = resolveSerialNumberStrokeWidth(data: data);

    if (fillOpacity > 0) {
      _paintFill(canvas, data, circleRect, fillOpacity);
    }

    if (strokeOpacity > 0 && strokeWidth > 0) {
      _paintStroke(canvas, data, circleRect, strokeOpacity, strokeWidth);
    }

    if (textOpacity > 0) {
      _paintText(canvas, data, circleRect, textOpacity, locale);
    }

    canvas.restore();
  }

  void _paintFill(
    Canvas canvas,
    SerialNumberData data,
    Rect circleRect,
    double fillOpacity,
  ) {
    final fillColor = data.fillColor.withValues(alpha: fillOpacity);
    if (data.fillStyle == FillStyle.solid) {
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor
        ..isAntiAlias = true;
      canvas.drawOval(circleRect, paint);
      return;
    }

    // Match text fill spacing so stripes scale with font size.
    final equivalentStrokeWidth = data.fontSize / 42;
    final fillLineWidth = (1 + (equivalentStrokeWidth - 1) * 0.6).clamp(
      0.5,
      3.0,
    );
    const lineToSpacingRatio = 4.0;
    final spacing = (fillLineWidth * lineToSpacingRatio).clamp(3.0, 18.0);
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
      ..color = data.color.withValues(alpha: strokeOpacity)
      ..isAntiAlias = true;

    if (data.strokeStyle == StrokeStyle.solid) {
      canvas.drawOval(circleRect, strokePaint);
      return;
    }

    final path = Path()..addOval(circleRect);
    if (data.strokeStyle == StrokeStyle.dashed) {
      final dashLength = strokeWidth * 2.0;
      final gapLength = dashLength * 1.2;
      final key = _StrokePathKey(
        diameter: circleRect.width,
        strokeStyle: StrokeStyle.dashed,
        patternPrimary: dashLength,
        patternSecondary: gapLength,
      );
      final dashedPath = _strokePathCache.getOrCreate(
        key,
        () => buildDashedPath(path, dashLength, gapLength),
      );
      strokePaint.strokeCap = StrokeCap.round;
      canvas.drawPath(dashedPath, strokePaint);
      return;
    }

    final dotSpacing = strokeWidth * 2.0;
    final dotRadius = strokeWidth * 0.5;
    final key = _StrokePathKey(
      diameter: circleRect.width,
      strokeStyle: StrokeStyle.dotted,
      patternPrimary: dotSpacing,
      patternSecondary: dotRadius,
    );
    final dottedPath = _strokePathCache.getOrCreate(
      key,
      () => buildDottedPath(path, dotSpacing, dotRadius),
    );
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = strokePaint.color
      ..isAntiAlias = true;
    canvas.drawPath(dottedPath, dotPaint);
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
      colorOverride: data.color.withValues(alpha: textOpacity),
      locale: locale,
    );
    final visualCenter =
        layout.visualBounds?.center ??
        Offset(layout.size.width / 2, layout.size.height / 2);
    final offset = Offset(
      circleRect.center.dx - visualCenter.dx,
      circleRect.center.dy - visualCenter.dy,
    );
    layout.painter.paint(canvas, offset);
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
