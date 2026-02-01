part of 'elbow_editing.dart';

/// Geometry helpers shared across elbow editing flows.

List<DrawPoint> _resolveLocalPoints(ElementState element, ArrowData data) {
  final resolved = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );
  return resolved
      .map((point) => DrawPoint(x: point.dx, y: point.dy))
      .toList(growable: false);
}

List<DrawPoint> _simplifyPath(
  List<DrawPoint> points, {
  Set<DrawPoint> pinned = const <DrawPoint>{},
}) {
  if (points.length < 3) {
    return points;
  }

  final withoutCollinear = <DrawPoint>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final point = points[i];
    if (pinned.contains(point)) {
      withoutCollinear.add(point);
      continue;
    }
    final prev = withoutCollinear.last;
    final next = points[i + 1];
    final isHorizontalPrev = _isHorizontal(prev, point);
    final isHorizontalNext = _isHorizontal(point, next);
    if (isHorizontalPrev == isHorizontalNext) {
      continue;
    }
    withoutCollinear.add(point);
  }
  withoutCollinear.add(points.last);

  final cleaned = <DrawPoint>[withoutCollinear.first];
  for (var i = 1; i < withoutCollinear.length; i++) {
    final point = withoutCollinear[i];
    if (point == cleaned.last) {
      continue;
    }
    final length = _manhattanDistance(cleaned.last, point);
    if (length <= _dedupThreshold && !pinned.contains(point)) {
      continue;
    }
    cleaned.add(point);
  }

  return List<DrawPoint>.unmodifiable(cleaned);
}

bool _hasDiagonalSegments(List<DrawPoint> points) {
  if (points.length < 2) {
    return false;
  }
  for (var i = 1; i < points.length; i++) {
    final dx = (points[i].x - points[i - 1].x).abs();
    final dy = (points[i].y - points[i - 1].y).abs();
    if (dx > _dedupThreshold && dy > _dedupThreshold) {
      return true;
    }
  }
  return false;
}

bool _segmentsCollinear(DrawPoint a, DrawPoint b, DrawPoint c) {
  final horizontal = _isHorizontal(a, b);
  final nextHorizontal = _isHorizontal(b, c);
  if (horizontal != nextHorizontal) {
    return false;
  }
  if (horizontal) {
    return (a.y - b.y).abs() <= _dedupThreshold &&
        (b.y - c.y).abs() <= _dedupThreshold;
  }
  return (a.x - b.x).abs() <= _dedupThreshold &&
      (b.x - c.x).abs() <= _dedupThreshold;
}

bool _isHorizontal(DrawPoint a, DrawPoint b) =>
    (a.y - b.y).abs() <= (a.x - b.x).abs();

double _manhattanDistance(DrawPoint a, DrawPoint b) =>
    (a.x - b.x).abs() + (a.y - b.y).abs();

bool _pointsEqual(List<DrawPoint> a, List<DrawPoint> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _pointsEqualExceptEndpoints(List<DrawPoint> a, List<DrawPoint> b) {
  if (a.length != b.length || a.length < 2) {
    return false;
  }
  for (var i = 1; i < a.length - 1; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
