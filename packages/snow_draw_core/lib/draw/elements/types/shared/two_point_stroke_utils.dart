import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart';

import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';

/// Shared immutable segment payload for two-point stroke fast paths.
@immutable
final class TwoPointStrokeSegment {
  const TwoPointStrokeSegment({required this.start, required this.end});

  /// Segment start in the target coordinate space.
  final Offset start;

  /// Segment end in the target coordinate space.
  final Offset end;
}

/// Returns true when a two-point stroke qualifies for the lightweight path.
bool canUseTwoPointStrokeFastPath({
  required int pointCount,
  required double strokeOpacity,
  required double fillOpacity,
  required double strokeWidth,
}) =>
    pointCount == 2 &&
    strokeOpacity > 0 &&
    fillOpacity <= 0 &&
    strokeWidth > 0 &&
    strokeWidth.isFinite;

/// Resolves normalized points into an element-local segment.
TwoPointStrokeSegment? resolveTwoPointStrokeSegmentLocal({
  required DrawRect rect,
  required DrawPoint startPoint,
  required DrawPoint endPoint,
}) {
  if (!_isFiniteRect(rect)) {
    return null;
  }
  final width = rect.width;
  final height = rect.height;
  final start = Offset(startPoint.x * width, startPoint.y * height);
  final end = Offset(endPoint.x * width, endPoint.y * height);
  if (!_isFiniteOffset(start) || !_isFiniteOffset(end)) {
    return null;
  }
  return TwoPointStrokeSegment(start: start, end: end);
}

/// Resolves normalized points into world-space coordinates.
TwoPointStrokeSegment? resolveTwoPointStrokeSegmentWorld({
  required DrawRect rect,
  required DrawPoint startPoint,
  required DrawPoint endPoint,
}) {
  final local = resolveTwoPointStrokeSegmentLocal(
    rect: rect,
    startPoint: startPoint,
    endPoint: endPoint,
  );
  if (local == null) {
    return null;
  }
  final start = Offset(local.start.dx + rect.minX, local.start.dy + rect.minY);
  final end = Offset(local.end.dx + rect.minX, local.end.dy + rect.minY);
  if (!_isFiniteOffset(start) || !_isFiniteOffset(end)) {
    return null;
  }
  return TwoPointStrokeSegment(start: start, end: end);
}

/// Paints a normalized two-point stroke directly without path caches.
bool renderTwoPointNormalizedStroke({
  required Canvas canvas,
  required DrawRect rect,
  required double rotation,
  required DrawPoint startPoint,
  required DrawPoint endPoint,
  required double strokeWidth,
  required StrokeStyle strokeStyle,
  required Color strokeColor,
}) {
  if (strokeWidth <= 0 || !strokeWidth.isFinite || !_isFiniteRect(rect)) {
    return false;
  }

  final segment = resolveTwoPointStrokeSegmentLocal(
    rect: rect,
    startPoint: startPoint,
    endPoint: endPoint,
  );
  if (segment == null) {
    return false;
  }

  canvas.save();
  if (rotation != 0) {
    canvas
      ..translate(rect.centerX, rect.centerY)
      ..rotate(rotation)
      ..translate(-rect.centerX, -rect.centerY);
  }
  canvas.translate(rect.minX, rect.minY);
  _drawTwoPointStroke(
    canvas: canvas,
    segment: segment,
    strokeWidth: strokeWidth,
    strokeStyle: strokeStyle,
    strokeColor: strokeColor,
  );
  canvas.restore();
  return true;
}

/// Returns true when [point] falls within [radius] of [segment].
bool hitTestTwoPointStrokeSegment({
  required TwoPointStrokeSegment segment,
  required Offset point,
  required double radius,
}) {
  if (!radius.isFinite || radius <= 0 || !_isFiniteOffset(point)) {
    return false;
  }
  if (!_isFiniteOffset(segment.start) || !_isFiniteOffset(segment.end)) {
    return false;
  }
  final distanceSq = _distanceSquaredToSegment(
    point,
    segment.start,
    segment.end,
  );
  return distanceSq <= radius * radius;
}

final _strokePaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

final _dotPaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..isAntiAlias = true;

void _drawTwoPointStroke({
  required Canvas canvas,
  required TwoPointStrokeSegment segment,
  required double strokeWidth,
  required StrokeStyle strokeStyle,
  required Color strokeColor,
}) {
  final strokePaint = _strokePaint
    ..strokeWidth = strokeWidth
    ..color = strokeColor;
  switch (strokeStyle) {
    case StrokeStyle.solid:
      canvas.drawLine(segment.start, segment.end, strokePaint);
      return;
    case StrokeStyle.dashed:
      final dashLength = strokeWidth * 2.0;
      _drawDashedSegment(
        canvas: canvas,
        start: segment.start,
        end: segment.end,
        paint: strokePaint,
        dashLength: dashLength,
        gapLength: dashLength * 1.2,
      );
      return;
    case StrokeStyle.dotted:
      final dotPaint = _dotPaint
        ..strokeWidth = strokeWidth
        ..color = strokeColor;
      canvas.drawRawPoints(
        PointMode.points,
        _buildDottedSegmentPositions(
          start: segment.start,
          end: segment.end,
          spacing: strokeWidth * 2.0,
        ),
        dotPaint,
      );
  }
}

void _drawDashedSegment({
  required Canvas canvas,
  required Offset start,
  required Offset end,
  required Paint paint,
  required double dashLength,
  required double gapLength,
}) {
  final dx = end.dx - start.dx;
  final dy = end.dy - start.dy;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length <= 0 || !length.isFinite) {
    canvas.drawLine(start, end, paint);
    return;
  }

  final unitX = dx / length;
  final unitY = dy / length;
  final step = dashLength + gapLength;
  if (step <= 0 || !step.isFinite) {
    canvas.drawLine(start, end, paint);
    return;
  }
  for (var distance = 0.0; distance < length; distance += step) {
    final dashEnd = math.min(distance + dashLength, length);
    final dashStartOffset = Offset(
      start.dx + unitX * distance,
      start.dy + unitY * distance,
    );
    final dashEndOffset = Offset(
      start.dx + unitX * dashEnd,
      start.dy + unitY * dashEnd,
    );
    canvas.drawLine(dashStartOffset, dashEndOffset, paint);
  }
}

Float32List _buildDottedSegmentPositions({
  required Offset start,
  required Offset end,
  required double spacing,
}) {
  final dx = end.dx - start.dx;
  final dy = end.dy - start.dy;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length <= 0 || !length.isFinite) {
    return Float32List.fromList([start.dx, start.dy]);
  }

  if (!spacing.isFinite) {
    return Float32List.fromList([start.dx, start.dy]);
  }
  final safeSpacing = spacing <= 0 ? 1.0 : spacing;
  final dotCount = (length / safeSpacing).ceil();
  final positions = Float32List(dotCount * 2);
  final unitX = dx / length;
  final unitY = dy / length;

  for (var i = 0; i < dotCount; i++) {
    final distance = i * safeSpacing;
    final offsetIndex = i * 2;
    positions[offsetIndex] = start.dx + unitX * distance;
    positions[offsetIndex + 1] = start.dy + unitY * distance;
  }
  return positions;
}

double _distanceSquaredToSegment(Offset point, Offset start, Offset end) {
  final segment = end - start;
  final toPoint = point - start;
  final segmentLengthSq = segment.dx * segment.dx + segment.dy * segment.dy;
  if (segmentLengthSq == 0) {
    final dx = toPoint.dx;
    final dy = toPoint.dy;
    return dx * dx + dy * dy;
  }

  var t = (toPoint.dx * segment.dx + toPoint.dy * segment.dy) / segmentLengthSq;
  if (t < 0) {
    t = 0;
  } else if (t > 1) {
    t = 1;
  }

  final closest = Offset(start.dx + segment.dx * t, start.dy + segment.dy * t);
  final dx = point.dx - closest.dx;
  final dy = point.dy - closest.dy;
  return dx * dx + dy * dy;
}

bool _isFiniteRect(DrawRect rect) =>
    rect.width.isFinite &&
    rect.height.isFinite &&
    rect.minX.isFinite &&
    rect.minY.isFinite &&
    rect.maxX.isFinite &&
    rect.maxY.isFinite &&
    rect.width >= 0 &&
    rect.height >= 0;

bool _isFiniteOffset(Offset value) => value.dx.isFinite && value.dy.isFinite;
