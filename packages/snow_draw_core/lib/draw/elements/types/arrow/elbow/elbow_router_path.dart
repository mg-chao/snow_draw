part of 'elbow_router.dart';

/// Path construction and cleanup for elbow routing.
///
/// Contains the direct-route checks, fallback routing, intersection tests,
/// and post-processing that guarantees orthogonal, stable point lists.

({bool alignedX, bool alignedY}) _axisAlignment(
  DrawPoint start,
  DrawPoint end,
) => (
  alignedX: (start.x - end.x).abs() <= _dedupThreshold,
  alignedY: (start.y - end.y).abs() <= _dedupThreshold,
);

bool _headingsCompatibleWithAlignment({
  required bool alignedX,
  required bool alignedY,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
}) {
  if (alignedY && (!startHeading.isHorizontal || !endHeading.isHorizontal)) {
    return false;
  }
  if (alignedX && (startHeading.isHorizontal || endHeading.isHorizontal)) {
    return false;
  }
  return true;
}

bool _segmentRespectsEndpointConstraints({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required bool startConstrained,
  required bool endConstrained,
}) {
  final segmentHeading = _segmentHeading(start, end);
  if (startConstrained && segmentHeading != startHeading) {
    return false;
  }
  if (endConstrained && segmentHeading != endHeading.opposite) {
    return false;
  }
  return true;
}

List<DrawPoint>? _directPathIfClear({
  required DrawPoint start,
  required DrawPoint end,
  required List<DrawRect> obstacles,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required bool startConstrained,
  required bool endConstrained,
}) {
  final alignment = _axisAlignment(start, end);
  if (!alignment.alignedX && !alignment.alignedY) {
    return null;
  }
  if (!_headingsCompatibleWithAlignment(
    alignedX: alignment.alignedX,
    alignedY: alignment.alignedY,
    startHeading: startHeading,
    endHeading: endHeading,
  )) {
    return null;
  }

  if (!_segmentRespectsEndpointConstraints(
    start: start,
    end: end,
    startHeading: startHeading,
    endHeading: endHeading,
    startConstrained: startConstrained,
    endConstrained: endConstrained,
  )) {
    return null;
  }

  if (_segmentIntersectsAnyBounds(start, end, obstacles)) {
    return null;
  }
  return [start, end];
}

bool _segmentIntersectsBounds(DrawPoint start, DrawPoint end, DrawRect bounds) {
  final innerBounds = _shrinkBounds(bounds, _intersectionEpsilon);
  if (!_hasArea(innerBounds)) {
    return false;
  }

  final dx = (start.x - end.x).abs();
  final dy = (start.y - end.y).abs();
  if (dx <= _dedupThreshold) {
    return _verticalSegmentIntersectsBounds(start, end, innerBounds);
  }
  if (dy <= _dedupThreshold) {
    return _horizontalSegmentIntersectsBounds(start, end, innerBounds);
  }
  return _diagonalSegmentIntersectsBounds(start, end, innerBounds);
}

DrawRect _shrinkBounds(DrawRect bounds, double inset) => DrawRect(
  minX: bounds.minX + inset,
  minY: bounds.minY + inset,
  maxX: bounds.maxX - inset,
  maxY: bounds.maxY - inset,
);

bool _hasArea(DrawRect bounds) =>
    bounds.minX < bounds.maxX && bounds.minY < bounds.maxY;

double _overlapLength(
  double minA,
  double maxA,
  double minB,
  double maxB,
) => math.min(maxA, maxB) - math.max(minA, minB);

bool _verticalSegmentIntersectsBounds(
  DrawPoint start,
  DrawPoint end,
  DrawRect bounds,
) {
  final x = (start.x + end.x) / 2;
  if (x < bounds.minX || x > bounds.maxX) {
    return false;
  }
  final segMinY = math.min(start.y, end.y);
  final segMaxY = math.max(start.y, end.y);
  return _overlapLength(segMinY, segMaxY, bounds.minY, bounds.maxY) >
      _intersectionEpsilon;
}

bool _horizontalSegmentIntersectsBounds(
  DrawPoint start,
  DrawPoint end,
  DrawRect bounds,
) {
  final y = (start.y + end.y) / 2;
  if (y < bounds.minY || y > bounds.maxY) {
    return false;
  }
  final segMinX = math.min(start.x, end.x);
  final segMaxX = math.max(start.x, end.x);
  return _overlapLength(segMinX, segMaxX, bounds.minX, bounds.maxX) >
      _intersectionEpsilon;
}

bool _diagonalSegmentIntersectsBounds(
  DrawPoint start,
  DrawPoint end,
  DrawRect bounds,
) {
  final segMinX = math.min(start.x, end.x);
  final segMaxX = math.max(start.x, end.x);
  final segMinY = math.min(start.y, end.y);
  final segMaxY = math.max(start.y, end.y);
  if (segMaxX < bounds.minX ||
      segMinX > bounds.maxX ||
      segMaxY < bounds.minY ||
      segMinY > bounds.maxY) {
    return false;
  }
  return true;
}

List<DrawPoint> _fallbackPath({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowHeading startHeading,
}) {
  if (_manhattanDistance(start, end) < _minArrowLength) {
    final midY = (start.y + end.y) / 2;
    return [
      start,
      DrawPoint(x: start.x, y: midY),
      DrawPoint(x: end.x, y: midY),
      end,
    ];
  }

  if ((start.x - end.x).abs() <= _dedupThreshold ||
      (start.y - end.y).abs() <= _dedupThreshold) {
    return [start, end];
  }

  if (startHeading.isHorizontal) {
    final midX = (start.x + end.x) / 2;
    return [
      start,
      DrawPoint(x: midX, y: start.y),
      DrawPoint(x: midX, y: end.y),
      end,
    ];
  }

  final midY = (start.y + end.y) / 2;
  return [
    start,
    DrawPoint(x: start.x, y: midY),
    DrawPoint(x: end.x, y: midY),
    end,
  ];
}

List<DrawPoint> _postProcessPath({
  required List<_GridNode> path,
  required DrawPoint startPoint,
  required DrawPoint endPoint,
  required DrawPoint startDongle,
  required DrawPoint endDongle,
}) {
  if (path.isEmpty) {
    return [startPoint, endPoint];
  }
  final points = <DrawPoint>[];
  if (startDongle != startPoint && path.first.pos != startPoint) {
    points.add(startPoint);
  }
  for (final node in path) {
    points.add(node.pos);
  }
  if (endDongle != endPoint && points.last != endPoint) {
    points.add(endPoint);
  }
  return points;
}

List<DrawPoint> _removeShortSegments(List<DrawPoint> points) {
  if (points.length < 4) {
    return points;
  }
  final filtered = <DrawPoint>[];
  for (var i = 0; i < points.length; i++) {
    if (i == 0 || i == points.length - 1) {
      filtered.add(points[i]);
      continue;
    }
    if (_manhattanDistance(points[i - 1], points[i]) > _dedupThreshold) {
      filtered.add(points[i]);
    }
  }
  return filtered;
}

List<DrawPoint> _getCornerPoints(List<DrawPoint> points) {
  if (points.length <= 2) {
    return points;
  }

  var previousIsHorizontal = _isHorizontal(points[0], points[1]);
  final result = <DrawPoint>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final nextIsHorizontal = _isHorizontal(points[i], points[i + 1]);
    if (previousIsHorizontal != nextIsHorizontal) {
      result.add(points[i]);
    }
    previousIsHorizontal = nextIsHorizontal;
  }
  result.add(points.last);
  return result;
}

List<DrawPoint> _finalizeRoutedPath({
  required List<DrawPoint> points,
  required ElbowHeading startHeading,
}) {
  // Step 5: enforce orthogonality, remove tiny segments, and clamp.
  final orthogonalized = _ensureOrthogonalPath(
    points: points,
    startHeading: startHeading,
  );
  final cleaned = _getCornerPoints(_removeShortSegments(orthogonalized));
  return cleaned.map(_clampPoint).toList(growable: false);
}

ElbowHeading _headingBetween(DrawPoint from, DrawPoint to) =>
    _vectorToHeading(from.x - to.x, from.y - to.y);

ElbowHeading _segmentHeading(DrawPoint from, DrawPoint to) =>
    _vectorToHeading(to.x - from.x, to.y - from.y);

bool _segmentIntersectsAnyBounds(
  DrawPoint start,
  DrawPoint end,
  List<DrawRect> obstacles,
) {
  for (final obstacle in obstacles) {
    if (_segmentIntersectsBounds(start, end, obstacle)) {
      return true;
    }
  }
  return false;
}

List<DrawPoint> _ensureOrthogonalPath({
  required List<DrawPoint> points,
  required ElbowHeading startHeading,
}) {
  // Insert a midpoint when a diagonal would appear between consecutive points.
  if (points.length < 2) {
    return points;
  }
  final result = <DrawPoint>[points.first];
  for (var i = 1; i < points.length; i++) {
    final previous = result.last;
    final next = points[i];
    final dx = (next.x - previous.x).abs();
    final dy = (next.y - previous.y).abs();
    if (dx <= _dedupThreshold || dy <= _dedupThreshold) {
      if (next != previous) {
        result.add(next);
      }
      continue;
    }

    final preferHorizontal = result.length > 1
        ? _isHorizontal(result[result.length - 2], previous)
        : startHeading.isHorizontal;
    final mid = preferHorizontal
        ? DrawPoint(x: next.x, y: previous.y)
        : DrawPoint(x: previous.x, y: next.y);
    if (mid != previous) {
      result.add(mid);
    }
    if (next != mid) {
      result.add(next);
    }
  }
  return result;
}

bool _isHorizontal(DrawPoint a, DrawPoint b) =>
    (a.y - b.y).abs() <= (a.x - b.x).abs();
