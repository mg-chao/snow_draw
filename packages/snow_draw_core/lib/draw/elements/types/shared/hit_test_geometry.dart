import 'dart:math' as math;

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';

/// Converts [position] into the element-local coordinate space.
DrawPoint resolveElementLocalPosition({
  required ElementState element,
  required DrawPoint position,
}) {
  if (element.rotation == 0) {
    return position;
  }
  final rect = element.rect;
  final space = ElementSpace(rotation: element.rotation, origin: rect.center);
  return space.fromWorld(position);
}

/// Returns whether [value] has finite coordinates.
bool isFiniteDrawPoint(DrawPoint value) => value.x.isFinite && value.y.isFinite;

/// Returns whether [position] is inside [rect] expanded by [padding].
bool isPointInsideRect(DrawRect rect, DrawPoint position, double padding) =>
    position.x >= rect.minX - padding &&
    position.x <= rect.maxX + padding &&
    position.y >= rect.minY - padding &&
    position.y <= rect.maxY + padding;

/// Hit-tests a normalized two-point stroke against [localPosition].
///
/// [normalizedStart] and [normalizedEnd] are expected in [0, 1] element space.
bool hitTestNormalizedTwoPointStroke({
  required DrawRect rect,
  required DrawPoint normalizedStart,
  required DrawPoint normalizedEnd,
  required DrawPoint localPosition,
  required double strokeWidth,
  required double tolerance,
}) {
  final radius = (strokeWidth / 2) + tolerance;
  if (!radius.isFinite || radius <= 0) {
    return false;
  }
  if (!isPointInsideRect(rect, localPosition, radius)) {
    return false;
  }
  if (!rect.width.isFinite ||
      !rect.height.isFinite ||
      rect.width < 0 ||
      rect.height < 0) {
    return false;
  }

  final start = DrawPoint(
    x: rect.minX + (normalizedStart.x * rect.width),
    y: rect.minY + (normalizedStart.y * rect.height),
  );
  final end = DrawPoint(
    x: rect.minX + (normalizedEnd.x * rect.width),
    y: rect.minY + (normalizedEnd.y * rect.height),
  );
  if (!isFiniteDrawPoint(start) || !isFiniteDrawPoint(end)) {
    return false;
  }
  return distanceSquaredToSegment(localPosition, start, end) <= radius * radius;
}

/// Returns squared distance from point [p] to segment [a]-[b].
double distanceSquaredToSegment(DrawPoint p, DrawPoint a, DrawPoint b) {
  final abX = b.x - a.x;
  final abY = b.y - a.y;
  final apX = p.x - a.x;
  final apY = p.y - a.y;
  final abLengthSq = abX * abX + abY * abY;
  if (abLengthSq == 0) {
    final dx = apX;
    final dy = apY;
    return dx * dx + dy * dy;
  }
  var t = (apX * abX + apY * abY) / abLengthSq;
  if (t < 0) {
    t = 0;
  } else if (t > 1) {
    t = 1;
  }
  final closestX = a.x + abX * t;
  final closestY = a.y + abY * t;
  final dx = p.x - closestX;
  final dy = p.y - closestY;
  return dx * dx + dy * dy;
}

/// Returns squared distance from [point] to the infinite line through [a]-[b].
double _distanceSquaredToLine(DrawPoint point, DrawPoint a, DrawPoint b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final lenSq = dx * dx + dy * dy;
  if (lenSq == 0) {
    final diffX = point.x - a.x;
    final diffY = point.y - a.y;
    return diffX * diffX + diffY * diffY;
  }
  final cross = dx * (point.y - a.y) - dy * (point.x - a.x);
  return (cross * cross) / lenSq;
}

/// Returns true when [point] lies inside [polygon] using even-odd winding.
bool isPointInsidePolygon(
  DrawPoint point,
  List<DrawPoint> polygon, {
  double epsilon = 1e-9,
}) {
  if (polygon.length < 3) {
    return false;
  }

  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final current = polygon[i];
    final previous = polygon[j];
    final intersects =
        (current.y > point.y) != (previous.y > point.y) &&
        point.x <
            (previous.x - current.x) *
                    (point.y - current.y) /
                    ((previous.y - current.y).abs() < epsilon
                        ? epsilon
                        : previous.y - current.y) +
                current.x;
    if (intersects) {
      inside = !inside;
    }
  }
  return inside;
}

/// Returns [a] + [b].
DrawPoint addDrawPoints(DrawPoint a, DrawPoint b) =>
    DrawPoint(x: a.x + b.x, y: a.y + b.y);

/// Returns [a] + [direction] * [scale].
DrawPoint addScaledDrawPoint(DrawPoint a, DrawPoint direction, double scale) =>
    DrawPoint(x: a.x + direction.x * scale, y: a.y + direction.y * scale);

/// Returns [a] - [direction] * [scale].
DrawPoint subtractScaledDrawPoint(
  DrawPoint a,
  DrawPoint direction,
  double scale,
) => DrawPoint(x: a.x - direction.x * scale, y: a.y - direction.y * scale);

/// Returns the midpoint of [a] and [b].
DrawPoint _midpointDrawPoint(DrawPoint a, DrawPoint b) =>
    DrawPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5);

/// Returns normalized [value], or null when it has zero length.
DrawPoint? normalizeDrawVector(DrawPoint value) {
  final length = math.sqrt(value.x * value.x + value.y * value.y);
  if (length == 0) {
    return null;
  }
  return DrawPoint(x: value.x / length, y: value.y / length);
}

/// Cubic segment used for curve flattening.
class CubicDrawSegment {
  /// Creates an immutable cubic segment.
  const CubicDrawSegment({
    required this.start,
    required this.control1,
    required this.control2,
    required this.end,
  });

  /// Segment start point.
  final DrawPoint start;

  /// First control point.
  final DrawPoint control1;

  /// Second control point.
  final DrawPoint control2;

  /// Segment end point.
  final DrawPoint end;
}

/// Builds a Catmull-Rom-derived cubic segment at [index].
CubicDrawSegment buildCatmullRomCubicSegment(
  List<DrawPoint> points,
  int index, {
  double tension = 1.0,
}) {
  final p0 = index == 0 ? points[index] : points[index - 1];
  final p1 = points[index];
  final p2 = points[index + 1];
  final p3 = index + 2 < points.length ? points[index + 2] : points[index + 1];

  final control1 = DrawPoint(
    x: p1.x + (p2.x - p0.x) * (tension / 6),
    y: p1.y + (p2.y - p0.y) * (tension / 6),
  );
  final control2 = DrawPoint(
    x: p2.x - (p3.x - p1.x) * (tension / 6),
    y: p2.y - (p3.y - p1.y) * (tension / 6),
  );
  return CubicDrawSegment(
    start: p1,
    control1: control1,
    control2: control2,
    end: p2,
  );
}

/// Flattens Catmull-Rom points into a polyline for hit testing.
List<DrawPoint> flattenCatmullRomDrawPoints({
  required List<DrawPoint> points,
  required double strokeWidth,
  int maxPoints = 120,
}) {
  if (points.isEmpty) {
    return const <DrawPoint>[];
  }
  if (points.length < 3) {
    return points;
  }

  final step = math.max(1, strokeWidth).toDouble();
  final tolerance = math.max(0.5, step * 0.35);
  final toleranceSq = tolerance * tolerance;

  final flattened = <DrawPoint>[points.first];
  for (var i = 0; i < points.length - 1; i++) {
    if (flattened.length >= maxPoints) {
      break;
    }
    final segment = buildCatmullRomCubicSegment(points, i);
    _flattenCubicSegment(
      segment: segment,
      toleranceSq: toleranceSq,
      output: flattened,
      maxPoints: maxPoints,
    );
  }

  return flattened;
}

void _flattenCubicSegment({
  required CubicDrawSegment segment,
  required double toleranceSq,
  required List<DrawPoint> output,
  required int maxPoints,
}) {
  final stack = <CubicDrawSegment>[segment];
  while (stack.isNotEmpty && output.length < maxPoints) {
    final current = stack.removeLast();
    if (_isCubicFlatEnough(current, toleranceSq) ||
        output.length >= maxPoints - 1) {
      output.add(current.end);
      continue;
    }

    final split = _splitCubicSegment(current);
    stack
      ..add(split.right)
      ..add(split.left);
  }
}

bool _isCubicFlatEnough(CubicDrawSegment segment, double toleranceSq) {
  final dist1 = _distanceSquaredToLine(
    segment.control1,
    segment.start,
    segment.end,
  );
  final dist2 = _distanceSquaredToLine(
    segment.control2,
    segment.start,
    segment.end,
  );
  return math.max(dist1, dist2) <= toleranceSq;
}

({CubicDrawSegment left, CubicDrawSegment right}) _splitCubicSegment(
  CubicDrawSegment segment,
) {
  final p01 = _midpointDrawPoint(segment.start, segment.control1);
  final p12 = _midpointDrawPoint(segment.control1, segment.control2);
  final p23 = _midpointDrawPoint(segment.control2, segment.end);
  final p012 = _midpointDrawPoint(p01, p12);
  final p123 = _midpointDrawPoint(p12, p23);
  final p0123 = _midpointDrawPoint(p012, p123);

  return (
    left: CubicDrawSegment(
      start: segment.start,
      control1: p01,
      control2: p012,
      end: p0123,
    ),
    right: CubicDrawSegment(
      start: p0123,
      control1: p123,
      control2: p23,
      end: segment.end,
    ),
  );
}
