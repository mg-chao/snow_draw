import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart'
    show Alignment, GradientRotation, LinearGradient;
import 'package:meta/meta.dart';

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import '../../core/element_renderer.dart';
import 'free_draw_data.dart';

class FreeDrawRenderer extends ElementTypeRenderer {
  const FreeDrawRenderer();

  static const double _lineFillAngle = -math.pi / 4;
  static const double _crossLineFillAngle = math.pi / 4;
  static final _lineShaderCache = LruCache<_LineShaderKey, Shader>(
    maxEntries: 128,
  );
  static final _visualCache = _FreeDrawVisualCache(maxEntries: 256);

  @override
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  }) {
    final data = element.data;
    if (data is! FreeDrawData) {
      throw StateError(
        'FreeDrawRenderer can only render FreeDrawData '
        '(got ${data.runtimeType})',
      );
    }
    final _ = scaleFactor;

    final rect = element.rect;
    final opacity = element.opacity;
    final strokeOpacity = (data.color.a * opacity).clamp(0.0, 1.0);
    final fillOpacity = (data.fillColor.a * opacity).clamp(0.0, 1.0);
    if (strokeOpacity <= 0 && fillOpacity <= 0) {
      return;
    }

    final cached = _visualCache.resolve(element: element, data: data);
    if (cached.pointCount < 2) {
      return;
    }

    final shouldFill =
        fillOpacity > 0 && _isClosed(data) && cached.pointCount > 2;

    canvas.save();
    if (element.rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(element.rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }
    canvas.translate(rect.minX, rect.minY);

    if (shouldFill) {
      final fillPath = Path()
        ..addPath(cached.path, Offset.zero)
        ..close();
      if (data.fillStyle == FillStyle.solid) {
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = data.fillColor.withValues(alpha: fillOpacity)
          ..isAntiAlias = true;
        canvas.drawPath(fillPath, paint);
      } else {
        final fillLineWidth = (1 + (data.strokeWidth - 1) * 0.6).clamp(
          0.5,
          3.0,
        );
        const lineToSpacingRatio = 4.0;
        final spacing = (fillLineWidth * lineToSpacingRatio).clamp(3.0, 18.0);
        final fillColor = data.fillColor.withValues(alpha: fillOpacity);
        final fillPaint = _buildLineFillPaint(
          spacing: spacing,
          lineWidth: fillLineWidth,
          angle: _lineFillAngle,
          color: fillColor,
        );
        canvas.drawPath(fillPath, fillPaint);
        if (data.fillStyle == FillStyle.crossLine) {
          final crossPaint = _buildLineFillPaint(
            spacing: spacing,
            lineWidth: fillLineWidth,
            angle: _crossLineFillAngle,
            color: fillColor,
          );
          canvas.drawPath(fillPath, crossPaint);
        }
      }
    }

    if (strokeOpacity > 0 && data.strokeWidth > 0) {
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = data.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = data.color.withValues(alpha: strokeOpacity)
        ..isAntiAlias = true;

      if (data.strokeStyle == StrokeStyle.dotted) {
        final dottedPath = cached.dottedPath;
        if (dottedPath != null) {
          final dotPaint = Paint()
            ..style = PaintingStyle.fill
            ..color = strokePaint.color
            ..isAntiAlias = true;
          canvas.drawPath(dottedPath, dotPaint);
        }
      } else {
        final combinedPath = cached.strokePath;
        if (combinedPath != null) {
          canvas.drawPath(combinedPath, strokePaint);
        }
      }
    }

    canvas.restore();
  }

  bool _isClosed(FreeDrawData data) =>
      data.points.length > 2 && data.points.first == data.points.last;

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

class _FreeDrawVisualCacheEntry {
  _FreeDrawVisualCacheEntry({
    required this.data,
    required this.width,
    required this.height,
    required this.pointCount,
    required this.path,
    required this.strokePath,
    required this.dottedPath,
  });

  final FreeDrawData data;
  final double width;
  final double height;
  final int pointCount;
  final Path path;
  final Path? strokePath;
  final Path? dottedPath;

  bool matches(FreeDrawData data, double width, double height) =>
      identical(this.data, data) && this.width == width && this.height == height;
}

class _FreeDrawVisualCache {
  _FreeDrawVisualCache({required int maxEntries})
    : _entries = LruCache<String, _FreeDrawVisualCacheEntry>(
        maxEntries: maxEntries,
      );

  final LruCache<String, _FreeDrawVisualCacheEntry> _entries;

  _FreeDrawVisualCacheEntry resolve({
    required ElementState element,
    required FreeDrawData data,
  }) {
    final id = element.id;
    final width = element.rect.width;
    final height = element.rect.height;
    final existing = _entries.get(id);
    if (existing != null && existing.matches(data, width, height)) {
      return existing;
    }

    final entry = _buildEntry(element: element, data: data);
    _entries.put(id, entry);
    return entry;
  }

  _FreeDrawVisualCacheEntry _buildEntry({
    required ElementState element,
    required FreeDrawData data,
  }) {
    final rect = element.rect;
    final localPoints = _resolveLocalPoints(rect: rect, points: data.points);
    if (localPoints.length < 2) {
      return _FreeDrawVisualCacheEntry(
        data: data,
        width: rect.width,
        height: rect.height,
        pointCount: localPoints.length,
        path: Path(),
        strokePath: null,
        dottedPath: null,
      );
    }

    final basePath = _buildSmoothPath(localPoints);

    Path? strokePath;
    Path? dottedPath;

    if (data.strokeWidth > 0) {
      switch (data.strokeStyle) {
        case StrokeStyle.solid:
          strokePath = basePath;
        case StrokeStyle.dashed:
          final dashLength = data.strokeWidth * 2.0;
          final gapLength = dashLength * 1.2;
          strokePath = _buildDashedPath(basePath, dashLength, gapLength);
        case StrokeStyle.dotted:
          final dotSpacing = data.strokeWidth * 2.0;
          final dotRadius = data.strokeWidth * 0.5;
          dottedPath = _buildDottedPath(basePath, dotSpacing, dotRadius);
      }
    }

    return _FreeDrawVisualCacheEntry(
      data: data,
      width: rect.width,
      height: rect.height,
      pointCount: localPoints.length,
      path: basePath,
      strokePath: strokePath,
      dottedPath: dottedPath,
    );
  }
}

List<Offset> _resolveLocalPoints({
  required DrawRect rect,
  required List<DrawPoint> points,
}) {
  if (points.isEmpty) {
    return const <Offset>[];
  }
  final width = rect.width;
  final height = rect.height;
  return points
      .map((point) => Offset(point.x * width, point.y * height))
      .toList(growable: false);
}

Path _buildSmoothPath(List<Offset> points) {
  if (points.length < 2) {
    return Path();
  }
  if (points.length == 2) {
    return Path()
      ..moveTo(points.first.dx, points.first.dy)
      ..lineTo(points.last.dx, points.last.dy);
  }

  final closed = points.first == points.last;
  final source = closed ? points.sublist(0, points.length - 1) : points;
  final smoothed = _smoothPoints(source, closed: closed);
  if (smoothed.length < 2) {
    return Path();
  }

  final path = Path()..moveTo(smoothed.first.dx, smoothed.first.dy);
  const tension = 0.5;
  final count = smoothed.length;

  if (closed) {
    for (var i = 0; i < count; i++) {
      final p0 = smoothed[(i - 1 + count) % count];
      final p1 = smoothed[i];
      final p2 = smoothed[(i + 1) % count];
      final p3 = smoothed[(i + 2) % count];

      final cp1 = p1 + (p2 - p0) * (tension / 6);
      final cp2 = p2 - (p3 - p1) * (tension / 6);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  for (var i = 0; i < count - 1; i++) {
    final p0 = i == 0 ? smoothed[i] : smoothed[i - 1];
    final p1 = smoothed[i];
    final p2 = smoothed[i + 1];
    final p3 = i + 2 < count ? smoothed[i + 2] : smoothed[i + 1];

    final cp1 = p1 + (p2 - p0) * (tension / 6);
    final cp2 = p2 - (p3 - p1) * (tension / 6);
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
  }
  return path;
}

List<Offset> _smoothPoints(List<Offset> points, {required bool closed}) {
  if (points.length < 3) {
    return points;
  }

  const iterations = 3;
  var working = List<Offset>.from(points);

  for (var iter = 0; iter < iterations; iter++) {
    final next = List<Offset>.from(working);
    final lastIndex = working.length - 1;

    if (closed) {
      for (var i = 0; i <= lastIndex; i++) {
        final prev = working[(i - 1 + working.length) % working.length];
        final curr = working[i];
        final nextPoint = working[(i + 1) % working.length];
        next[i] = Offset(
          (prev.dx + curr.dx * 2 + nextPoint.dx) * 0.25,
          (prev.dy + curr.dy * 2 + nextPoint.dy) * 0.25,
        );
      }
    } else {
      for (var i = 1; i < lastIndex; i++) {
        final prev = working[i - 1];
        final curr = working[i];
        final nextPoint = working[i + 1];
        next[i] = Offset(
          (prev.dx + curr.dx * 2 + nextPoint.dx) * 0.25,
          (prev.dy + curr.dy * 2 + nextPoint.dy) * 0.25,
        );
      }
      next[0] = working[0];
      next[lastIndex] = working[lastIndex];
    }

    working = next;
  }

  return working;
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
