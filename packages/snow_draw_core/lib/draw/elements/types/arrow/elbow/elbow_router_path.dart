part of 'elbow_router.dart';

/// Path construction and cleanup for elbow routing.
///
/// Contains the direct-route checks, fallback routing, intersection tests,
/// and post-processing that guarantees orthogonal, stable point lists.

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
  final alignedX = (start.x - end.x).abs() <= ElbowConstants.dedupThreshold;
  final alignedY = (start.y - end.y).abs() <= ElbowConstants.dedupThreshold;
  if (!alignedX && !alignedY) {
    return null;
  }

  // Check heading compatibility with alignment.
  if (alignedX && alignedY) {
    return null;
  }
  if (alignedY) {
    if (!startHeading.isHorizontal || !endHeading.isHorizontal) {
      return null;
    }
  } else if (startHeading.isHorizontal || endHeading.isHorizontal) {
    return null;
  }

  // Ensure the direct segment respects endpoint heading constraints.
  final segmentHeading = ElbowGeometry.headingForSegment(start, end);
  if (startConstrained && segmentHeading != startHeading) {
    return null;
  }
  if (endConstrained && segmentHeading != endHeading.opposite) {
    return null;
  }

  if (_segmentIntersectsAnyBounds(start, end, obstacles)) {
    return null;
  }
  return [start, end];
}

bool _segmentIntersectsBounds(DrawPoint start, DrawPoint end, DrawRect bounds) {
  final innerBounds = DrawRect(
    minX: bounds.minX + ElbowConstants.intersectionEpsilon,
    minY: bounds.minY + ElbowConstants.intersectionEpsilon,
    maxX: bounds.maxX - ElbowConstants.intersectionEpsilon,
    maxY: bounds.maxY - ElbowConstants.intersectionEpsilon,
  );
  if (innerBounds.minX >= innerBounds.maxX ||
      innerBounds.minY >= innerBounds.maxY) {
    return false;
  }
  final dx = (start.x - end.x).abs();
  final dy = (start.y - end.y).abs();
  if (dx <= ElbowConstants.dedupThreshold) {
    final x = (start.x + end.x) / 2;
    if (x < innerBounds.minX || x > innerBounds.maxX) {
      return false;
    }
    return _overlapLength(
          math.min(start.y, end.y),
          math.max(start.y, end.y),
          innerBounds.minY,
          innerBounds.maxY,
        ) >
        ElbowConstants.intersectionEpsilon;
  }
  if (dy <= ElbowConstants.dedupThreshold) {
    final y = (start.y + end.y) / 2;
    if (y < innerBounds.minY || y > innerBounds.maxY) {
      return false;
    }
    return _overlapLength(
          math.min(start.x, end.x),
          math.max(start.x, end.x),
          innerBounds.minX,
          innerBounds.maxX,
        ) >
        ElbowConstants.intersectionEpsilon;
  }
  return math.max(start.x, end.x) >= innerBounds.minX &&
      math.min(start.x, end.x) <= innerBounds.maxX &&
      math.max(start.y, end.y) >= innerBounds.minY &&
      math.min(start.y, end.y) <= innerBounds.maxY;
}

double _overlapLength(double minA, double maxA, double minB, double maxB) =>
    math.min(maxA, maxB) - math.max(minA, minB);

List<DrawPoint> _fallbackPath({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowHeading startHeading,
  ElbowHeading? endHeading,
  bool startConstrained = false,
  bool endConstrained = false,
}) {
  final resolvedEndHeading = endHeading ?? startHeading.opposite;

  // Try constrained fallback first when either endpoint is bound.
  if (startConstrained || endConstrained) {
    final candidates = <List<DrawPoint>>[
      [start, end],
      ElbowGeometry.directElbowPath(start, end, preferHorizontal: true),
      ElbowGeometry.directElbowPath(start, end, preferHorizontal: false),
    ];
    for (final horizontal in const [true, false]) {
      final mid = _resolveFallbackMid(
        start: start,
        end: end,
        startHeading: startHeading,
        endHeading: resolvedEndHeading,
        startConstrained: startConstrained,
        endConstrained: endConstrained,
        horizontal: horizontal,
      );
      if (mid != null) {
        candidates.add(
          _buildElbowThroughMid(
            start: start,
            end: end,
            horizontal: horizontal,
            mid: mid,
          ),
        );
      }
    }

    List<DrawPoint>? best;
    var bestLength = double.infinity;
    for (final candidate in candidates) {
      final cleaned = ElbowGeometry.cornerPoints(
        ElbowGeometry.removeShortSegments(candidate),
      );
      if (cleaned.length < 2 || ElbowGeometry.hasDiagonalSegments(cleaned)) {
        continue;
      }
      if (startConstrained &&
          ElbowGeometry.headingForSegment(cleaned.first, cleaned[1]) !=
              startHeading) {
        continue;
      }
      if (endConstrained &&
          ElbowGeometry.headingForSegment(
                cleaned[cleaned.length - 2],
                cleaned.last,
              ) !=
              resolvedEndHeading.opposite) {
        continue;
      }
      final length = ElbowGeometry.pathLength(cleaned);
      if (length < bestLength) {
        bestLength = length;
        best = cleaned;
      }
    }
    if (best != null) {
      return best;
    }
  }

  // Unconstrained fallback.
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

  for (final (constrained, heading, value) in [
    (startConstrained, startHeading, horizontal ? start.x : start.y),
    (endConstrained, endHeading, horizontal ? end.x : end.y),
  ]) {
    if (!constrained || heading.isHorizontal != horizontal) {
      continue;
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
  if (min.isFinite && max.isFinite && min > max) {
    return null;
  }
  final candidate = horizontal ? (start.x + end.x) / 2 : (start.y + end.y) / 2;
  if (min.isFinite && candidate < min) {
    return min;
  }
  if (max.isFinite && candidate > max) {
    return max;
  }
  return candidate;
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
  final startBounds = start.elementBounds;
  final endBounds = end.elementBounds;
  if (!start.isBound ||
      !end.isBound ||
      startBounds == null ||
      endBounds == null) {
    return points;
  }

  final segments = [
    for (var i = 0; i < points.length - 1; i++)
      if (ElbowGeometry.manhattanDistance(points[i], points[i + 1]) >
          ElbowConstants.dedupThreshold)
        _RouteSegment(
          index: i,
          start: points[i],
          end: points[i + 1],
          heading: ElbowGeometry.headingForSegment(points[i], points[i + 1]),
        ),
  ];

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
  final resolvedSpacing = ElbowSpacing.resolveSharedSpacing(
    startSpacing: startSpacing,
    endSpacing: endSpacing,
    startHasArrowhead: start.hasArrowhead,
    endHasArrowhead: end.hasArrowhead,
  );
  if (resolvedSpacing == null) {
    return points;
  }

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
  if (first.heading.isHorizontal != last.heading.isHorizontal) {
    return points;
  }

  final h = first.heading.isHorizontal;
  final minSpacing = math.max(
    ElbowSpacing.minBindingSpacing(hasArrowhead: start.hasArrowhead),
    ElbowSpacing.minBindingSpacing(hasArrowhead: end.hasArrowhead),
  );

  // Compute limits along the perpendicular axis.
  final forward = h
      ? first.heading != ElbowHeading.left
      : first.heading != ElbowHeading.up;

  double boundsLimit(DrawRect b, {required bool forStart}) {
    if (h) {
      return forward == forStart ? b.maxX + minSpacing : b.minX - minSpacing;
    }
    return forward == forStart ? b.maxY + minSpacing : b.minY - minSpacing;
  }

  final startLimit = boundsLimit(startBounds, forStart: true);
  final endLimit = boundsLimit(endBounds, forStart: false);
  final startVal = h ? points.first.x : points.first.y;
  final endVal = h ? points.last.x : points.last.y;
  final lo = math.min(startLimit, endLimit);
  final hi = math.max(startLimit, endLimit);
  final balanced = ((startVal + endVal) / 2).clamp(lo, hi);

  final mid = segments[1];
  final updated = List<DrawPoint>.from(points);
  if (h) {
    updated[mid.index] = updated[mid.index].copyWith(x: balanced);
    updated[mid.index + 1] = updated[mid.index + 1].copyWith(x: balanced);
  } else {
    updated[mid.index] = updated[mid.index].copyWith(y: balanced);
    updated[mid.index + 1] = updated[mid.index + 1].copyWith(y: balanced);
  }
  return updated;
}

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
    for (var i = 1; i < updated.length - 2 && !changed; i++) {
      for (var j = i + 2; j < updated.length - 1; j++) {
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
          final delta = alignedX
              ? (updated[k].x - a.x).abs()
              : (updated[k].y - a.y).abs();
          if (delta > ElbowConstants.dedupThreshold) {
            deviates = true;
            break;
          }
        }
        if (deviates) {
          updated = [
            ...updated.sublist(0, i + 1),
            d,
            ...updated.sublist(j + 1),
          ];
          changed = true;
          break;
        }
      }
    }
  }
  return updated;
}

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
  final i = segment.index;
  if (i < 0 || i + 1 >= points.length) {
    return;
  }
  final isVerticalSegment =
      heading == ElbowHeading.up || heading == ElbowHeading.down;
  final value = switch (heading) {
    ElbowHeading.up => bounds.minY - spacing,
    ElbowHeading.right => bounds.maxX + spacing,
    ElbowHeading.down => bounds.maxY + spacing,
    ElbowHeading.left => bounds.minX - spacing,
  };
  if (isVerticalSegment) {
    points[i] = points[i].copyWith(y: value);
    points[i + 1] = points[i + 1].copyWith(y: value);
  } else {
    points[i] = points[i].copyWith(x: value);
    points[i + 1] = points[i + 1].copyWith(x: value);
  }
}

List<DrawPoint> _ensureOrthogonalPath({
  required List<DrawPoint> points,
  required ElbowHeading startHeading,
}) {
  if (points.length < 2) {
    return points;
  }
  final result = <DrawPoint>[points.first];
  for (var i = 1; i < points.length; i++) {
    final prev = result.last;
    final next = points[i];
    final dx = (next.x - prev.x).abs();
    final dy = (next.y - prev.y).abs();
    if (dx <= ElbowConstants.dedupThreshold ||
        dy <= ElbowConstants.dedupThreshold) {
      if (next != prev) {
        result.add(next);
      }
      continue;
    }
    final preferH = result.length > 1
        ? ElbowGeometry.segmentIsHorizontal(result[result.length - 2], prev)
        : startHeading.isHorizontal;
    final mid = preferH
        ? DrawPoint(x: next.x, y: prev.y)
        : DrawPoint(x: prev.x, y: next.y);
    if (mid != prev) {
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

typedef _ElbowGridAddress = ({int col, int row});

void _addBoundsToAxes(Set<double> xs, Set<double> ys, DrawRect bounds) {
  xs
    ..add(bounds.minX)
    ..add(bounds.maxX);
  ys
    ..add(bounds.minY)
    ..add(bounds.maxY);
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
  final xs = <double>{start.x, end.x, bounds.minX, bounds.maxX};
  final ys = <double>{start.y, end.y, bounds.minY, bounds.maxY};
  for (final o in obstacles) {
    _addBoundsToAxes(xs, ys, o);
  }

  final sortedX = xs.toList()..sort();
  final sortedY = ys.toList()..sort();
  final xIndex = _buildAxisIndex(sortedX);
  final yIndex = _buildAxisIndex(sortedY);

  final nodes = [
    for (var row = 0; row < sortedY.length; row++)
      for (var col = 0; col < sortedX.length; col++)
        _ElbowGridNode(
          pos: DrawPoint(x: sortedX[col], y: sortedY[row]),
          addr: (col: col, row: row),
        ),
  ];

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
          : ElbowGeometry.headingForSegment(current.parent!.pos, current.pos);
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
  for (var node = current; ;) {
    reversed.add(node);
    final parent = node.parent;
    if (parent == null) {
      break;
    }
    node = parent;
  }
  final path = reversed.reversed.toList(growable: true);
  if (path.first.addr != start.addr) {
    path.insert(0, start);
  }
  return path;
}

typedef _ElbowNeighborOffset = ({int dx, int dy, ElbowHeading heading});

const _neighborOffsets = <_ElbowNeighborOffset>[
  (dx: 0, dy: -1, heading: ElbowHeading.up),
  (dx: 1, dy: 0, heading: ElbowHeading.right),
  (dx: 0, dy: 1, heading: ElbowHeading.down),
  (dx: -1, dy: 0, heading: ElbowHeading.left),
];
