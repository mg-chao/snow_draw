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
    ElbowGeometry.directElbowPath(start, end, preferHorizontal: true),
    ElbowGeometry.directElbowPath(start, end, preferHorizontal: false),
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
    final length = ElbowGeometry.pathLength(normalized);
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
  final cleaned = ElbowGeometry.cornerPoints(
    ElbowGeometry.removeShortSegments(points),
  );
  if (cleaned.length < 2) {
    return null;
  }
  if (ElbowGeometry.hasDiagonalSegments(cleaned)) {
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
  final cleaned = ElbowGeometry.cornerPoints(
    ElbowGeometry.removeShortSegments(backtrackCollapsed),
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

  // Balance a 3-segment path whose first and last segments share the same
  // axis (e.g. [right, down, right]).  Move the middle perpendicular segment
  // to the midpoint of the gap so the two parallel segments are even.
  if (segments.length == 3) {
    return _balanceThreeSegmentPath(
      points: points,
      segments: segments,
      start: start,
      end: end,
      startBounds: startBounds,
      endBounds: endBounds,
    );
  }

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
    ElbowSpacing.minBindingSpacing(hasArrowhead: start.hasArrowhead),
    ElbowSpacing.minBindingSpacing(hasArrowhead: end.hasArrowhead),
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

/// Balances a 3-segment path where the first and last segments share the
/// same axis by centering the middle perpendicular segment in the gap.
List<DrawPoint> _balanceThreeSegmentPath({
  required List<DrawPoint> points,
  required List<_RouteSegment> segments,
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
  required DrawRect startBounds,
  required DrawRect endBounds,
}) {
  final first = segments.first;
  final last = segments.last;

  // Only applies when the outer segments share the same axis.
  if (first.heading.isHorizontal != last.heading.isHorizontal) {
    return points;
  }

  final horizontal = first.heading.isHorizontal;

  // Compute the allowed range for the middle segment along the parallel
  // axis.  The middle segment must stay outside both element bounds.
  final minSpacing = math.max(
    ElbowSpacing.minBindingSpacing(hasArrowhead: start.hasArrowhead),
    ElbowSpacing.minBindingSpacing(hasArrowhead: end.hasArrowhead),
  );

  double startLimit;
  double endLimit;
  if (horizontal) {
    // Middle segment is vertical; its x position must respect both bounds.
    startLimit = startBounds.maxX + minSpacing;
    endLimit = endBounds.minX - minSpacing;
    if (first.heading == ElbowHeading.left) {
      startLimit = startBounds.minX - minSpacing;
      endLimit = endBounds.maxX + minSpacing;
    }
  } else {
    // Middle segment is horizontal; its y position must respect both bounds.
    startLimit = startBounds.maxY + minSpacing;
    endLimit = endBounds.minY - minSpacing;
    if (first.heading == ElbowHeading.up) {
      startLimit = startBounds.minY - minSpacing;
      endLimit = endBounds.maxY + minSpacing;
    }
  }

  // The ideal position is the midpoint between the two endpoints along the
  // parallel axis.
  final startVal = horizontal ? points.first.x : points.first.y;
  final endVal = horizontal ? points.last.x : points.last.y;
  final ideal = (startVal + endVal) / 2;

  // Clamp to the allowed range.
  final lo = math.min(startLimit, endLimit);
  final hi = math.max(startLimit, endLimit);
  final balanced = ideal.clamp(lo, hi);

  // The middle segment spans points[1] and points[2] in a 4-point path.
  final mid = segments[1];
  final updated = List<DrawPoint>.from(points);
  if (horizontal) {
    updated[mid.index] = updated[mid.index].copyWith(x: balanced);
    updated[mid.index + 1] = updated[mid.index + 1].copyWith(x: balanced);
  } else {
    updated[mid.index] = updated[mid.index].copyWith(y: balanced);
    updated[mid.index + 1] = updated[mid.index + 1].copyWith(y: balanced);
  }
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
  final horizontal = heading == ElbowHeading.up || heading == ElbowHeading.down;
  final value = switch (heading) {
    ElbowHeading.up => bounds.minY - spacing,
    ElbowHeading.right => bounds.maxX + spacing,
    ElbowHeading.down => bounds.maxY + spacing,
    ElbowHeading.left => bounds.minX - spacing,
  };
  if (horizontal) {
    points[index] = points[index].copyWith(y: value);
    points[index + 1] = points[index + 1].copyWith(y: value);
  } else {
    points[index] = points[index].copyWith(x: value);
    points[index + 1] = points[index + 1].copyWith(x: value);
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
        ? ElbowGeometry.segmentIsHorizontal(result[result.length - 2], previous)
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

// ---------------------------------------------------------------------------
// Sparse grid routing (merged from elbow_router_grid.dart)
// ---------------------------------------------------------------------------

/// Forces grid routing to fail so fallback paths can be exercised in tests.
@visibleForTesting
var elbowForceGridFailure = false;

@immutable
final class _ElbowGrid {
  const _ElbowGrid({
    required this.rows,
    required this.cols,
    required this.nodes,
    required this.xIndex,
    required this.yIndex,
  });

  final int rows;
  final int cols;
  final List<_ElbowGridNode> nodes;
  final Map<double, int> xIndex;
  final Map<double, int> yIndex;

  _ElbowGridNode? nodeAt(int col, int row) {
    if (col < 0 || row < 0 || col >= cols || row >= rows) {
      return null;
    }
    return nodes[row * cols + col];
  }

  _ElbowGridNode? nodeForPoint(DrawPoint point) {
    final col = xIndex[point.x];
    final row = yIndex[point.y];
    if (col == null || row == null) {
      return null;
    }
    return nodeAt(col, row);
  }
}

final class _ElbowGridNode {
  _ElbowGridNode({required this.pos, required this.addr});

  final DrawPoint pos;
  final _ElbowGridAddress addr;
  double f = 0;
  double g = 0;
  double h = 0;
  var closed = false;
  var visited = false;
  _ElbowGridNode? parent;
}

@immutable
final class _ElbowGridAddress {
  const _ElbowGridAddress({required this.col, required this.row});

  final int col;
  final int row;
}

void _addBoundsToAxes(Set<double> xs, Set<double> ys, DrawRect bounds) {
  xs
    ..add(bounds.minX)
    ..add(bounds.maxX);
  ys
    ..add(bounds.minY)
    ..add(bounds.maxY);
}

void _addPointToAxes(Set<double> xs, Set<double> ys, DrawPoint point) {
  xs.add(point.x);
  ys.add(point.y);
}

Map<double, int> _buildAxisIndex(List<double> sortedAxis) => <double, int>{
  for (var i = 0; i < sortedAxis.length; i++) sortedAxis[i]: i,
};

_ElbowGrid _buildGrid({
  required List<DrawRect> obstacles,
  required DrawPoint start,
  required ElbowHeading startHeading,
  required DrawPoint end,
  required ElbowHeading endHeading,
  required DrawRect bounds,
}) {
  final xs = <double>{};
  final ys = <double>{};

  for (final obstacle in obstacles) {
    _addBoundsToAxes(xs, ys, obstacle);
  }

  _addPointToAxes(xs, ys, start);
  _addPointToAxes(xs, ys, end);

  _addBoundsToAxes(xs, ys, bounds);

  if (startHeading.isHorizontal) {
    ys.add(start.y);
  } else {
    xs.add(start.x);
  }
  if (endHeading.isHorizontal) {
    ys.add(end.y);
  } else {
    xs.add(end.x);
  }

  final sortedX = xs.toList()..sort();
  final sortedY = ys.toList()..sort();
  final xIndex = _buildAxisIndex(sortedX);
  final yIndex = _buildAxisIndex(sortedY);

  final nodes = <_ElbowGridNode>[];
  for (var row = 0; row < sortedY.length; row++) {
    for (var col = 0; col < sortedX.length; col++) {
      nodes.add(
        _ElbowGridNode(
          pos: DrawPoint(x: sortedX[col], y: sortedY[row]),
          addr: _ElbowGridAddress(col: col, row: row),
        ),
      );
    }
  }

  return _ElbowGrid(
    rows: sortedY.length,
    cols: sortedX.length,
    nodes: nodes,
    xIndex: xIndex,
    yIndex: yIndex,
  );
}

@immutable
final class _BendPenalty {
  const _BendPenalty(double base)
    : squared = base * base,
      cubed = base * base * base;

  final double squared;
  final double cubed;
}

/// A* router that walks the sparse elbow grid with bend penalties.
@immutable
final class _ElbowGridRouter {
  const _ElbowGridRouter({
    required this.grid,
    required this.start,
    required this.end,
    required this.startHeading,
    required this.endHeading,
    required this.startConstrained,
    required this.endConstrained,
    required this.obstacles,
  });

  final _ElbowGrid grid;
  final _ElbowGridNode start;
  final _ElbowGridNode end;
  final ElbowHeading startHeading;
  final ElbowHeading endHeading;
  final bool startConstrained;
  final bool endConstrained;
  final List<DrawRect> obstacles;

  List<_ElbowGridNode> findPath() {
    final openSet = BinaryHeap<_ElbowGridNode>((node) => node.f)..push(start);

    final bendPenalty = _BendPenalty(
      ElbowGeometry.manhattanDistance(start.pos, end.pos),
    );
    final startHeadingFlip = startHeading.opposite;
    final endHeadingFlip = endHeading.opposite;

    while (openSet.isNotEmpty) {
      final current = openSet.pop();
      if (current == null || current.closed) {
        continue;
      }
      if (current.addr == end.addr) {
        return _reconstructPath(current, start);
      }

      current.closed = true;

      final previousHeading = current.parent == null
          ? startHeading
          : _segmentHeading(current.parent!.pos, current.pos);
      final isStartNode = current.addr == start.addr;

      for (final offset in _neighborOffsets) {
        final next = grid.nodeAt(
          current.addr.col + offset.dx,
          current.addr.row + offset.dy,
        );
        if (next == null || next.closed) {
          continue;
        }

        if (!_canTraverseNeighbor(
          current: current,
          next: next,
          isStartNode: isStartNode,
          endAddress: end.addr,
          previousHeading: previousHeading,
          neighborHeading: offset.heading,
          startHeadingFlip: startHeadingFlip,
          endHeadingFlip: endHeadingFlip,
        )) {
          continue;
        }

        final directionChanged = offset.heading != previousHeading;
        final moveCost = ElbowGeometry.manhattanDistance(current.pos, next.pos);
        final bendCost = directionChanged ? bendPenalty.cubed : 0;
        final gScore = current.g + moveCost + bendCost;

        if (!next.visited || gScore < next.g) {
          final hScore = _heuristicScore(
            from: next.pos,
            to: end.pos,
            fromHeading: offset.heading,
            endHeading: endHeadingFlip,
            bendPenaltySquared: bendPenalty.squared,
          );
          next
            ..parent = current
            ..g = gScore
            ..h = hScore
            ..f = gScore + hScore;
          if (!next.visited) {
            next.visited = true;
            openSet.push(next);
          } else {
            openSet.rescore(next);
          }
        }
      }
    }

    return const <_ElbowGridNode>[];
  }

  bool _canTraverseNeighbor({
    required _ElbowGridNode current,
    required _ElbowGridNode next,
    required bool isStartNode,
    required _ElbowGridAddress endAddress,
    required ElbowHeading previousHeading,
    required ElbowHeading neighborHeading,
    required ElbowHeading startHeadingFlip,
    required ElbowHeading endHeadingFlip,
  }) {
    if (_segmentIntersectsAnyBounds(current.pos, next.pos, obstacles)) {
      return false;
    }

    if (neighborHeading == previousHeading.opposite) {
      return false;
    }

    if (isStartNode &&
        !_allowsHeadingFromStart(
          constrained: startConstrained,
          neighborHeading: neighborHeading,
          startHeading: startHeading,
          startHeadingFlip: startHeadingFlip,
        )) {
      return false;
    }

    if (next.addr == endAddress &&
        !_allowsHeadingIntoEnd(
          constrained: endConstrained,
          neighborHeading: neighborHeading,
          endHeadingFlip: endHeadingFlip,
        )) {
      return false;
    }

    return true;
  }

  double _heuristicScore({
    required DrawPoint from,
    required DrawPoint to,
    required ElbowHeading fromHeading,
    required ElbowHeading endHeading,
    required double bendPenaltySquared,
  }) =>
      ElbowGeometry.manhattanDistance(from, to) +
      _estimatedBendPenalty(
        start: from,
        end: to,
        startHeading: fromHeading,
        endHeading: endHeading,
        bendPenaltySquared: bendPenaltySquared,
      );
}

double _estimatedBendPenalty({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required double bendPenaltySquared,
}) {
  final sameAxis = startHeading.isHorizontal == endHeading.isHorizontal;
  if (!sameAxis) {
    return bendPenaltySquared;
  }

  final alignedOnAxis = startHeading.isHorizontal
      ? (start.y - end.y).abs() <= ElbowConstants.dedupThreshold
      : (start.x - end.x).abs() <= ElbowConstants.dedupThreshold;
  return alignedOnAxis ? 0 : bendPenaltySquared;
}

List<_ElbowGridNode>? _tryRouteGridPath({
  required _ElbowGrid grid,
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
  required DrawPoint startExit,
  required DrawPoint endExit,
  required List<DrawRect> obstacles,
}) {
  if (elbowForceGridFailure) {
    return null;
  }
  final startNode = grid.nodeForPoint(startExit);
  final endNode = grid.nodeForPoint(endExit);
  if (startNode == null || endNode == null) {
    return null;
  }

  final path = _ElbowGridRouter(
    grid: grid,
    start: startNode,
    end: endNode,
    startHeading: start.heading,
    endHeading: end.heading,
    startConstrained: start.isBound,
    endConstrained: end.isBound,
    obstacles: obstacles,
  ).findPath();
  if (path.isEmpty) {
    return null;
  }
  return path;
}

bool _allowsHeadingFromStart({
  required bool constrained,
  required ElbowHeading neighborHeading,
  required ElbowHeading startHeading,
  required ElbowHeading startHeadingFlip,
}) {
  if (constrained) {
    return neighborHeading == startHeading;
  }
  return neighborHeading != startHeadingFlip;
}

bool _allowsHeadingIntoEnd({
  required bool constrained,
  required ElbowHeading neighborHeading,
  required ElbowHeading endHeadingFlip,
}) {
  if (constrained) {
    return neighborHeading == endHeadingFlip;
  }
  return true;
}

List<_ElbowGridNode> _reconstructPath(
  _ElbowGridNode current,
  _ElbowGridNode start,
) {
  final reversed = <_ElbowGridNode>[];
  var node = current;
  while (true) {
    reversed.add(node);
    final parent = node.parent;
    if (parent == null) {
      break;
    }
    node = parent;
  }
  if (reversed.isEmpty) {
    return [start];
  }
  final path = reversed.reversed.toList(growable: true);
  if (path.first.addr != start.addr) {
    path.insert(0, start);
  }
  return path;
}

@immutable
final class _ElbowNeighborOffset {
  const _ElbowNeighborOffset(this.dx, this.dy, this.heading);

  final int dx;
  final int dy;
  final ElbowHeading heading;
}

const _neighborOffsets = <_ElbowNeighborOffset>[
  _ElbowNeighborOffset(0, -1, ElbowHeading.up),
  _ElbowNeighborOffset(1, 0, ElbowHeading.right),
  _ElbowNeighborOffset(0, 1, ElbowHeading.down),
  _ElbowNeighborOffset(-1, 0, ElbowHeading.left),
];
