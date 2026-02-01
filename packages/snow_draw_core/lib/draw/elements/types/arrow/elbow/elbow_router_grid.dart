part of 'elbow_router.dart';

/// Sparse grid routing (A* with bend penalties) for elbow paths.

@immutable
class _Grid {
  const _Grid({
    required this.rows,
    required this.cols,
    required this.nodes,
    required this.xIndex,
    required this.yIndex,
  });

  final int rows;
  final int cols;
  final List<_GridNode> nodes;
  final Map<double, int> xIndex;
  final Map<double, int> yIndex;

  _GridNode? nodeAt(int col, int row) {
    if (col < 0 || row < 0 || col >= cols || row >= rows) {
      return null;
    }
    return nodes[row * cols + col];
  }

  _GridNode? nodeForPoint(DrawPoint point) {
    final col = xIndex[point.x];
    final row = yIndex[point.y];
    if (col == null || row == null) {
      return null;
    }
    return nodeAt(col, row);
  }
}

class _GridNode {
  _GridNode({required this.pos, required this.addr});

  final DrawPoint pos;
  final _GridAddress addr;
  double f = 0;
  double g = 0;
  double h = 0;
  var closed = false;
  var visited = false;
  _GridNode? parent;
}

@immutable
class _GridAddress {
  const _GridAddress({required this.col, required this.row});

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

_Grid _buildGrid({
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

  final nodes = <_GridNode>[];
  for (var row = 0; row < sortedY.length; row++) {
    for (var col = 0; col < sortedX.length; col++) {
      nodes.add(
        _GridNode(
          pos: DrawPoint(x: sortedX[col], y: sortedY[row]),
          addr: _GridAddress(col: col, row: row),
        ),
      );
    }
  }

  return _Grid(
    rows: sortedY.length,
    cols: sortedX.length,
    nodes: nodes,
    xIndex: xIndex,
    yIndex: yIndex,
  );
}

@immutable
class _BendPenalty {
  const _BendPenalty(double base)
    : squared = base * base,
      cubed = base * base * base;

  final double squared;
  final double cubed;
}

bool _canTraverseNeighbor({
  required _GridNode current,
  required _GridNode next,
  required bool isStartNode,
  required _GridAddress endAddress,
  required ElbowHeading previousHeading,
  required ElbowHeading neighborHeading,
  required bool startConstrained,
  required bool endConstrained,
  required ElbowHeading startHeading,
  required ElbowHeading startHeadingFlip,
  required ElbowHeading endHeadingFlip,
  required List<DrawRect> obstacles,
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

List<_GridNode> _astar({
  required _Grid grid,
  required _GridNode start,
  required _GridNode end,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required bool startConstrained,
  required bool endConstrained,
  required List<DrawRect> obstacles,
}) {
  // A* with bend penalties to discourage unnecessary elbows.
  final openSet = _BinaryHeap<_GridNode>((node) => node.f)..push(start);

  final bendPenalty = _BendPenalty(
    ElbowGeometry.manhattanDistance(start.pos, end.pos),
  );
  final startHeadingFlip = startHeading.opposite;
  final endHeadingFlip = endHeading.opposite;

  while (openSet.isNotEmpty) {
    final current = openSet.pop();
    if (current == null) {
      break;
    }
    if (current.closed) {
      continue;
    }
    if (current.addr == end.addr) {
      return _reconstructPath(current, start);
    }

    current.closed = true;

    final previousHeading = current.parent == null
        ? startHeading
        : _headingBetween(current.pos, current.parent!.pos);
    final isStartNode = current.addr == start.addr;
    final col = current.addr.col;
    final row = current.addr.row;

    for (final offset in _neighborOffsets) {
      final next = grid.nodeAt(col + offset.dx, row + offset.dy);
      if (next == null) {
        continue;
      }
      if (next.closed) {
        continue;
      }

      final neighborHeading = offset.heading;

      if (!_canTraverseNeighbor(
        current: current,
        next: next,
        isStartNode: isStartNode,
        endAddress: end.addr,
        previousHeading: previousHeading,
        neighborHeading: neighborHeading,
        startConstrained: startConstrained,
        endConstrained: endConstrained,
        startHeading: startHeading,
        startHeadingFlip: startHeadingFlip,
        endHeadingFlip: endHeadingFlip,
        obstacles: obstacles,
      )) {
        continue;
      }

      final directionChanged = neighborHeading != previousHeading;
      final moveCost = ElbowGeometry.manhattanDistance(current.pos, next.pos);
      final bendCost = directionChanged ? bendPenalty.cubed : 0;
      final gScore = current.g + moveCost + bendCost;

      if (!next.visited || gScore < next.g) {
        final hScore = _heuristicScore(
          from: next.pos,
          to: end.pos,
          fromHeading: neighborHeading,
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

  return const <_GridNode>[];
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

List<_GridNode>? _tryRouteGridPath({
  required _Grid grid,
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
  required DrawPoint startDongle,
  required DrawPoint endDongle,
  required List<DrawRect> obstacles,
}) {
  final startNode = grid.nodeForPoint(startDongle);
  final endNode = grid.nodeForPoint(endDongle);
  if (startNode == null || endNode == null) {
    return null;
  }

  return _astar(
    grid: grid,
    start: startNode,
    end: endNode,
    startHeading: start.heading,
    endHeading: end.heading,
    startConstrained: start.isBound,
    endConstrained: end.isBound,
    obstacles: obstacles,
  );
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
  return neighborHeading != endHeadingFlip;
}

List<_GridNode> _reconstructPath(_GridNode current, _GridNode start) {
  final reversed = <_GridNode>[];
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
class _NeighborOffset {
  const _NeighborOffset(this.dx, this.dy, this.heading);

  final int dx;
  final int dy;
  final ElbowHeading heading;
}

const List<_NeighborOffset> _neighborOffsets = [
  _NeighborOffset(0, -1, ElbowHeading.up),
  _NeighborOffset(1, 0, ElbowHeading.right),
  _NeighborOffset(0, 1, ElbowHeading.down),
  _NeighborOffset(-1, 0, ElbowHeading.left),
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
