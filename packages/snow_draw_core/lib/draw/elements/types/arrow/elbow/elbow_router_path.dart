part of 'elbow_router.dart';

/// Path construction and cleanup for elbow routing.
///
/// Contains the direct-route checks, fallback routing, intersection tests,
/// and post-processing that guarantees orthogonal, stable point lists.

/// Axis alignment between two points using elbow tolerances.
@immutable
final class _AxisAlignment {
  const _AxisAlignment({required this.alignedX, required this.alignedY});

  final bool alignedX;
  final bool alignedY;

  bool get isAligned => alignedX || alignedY;
}

_AxisAlignment _resolveAxisAlignment(DrawPoint start, DrawPoint end) =>
    _AxisAlignment(
      alignedX: (start.x - end.x).abs() <= ElbowConstants.dedupThreshold,
      alignedY: (start.y - end.y).abs() <= ElbowConstants.dedupThreshold,
    );

/// Checks whether endpoint headings allow a direct aligned segment.
bool _headingsCompatibleWithAlignment({
  required _AxisAlignment alignment,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
}) {
  if (alignment.alignedY &&
      (!startHeading.isHorizontal || !endHeading.isHorizontal)) {
    return false;
  }
  if (alignment.alignedX &&
      (startHeading.isHorizontal || endHeading.isHorizontal)) {
    return false;
  }
  return true;
}

/// Ensures a direct segment does not violate bound endpoint headings.
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

/// Returns a direct 2-point route when alignment + constraints allow it.
List<DrawPoint>? _directPathIfClear({
  required DrawPoint start,
  required DrawPoint end,
  required List<DrawRect> obstacles,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required bool startConstrained,
  required bool endConstrained,
}) {
  final alignment = _resolveAxisAlignment(start, end);
  if (!alignment.isAligned) {
    return null;
  }
  if (!_headingsCompatibleWithAlignment(
    alignment: alignment,
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
  final innerBounds = _shrinkBounds(bounds, ElbowConstants.intersectionEpsilon);
  if (!_hasArea(innerBounds)) {
    return false;
  }

  final dx = (start.x - end.x).abs();
  final dy = (start.y - end.y).abs();
  if (dx <= ElbowConstants.dedupThreshold) {
    return _verticalSegmentIntersectsBounds(start, end, innerBounds);
  }
  if (dy <= ElbowConstants.dedupThreshold) {
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

double _overlapLength(double minA, double maxA, double minB, double maxB) =>
    math.min(maxA, maxB) - math.max(minA, minB);

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
      ElbowConstants.intersectionEpsilon;
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
      ElbowConstants.intersectionEpsilon;
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
  if (ElbowGeometry.manhattanDistance(start, end) <
      ElbowConstants.minArrowLength) {
    final midY = (start.y + end.y) / 2;
    return [
      start,
      DrawPoint(x: start.x, y: midY),
      DrawPoint(x: end.x, y: midY),
      end,
    ];
  }

  if ((start.x - end.x).abs() <= ElbowConstants.dedupThreshold ||
      (start.y - end.y).abs() <= ElbowConstants.dedupThreshold) {
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
  required List<_ElbowGridNode> path,
  required DrawPoint startPoint,
  required DrawPoint endPoint,
  required DrawPoint startExit,
  required DrawPoint endExit,
}) {
  if (path.isEmpty) {
    return [startPoint, endPoint];
  }
  final points = <DrawPoint>[];
  if (startExit != startPoint && path.first.pos != startPoint) {
    points.add(startPoint);
  }
  for (final node in path) {
    points.add(node.pos);
  }
  if (endExit != endPoint && points.last != endPoint) {
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
    if (ElbowGeometry.manhattanDistance(points[i - 1], points[i]) >
        ElbowConstants.dedupThreshold) {
      filtered.add(points[i]);
    }
  }
  return filtered;
}

List<DrawPoint> _getCornerPoints(List<DrawPoint> points) {
  if (points.length <= 2) {
    return points;
  }

  var previousIsHorizontal = ElbowGeometry.isHorizontal(points[0], points[1]);
  final result = <DrawPoint>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final nextIsHorizontal = ElbowGeometry.isHorizontal(
      points[i],
      points[i + 1],
    );
    if (previousIsHorizontal != nextIsHorizontal) {
      result.add(points[i]);
    }
    previousIsHorizontal = nextIsHorizontal;
  }
  result.add(points.last);
  return result;
}

/// Final cleanup for routed paths: orthogonalize, prune, and clamp.
List<DrawPoint> _finalizeRoutedPath({
  required List<DrawPoint> points,
  required ElbowHeading startHeading,
  required List<DrawRect> obstacles,
}) {
  // Step 5: enforce orthogonality, remove tiny segments, and clamp.
  final orthogonalized = _ensureOrthogonalPath(
    points: points,
    startHeading: startHeading,
  );
  final backtrackCollapsed = _collapseRouteBacktracks(
    points: orthogonalized,
    obstacles: obstacles,
  );
  final cleaned = _getCornerPoints(_removeShortSegments(backtrackCollapsed));
  return cleaned.map(_clampPoint).toList(growable: false);
}

// Collapse detours that return to the same axis when the straight segment is
// clear.
List<DrawPoint> _collapseRouteBacktracks({
  required List<DrawPoint> points,
  required List<DrawRect> obstacles,
}) {
  if (points.length < 3) {
    return points;
  }
  var updated = List<DrawPoint>.from(points);
  var changed = true;

  while (changed) {
    changed = false;
    for (var i = 0; i < updated.length - 2; i++) {
      if (i == 0) {
        continue;
      }
      for (var j = i + 2; j < updated.length; j++) {
        if (j == updated.length - 1) {
          continue;
        }
        final a = updated[i];
        final d = updated[j];
        final alignedX = (a.x - d.x).abs() <= ElbowConstants.dedupThreshold;
        final alignedY = (a.y - d.y).abs() <= ElbowConstants.dedupThreshold;
        if (!alignedX && !alignedY) {
          continue;
        }
        if (_segmentIntersectsAnyBounds(a, d, obstacles)) {
          continue;
        }
        var deviates = false;
        for (var k = i + 1; k < j; k++) {
          final candidate = updated[k];
          if (alignedX) {
            if ((candidate.x - a.x).abs() > ElbowConstants.dedupThreshold) {
              deviates = true;
              break;
            }
          } else {
            if ((candidate.y - a.y).abs() > ElbowConstants.dedupThreshold) {
              deviates = true;
              break;
            }
          }
        }
        if (!deviates) {
          continue;
        }
        updated = [...updated.sublist(0, i + 1), d, ...updated.sublist(j + 1)];
        changed = true;
        break;
      }
      if (changed) {
        break;
      }
    }
  }

  return updated;
}

ElbowHeading _headingBetween(DrawPoint from, DrawPoint to) =>
    ElbowGeometry.headingForVector(from.x - to.x, from.y - to.y);

ElbowHeading _segmentHeading(DrawPoint from, DrawPoint to) =>
    ElbowGeometry.headingForSegment(from, to);

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
    if (dx <= ElbowConstants.dedupThreshold ||
        dy <= ElbowConstants.dedupThreshold) {
      if (next != previous) {
        result.add(next);
      }
      continue;
    }

    final preferHorizontal = result.length > 1
        ? ElbowGeometry.isHorizontal(result[result.length - 2], previous)
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
