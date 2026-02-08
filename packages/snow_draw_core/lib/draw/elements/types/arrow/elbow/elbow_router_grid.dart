part of 'elbow_router.dart';

/// Sparse grid routing (A* with bend penalties) for elbow paths.

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
  // Build a sparse grid from obstacle edges + endpoints for A* routing.
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
    // A* with bend penalties to discourage unnecessary elbows.
    final openSet = _BinaryHeap<_ElbowGridNode>((node) => node.f)..push(start);

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
          : _headingFromTo(current.parent!.pos, current.pos);
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

class _BinaryHeap<T> {
  _BinaryHeap(double Function(T) score)
    : _score = ((value) => score(value as T));

  final double Function(Object?) _score;
  final List<T> _content = [];

  bool get isNotEmpty => _content.isNotEmpty;

  void push(T element) {
    _content.add(element);
    _sinkDown(_content.length - 1);
  }

  T? pop() {
    if (_content.isEmpty) {
      return null;
    }
    final result = _content.first;
    final end = _content.removeLast();
    if (_content.isNotEmpty) {
      _content[0] = end;
      _bubbleUp(0);
    }
    return result;
  }

  bool contains(T element) => _content.contains(element);

  void rescore(T element) {
    final index = _content.indexOf(element);
    if (index >= 0) {
      _sinkDown(index);
    }
  }

  void _sinkDown(int n) {
    final element = _content[n];
    final elementScore = _score(element);
    while (n > 0) {
      final parentN = ((n + 1) >> 1) - 1;
      final parent = _content[parentN];
      if (elementScore < _score(parent)) {
        _content[parentN] = element;
        _content[n] = parent;
        n = parentN;
      } else {
        break;
      }
    }
  }

  void _bubbleUp(int n) {
    final length = _content.length;
    final element = _content[n];
    final elemScore = _score(element);

    while (true) {
      final child2N = (n + 1) << 1;
      final child1N = child2N - 1;
      int? swap;
      var child1Score = 0.0;

      if (child1N < length) {
        final child1 = _content[child1N];
        child1Score = _score(child1);
        if (child1Score < elemScore) {
          swap = child1N;
        }
      }

      if (child2N < length) {
        final child2 = _content[child2N];
        final child2Score = _score(child2);
        if (child2Score < (swap == null ? elemScore : child1Score)) {
          swap = child2N;
        }
      }

      if (swap != null) {
        _content[n] = _content[swap];
        _content[swap] = element;
        n = swap;
      } else {
        break;
      }
    }
  }
}
