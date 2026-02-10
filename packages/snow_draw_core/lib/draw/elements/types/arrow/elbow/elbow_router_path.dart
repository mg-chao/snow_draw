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
  if (!alignment.isAligned) {
    return true;
  }
  if (alignment.alignedX && alignment.alignedY) {
    return false;
  }
  if (alignment.alignedY) {
    return startHeading.isHorizontal && endHeading.isHorizontal;
  }
  return !startHeading.isHorizontal && !endHeading.isHorizontal;
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
  // Diagonal segments use a conservative AABB overlap check.
  return _segmentAabbIntersectsBounds(start, end, innerBounds);
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

bool _segmentAabbIntersectsBounds(
  DrawPoint start,
  DrawPoint end,
  DrawRect bounds,
) {
  final segMinX = math.min(start.x, end.x);
  final segMaxX = math.max(start.x, end.x);
  final segMinY = math.min(start.y, end.y);
  final segMaxY = math.max(start.y, end.y);
  return segMaxX >= bounds.minX &&
      segMinX <= bounds.maxX &&
      segMaxY >= bounds.minY &&
      segMinY <= bounds.maxY;
}

List<DrawPoint> _fallbackPath({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowHeading startHeading,
  ElbowHeading? endHeading,
  bool startConstrained = false,
  bool endConstrained = false,
}) {
  final resolvedEndHeading = endHeading ?? startHeading.opposite;
  if (startConstrained || endConstrained) {
    final constrained = _fallbackPathConstrained(
      start: start,
      end: end,
      startHeading: startHeading,
      endHeading: resolvedEndHeading,
      startConstrained: startConstrained,
      endConstrained: endConstrained,
    );
    if (constrained != null) {
      return constrained;
    }
  }

  return _fallbackPathUnconstrained(
    start: start,
    end: end,
    startHeading: startHeading,
  );
}

List<DrawPoint> _buildElbowThroughMid({
  required DrawPoint start,
  required DrawPoint end,
  required bool horizontal,
  required double mid,
}) {
  if (horizontal) {
    return [
      start,
      DrawPoint(x: mid, y: start.y),
      DrawPoint(x: mid, y: end.y),
      end,
    ];
  }
  return [
    start,
    DrawPoint(x: start.x, y: mid),
    DrawPoint(x: end.x, y: mid),
    end,
  ];
}

List<DrawPoint> _fallbackPathUnconstrained({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowHeading startHeading,
}) {
  if (ElbowGeometry.manhattanDistance(start, end) <
      ElbowConstants.minArrowLength) {
    final midY = (start.y + end.y) / 2;
    return _buildElbowThroughMid(
      start: start,
      end: end,
      horizontal: false,
      mid: midY,
    );
  }

  if ((start.x - end.x).abs() <= ElbowConstants.dedupThreshold ||
      (start.y - end.y).abs() <= ElbowConstants.dedupThreshold) {
    return [start, end];
  }

  final horizontal = startHeading.isHorizontal;
  final mid = horizontal ? (start.x + end.x) / 2 : (start.y + end.y) / 2;
  return _buildElbowThroughMid(
    start: start,
    end: end,
    horizontal: horizontal,
    mid: mid,
  );
}

List<DrawPoint>? _fallbackPathConstrained({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required bool startConstrained,
  required bool endConstrained,
}) {
  final candidates = _generateFallbackCandidates(
    start: start,
    end: end,
    startHeading: startHeading,
    endHeading: endHeading,
    startConstrained: startConstrained,
    endConstrained: endConstrained,
  );

  return _selectBestCandidate(
    candidates: candidates,
    startHeading: startHeading,
    endHeading: endHeading,
    startConstrained: startConstrained,
    endConstrained: endConstrained,
  );
}

List<List<DrawPoint>> _generateFallbackCandidates({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required bool startConstrained,
  required bool endConstrained,
}) {
  final candidates = <List<DrawPoint>>[
    [start, end],
    ElbowPathUtils.directElbowPath(start, end, preferHorizontal: true),
    ElbowPathUtils.directElbowPath(start, end, preferHorizontal: false),
  ];

  void addMidCandidate({required bool horizontal}) {
    final mid = _resolveFallbackMid(
      start: start,
      end: end,
      startHeading: startHeading,
      endHeading: endHeading,
      startConstrained: startConstrained,
      endConstrained: endConstrained,
      horizontal: horizontal,
    );
    if (mid == null) {
      return;
    }
    candidates.add(
      _buildElbowThroughMid(
        start: start,
        end: end,
        horizontal: horizontal,
        mid: mid,
      ),
    );
  }

  addMidCandidate(horizontal: true);
  addMidCandidate(horizontal: false);

  return candidates;
}

List<DrawPoint>? _selectBestCandidate({
  required List<List<DrawPoint>> candidates,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required bool startConstrained,
  required bool endConstrained,
}) {
  List<DrawPoint>? best;
  var bestLength = double.infinity;

  for (final candidate in candidates) {
    final normalized = _normalizeFallbackCandidate(
      points: candidate,
      startHeading: startHeading,
      endHeading: endHeading,
      startConstrained: startConstrained,
      endConstrained: endConstrained,
    );
    if (normalized == null) {
      continue;
    }
    final length = _pathLength(normalized);
    if (length < bestLength) {
      bestLength = length;
      best = normalized;
    }
  }
  return best;
}

/// Resolves a constrained midpoint along a single axis.
///
/// When [horizontal] is true, constrains along X using horizontal headings;
/// otherwise constrains along Y using vertical headings.
double? _resolveFallbackMid({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required bool startConstrained,
  required bool endConstrained,
  required bool horizontal,
}) {
  const padding = ElbowConstants.directionFixPadding;
  var min = double.negativeInfinity;
  var max = double.infinity;

  void applyConstraint({
    required bool constrained,
    required ElbowHeading heading,
    required double value,
  }) {
    if (!constrained || heading.isHorizontal != horizontal) {
      return;
    }
    final positive = horizontal
        ? heading == ElbowHeading.right
        : heading == ElbowHeading.down;
    if (positive) {
      min = math.max(min, value + padding);
    } else {
      max = math.min(max, value - padding);
    }
  }

  applyConstraint(
    constrained: startConstrained,
    heading: startHeading,
    value: horizontal ? start.x : start.y,
  );
  applyConstraint(
    constrained: endConstrained,
    heading: endHeading,
    value: horizontal ? end.x : end.y,
  );

  if (min.isFinite && max.isFinite && min > max) {
    return null;
  }

  final candidate = horizontal ? (start.x + end.x) / 2 : (start.y + end.y) / 2;
  return _clampToRange(candidate, min, max);
}

double _clampToRange(double value, double min, double max) {
  if (min.isFinite && value < min) {
    return min;
  }
  if (max.isFinite && value > max) {
    return max;
  }
  return value;
}

List<DrawPoint>? _normalizeFallbackCandidate({
  required List<DrawPoint> points,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required bool startConstrained,
  required bool endConstrained,
}) {
  final cleaned = ElbowPathUtils.cornerPoints(
    ElbowPathUtils.removeShortSegments(points),
  );
  if (cleaned.length < 2) {
    return null;
  }
  if (ElbowPathUtils.hasDiagonalSegments(cleaned)) {
    return null;
  }
  if (startConstrained &&
      _segmentHeading(cleaned.first, cleaned[1]) != startHeading) {
    return null;
  }
  if (endConstrained &&
      _segmentHeading(cleaned[cleaned.length - 2], cleaned.last) !=
          endHeading.opposite) {
    return null;
  }
  return cleaned;
}

double _pathLength(List<DrawPoint> points) {
  var length = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    length += ElbowGeometry.manhattanDistance(points[i], points[i + 1]);
  }
  return length;
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
  final cleaned = ElbowPathUtils.cornerPoints(
    ElbowPathUtils.removeShortSegments(backtrackCollapsed),
  );
  return cleaned.map(_clampPoint).toList(growable: false);
}

List<DrawPoint> _harmonizeBoundSpacing({
  required List<DrawPoint> points,
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
}) {
  if (!start.isBound || !end.isBound) {
    return points;
  }
  final startBounds = start.elementBounds;
  final endBounds = end.elementBounds;
  if (startBounds == null || endBounds == null) {
    return points;
  }

  final segments = _routeSegments(points);
  if (segments.length < 4) {
    return points;
  }

  final startSegment = segments[1];
  final endSegment = segments[segments.length - 2];
  if (startSegment.heading.isHorizontal == start.heading.isHorizontal ||
      endSegment.heading.isHorizontal == end.heading.isHorizontal) {
    return points;
  }

  final startSpacing = _segmentSpacing(
    segment: startSegment,
    bounds: startBounds,
    heading: start.heading,
  );
  final endSpacing = _segmentSpacing(
    segment: endSegment,
    bounds: endBounds,
    heading: end.heading,
  );
  if (startSpacing == null || endSpacing == null) {
    return points;
  }

  final sharedSpacing = math.min(startSpacing, endSpacing);
  if (!sharedSpacing.isFinite) {
    return points;
  }

  final minAllowedSpacing = math.max(
    _minBindingSpacing(hasArrowhead: start.hasArrowhead),
    _minBindingSpacing(hasArrowhead: end.hasArrowhead),
  );
  final resolvedSpacing = math.max(sharedSpacing, minAllowedSpacing);

  final updated = List<DrawPoint>.from(points);
  _applySegmentSpacing(
    points: updated,
    segment: startSegment,
    bounds: startBounds,
    heading: start.heading,
    spacing: resolvedSpacing,
  );
  _applySegmentSpacing(
    points: updated,
    segment: endSegment,
    bounds: endBounds,
    heading: end.heading,
    spacing: resolvedSpacing,
  );
  return updated;
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
    final collapsed = _tryCollapseOneBacktrack(updated, obstacles);
    if (collapsed != null) {
      updated = collapsed;
      changed = true;
    }
  }

  return updated;
}

List<DrawPoint>? _tryCollapseOneBacktrack(
  List<DrawPoint> points,
  List<DrawRect> obstacles,
) {
  for (var i = 1; i < points.length - 2; i++) {
    for (var j = i + 2; j < points.length - 1; j++) {
      final a = points[i];
      final d = points[j];
      final alignedX = (a.x - d.x).abs() <= ElbowConstants.dedupThreshold;
      final alignedY = (a.y - d.y).abs() <= ElbowConstants.dedupThreshold;

      if (!alignedX && !alignedY) {
        continue;
      }
      if (_segmentIntersectsAnyBounds(a, d, obstacles)) {
        continue;
      }

      final deviates = _pathDeviatesFromAxis(
        points: points,
        start: i,
        end: j,
        alignedX: alignedX,
        reference: a,
      );

      if (deviates) {
        return [...points.sublist(0, i + 1), d, ...points.sublist(j + 1)];
      }
    }
  }
  return null;
}

bool _pathDeviatesFromAxis({
  required List<DrawPoint> points,
  required int start,
  required int end,
  required bool alignedX,
  required DrawPoint reference,
}) {
  for (var k = start + 1; k < end; k++) {
    final candidate = points[k];
    if (alignedX) {
      if ((candidate.x - reference.x).abs() > ElbowConstants.dedupThreshold) {
        return true;
      }
    } else {
      if ((candidate.y - reference.y).abs() > ElbowConstants.dedupThreshold) {
        return true;
      }
    }
  }
  return false;
}

ElbowHeading _headingFromTo(DrawPoint from, DrawPoint to) =>
    ElbowGeometry.headingForVector(to.x - from.x, to.y - from.y);

ElbowHeading _segmentHeading(DrawPoint from, DrawPoint to) =>
    ElbowGeometry.headingForSegment(from, to);

bool _segmentIntersectsAnyBounds(
  DrawPoint start,
  DrawPoint end,
  List<DrawRect> obstacles,
) =>
    obstacles.any((obstacle) => _segmentIntersectsBounds(start, end, obstacle));

@immutable
final class _RouteSegment {
  const _RouteSegment({
    required this.index,
    required this.start,
    required this.end,
    required this.heading,
  });

  final int index;
  final DrawPoint start;
  final DrawPoint end;
  final ElbowHeading heading;

  double get midX => (start.x + end.x) / 2;
  double get midY => (start.y + end.y) / 2;
}

List<_RouteSegment> _routeSegments(List<DrawPoint> points) {
  if (points.length < 2) {
    return const <_RouteSegment>[];
  }
  final segments = <_RouteSegment>[];
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    if (ElbowGeometry.manhattanDistance(start, end) <=
        ElbowConstants.dedupThreshold) {
      continue;
    }
    segments.add(
      _RouteSegment(
        index: i,
        start: start,
        end: end,
        heading: ElbowGeometry.headingForSegment(start, end),
      ),
    );
  }
  return segments;
}

double? _segmentSpacing({
  required _RouteSegment segment,
  required DrawRect bounds,
  required ElbowHeading heading,
}) {
  final spacing = switch (heading) {
    ElbowHeading.up => bounds.minY - segment.midY,
    ElbowHeading.right => segment.midX - bounds.maxX,
    ElbowHeading.down => segment.midY - bounds.maxY,
    ElbowHeading.left => bounds.minX - segment.midX,
  };
  if (!spacing.isFinite || spacing <= ElbowConstants.intersectionEpsilon) {
    return null;
  }
  return spacing;
}

void _applySegmentSpacing({
  required List<DrawPoint> points,
  required _RouteSegment segment,
  required DrawRect bounds,
  required ElbowHeading heading,
  required double spacing,
}) {
  final index = segment.index;
  if (index < 0 || index + 1 >= points.length) {
    return;
  }
  switch (heading) {
    case ElbowHeading.up:
      final y = bounds.minY - spacing;
      points[index] = points[index].copyWith(y: y);
      points[index + 1] = points[index + 1].copyWith(y: y);
    case ElbowHeading.right:
      final x = bounds.maxX + spacing;
      points[index] = points[index].copyWith(x: x);
      points[index + 1] = points[index + 1].copyWith(x: x);
    case ElbowHeading.down:
      final y = bounds.maxY + spacing;
      points[index] = points[index].copyWith(y: y);
      points[index + 1] = points[index + 1].copyWith(y: y);
    case ElbowHeading.left:
      final x = bounds.minX - spacing;
      points[index] = points[index].copyWith(x: x);
      points[index + 1] = points[index + 1].copyWith(x: x);
  }
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
        ? ElbowPathUtils.segmentIsHorizontal(
            result[result.length - 2],
            previous,
          )
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
