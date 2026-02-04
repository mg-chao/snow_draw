import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart'
    show Alignment, GradientRotation, LinearGradient;

import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../core/element_renderer.dart';
import 'serial_number_data.dart';
import 'serial_number_layout.dart';

class SerialNumberRenderer extends ElementTypeRenderer {
  const SerialNumberRenderer();

  static const double _lineFillAngle = -math.pi / 4;
  static const double _crossLineFillAngle = math.pi / 4;
  static final _lineShaderCache = _LruCache<_LineShaderKey, Shader>(
    maxEntries: 64,
  );
  static final _strokePathCache = _LruCache<_StrokePathKey, Path>(
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

    if (fillOpacity > 0) {
      _paintFill(canvas, data, circleRect, fillOpacity);
    }

    if (strokeOpacity > 0 && data.strokeWidth > 0) {
      _paintStroke(canvas, data, circleRect, strokeOpacity);
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

    final fillLineWidth = (1 + (data.strokeWidth - 1) * 0.6).clamp(0.5, 3.0);
    const lineToSpacingRatio = 4.0;
    final spacing = (fillLineWidth * lineToSpacingRatio).clamp(3.0, 18.0);
    final fillPaint = _buildLineFillPaint(
      spacing: spacing,
      lineWidth: fillLineWidth,
      angle: _lineFillAngle,
      color: fillColor,
    );
    canvas.drawOval(circleRect, fillPaint);
    if (data.fillStyle == FillStyle.crossLine) {
      final crossPaint = _buildLineFillPaint(
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
  ) {
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = data.strokeWidth
      ..color = data.color.withValues(alpha: strokeOpacity)
      ..isAntiAlias = true;

    if (data.strokeStyle == StrokeStyle.solid) {
      canvas.drawOval(circleRect, strokePaint);
      return;
    }

    final path = Path()..addOval(circleRect);
    if (data.strokeStyle == StrokeStyle.dashed) {
      final dashLength = data.strokeWidth * 2.0;
      final gapLength = dashLength * 1.2;
      final key = _StrokePathKey(
        diameter: circleRect.width,
        strokeStyle: StrokeStyle.dashed,
        patternPrimary: dashLength,
        patternSecondary: gapLength,
      );
      final dashedPath = _strokePathCache.getOrCreate(
        key,
        () => _buildDashedPath(path, dashLength, gapLength),
      );
      strokePaint.strokeCap = StrokeCap.round;
      canvas.drawPath(dashedPath, strokePaint);
      return;
    }

    final dotSpacing = data.strokeWidth * 2.0;
    final dotRadius = data.strokeWidth * 0.5;
    final key = _StrokePathKey(
      diameter: circleRect.width,
      strokeStyle: StrokeStyle.dotted,
      patternPrimary: dotSpacing,
      patternSecondary: dotRadius,
    );
    final dottedPath = _strokePathCache.getOrCreate(
      key,
      () => _buildDottedPath(path, dotSpacing, dotRadius),
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
    final visualCenter = layout.visualBounds?.center ??
        Offset(layout.size.width / 2, layout.size.height / 2);
    final offset = Offset(
      circleRect.center.dx - visualCenter.dx,
      circleRect.center.dy - visualCenter.dy,
    );
    layout.painter.paint(canvas, offset);
  }

  Paint _buildLineFillPaint({
    required double spacing,
    required double lineWidth,
    required double angle,
    required Color color,
  }) => Paint()
    ..style = PaintingStyle.fill
    ..shader = _lineShaderCache.getOrCreate(
      _LineShaderKey(spacing: spacing, lineWidth: lineWidth, angle: angle),
      () => _buildLineShader(
        spacing: spacing,
        lineWidth: lineWidth,
        angle: angle,
      ),
    )
    ..colorFilter = ColorFilter.mode(color, BlendMode.modulate)
    ..isAntiAlias = true;

  Shader _buildLineShader({
    required double spacing,
    required double lineWidth,
    required double angle,
  }) {
    final safeSpacing = spacing <= 0 ? 1.0 : spacing;
    final lineStop = (lineWidth / safeSpacing).clamp(0.0, 1.0);
    final cosAngle = math.cos(angle).abs();
    final adjustedSpacing = cosAngle > 0.01
        ? safeSpacing / cosAngle
        : safeSpacing;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      tileMode: TileMode.repeated,
      colors: const [
        Color(0xFFFFFFFF),
        Color(0xFFFFFFFF),
        Color(0x00FFFFFF),
        Color(0x00FFFFFF),
      ],
      stops: [0.0, lineStop, lineStop, 1.0],
      transform: GradientRotation(angle),
    ).createShader(Rect.fromLTWH(0, 0, adjustedSpacing, adjustedSpacing));
  }

  Path _buildDashedPath(Path basePath, double dashLength, double gapLength) {
    final dashed = Path();
    for (final metric in basePath.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        dashed.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + gapLength;
      }
    }
    return dashed;
  }

  Path _buildDottedPath(Path basePath, double dotSpacing, double dotRadius) {
    final dotted = Path();
    for (final metric in basePath.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final tangent = metric.getTangentForOffset(distance);
        if (tangent != null) {
          dotted.addOval(
            Rect.fromCircle(center: tangent.position, radius: dotRadius),
          );
        }
        distance += dotSpacing;
      }
    }
    return dotted;
  }
}

class _LruCache<K, V> {
  _LruCache({required this.maxEntries});

  final int maxEntries;
  final _cache = <K, V>{};

  V getOrCreate(K key, V Function() builder) {
    final existing = _cache.remove(key);
    if (existing != null) {
      _cache[key] = existing;
      return existing;
    }
    final value = builder();
    _cache[key] = value;
    if (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return value;
  }
}

@immutable
class _LineShaderKey {
  _LineShaderKey({
    required double spacing,
    required double lineWidth,
    required this.angle,
  }) : spacing = _quantize(spacing),
       lineWidth = _quantize(lineWidth);

  final double spacing;
  final double lineWidth;
  final double angle;

  static double _quantize(double value) => (value * 10).roundToDouble() / 10;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LineShaderKey &&
          other.spacing == spacing &&
          other.lineWidth == lineWidth &&
          other.angle == angle;

  @override
  int get hashCode => Object.hash(spacing, lineWidth, angle);
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
