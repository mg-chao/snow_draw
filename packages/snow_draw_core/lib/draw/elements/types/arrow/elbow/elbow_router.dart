import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../../utils/selection_calculator.dart';
import '../../../../models/element_state.dart';
import '../../../../types/draw_point.dart';
import '../../../../types/draw_rect.dart';
import '../../../../types/element_style.dart';
import '../../../../core/coordinates/element_space.dart';
import '../arrow_binding.dart';
import '../arrow_data.dart';
import '../arrow_geometry.dart';

const double _basePadding = 40;
const double _dedupThreshold = 1;
const double _minArrowLength = 8;
const double _maxPosition = 1000000;
const double _donglePointPadding = 2;
const double _arrowheadPadding = 12;
const double _basePointPadding = 4;

@immutable
final class ElbowRouteResult {
  const ElbowRouteResult({
    required this.points,
    required this.startPoint,
    required this.endPoint,
  });

  final List<DrawPoint> points;
  final DrawPoint startPoint;
  final DrawPoint endPoint;
}

@immutable
final class ElbowRoutedPoints {
  const ElbowRoutedPoints({
    required this.localPoints,
    required this.worldPoints,
  });

  final List<DrawPoint> localPoints;
  final List<DrawPoint> worldPoints;
}

enum ElbowHeading { right, down, left, up }

extension ElbowHeadingX on ElbowHeading {
  int get dx => switch (this) {
    ElbowHeading.right => 1,
    ElbowHeading.left => -1,
    _ => 0,
  };
  int get dy => switch (this) {
    ElbowHeading.down => 1,
    ElbowHeading.up => -1,
    _ => 0,
  };

  bool get isHorizontal =>
      this == ElbowHeading.right || this == ElbowHeading.left;
}

ElbowHeading _flipHeading(ElbowHeading heading) => switch (heading) {
  ElbowHeading.right => ElbowHeading.left,
  ElbowHeading.left => ElbowHeading.right,
  ElbowHeading.up => ElbowHeading.down,
  ElbowHeading.down => ElbowHeading.up,
};

ElbowHeading _vectorToHeading(double dx, double dy) {
  final absX = dx.abs();
  final absY = dy.abs();
  if (absX >= absY) {
    return dx >= 0 ? ElbowHeading.right : ElbowHeading.left;
  }
  return dy >= 0 ? ElbowHeading.down : ElbowHeading.up;
}

ElbowHeading _headingForPointOnBounds(DrawRect bounds, DrawPoint point) {
  final left = (point.x - bounds.minX).abs();
  final right = (bounds.maxX - point.x).abs();
  final top = (point.y - bounds.minY).abs();
  final bottom = (bounds.maxY - point.y).abs();
  final minEdge = math.min(math.min(left, right), math.min(top, bottom));
  if (minEdge == left) {
    return ElbowHeading.left;
  }
  if (minEdge == right) {
    return ElbowHeading.right;
  }
  if (minEdge == top) {
    return ElbowHeading.up;
  }
  return ElbowHeading.down;
}

double _manhattanDistance(DrawPoint a, DrawPoint b) =>
    (a.x - b.x).abs() + (a.y - b.y).abs();

bool _pointInBounds(DrawPoint point, DrawRect bounds) =>
    point.x >= bounds.minX &&
    point.x <= bounds.maxX &&
    point.y >= bounds.minY &&
    point.y <= bounds.maxY;

DrawRect _inflateBounds(DrawRect rect, double padding) => DrawRect(
  minX: rect.minX - padding,
  minY: rect.minY - padding,
  maxX: rect.maxX + padding,
  maxY: rect.maxY + padding,
);

DrawRect _clampBounds(DrawRect rect) => DrawRect(
  minX: rect.minX.clamp(-_maxPosition, _maxPosition),
  minY: rect.minY.clamp(-_maxPosition, _maxPosition),
  maxX: rect.maxX.clamp(-_maxPosition, _maxPosition),
  maxY: rect.maxY.clamp(-_maxPosition, _maxPosition),
);

DrawPoint _clampPoint(DrawPoint point) => DrawPoint(
  x: point.x.clamp(-_maxPosition, _maxPosition),
  y: point.y.clamp(-_maxPosition, _maxPosition),
);

DrawRect _unionBounds(List<DrawRect> bounds) {
  var minX = bounds.first.minX;
  var minY = bounds.first.minY;
  var maxX = bounds.first.maxX;
  var maxY = bounds.first.maxY;
  for (final rect in bounds.skip(1)) {
    minX = math.min(minX, rect.minX);
    minY = math.min(minY, rect.minY);
    maxX = math.max(maxX, rect.maxX);
    maxY = math.max(maxY, rect.maxY);
  }
  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

DrawRect _createBoundingBox({
  required DrawPoint point,
  required ElementState? element,
  required ElbowHeading heading,
  required bool hasArrowhead,
}) {
  if (element == null) {
    return DrawRect(
      minX: point.x - _donglePointPadding,
      minY: point.y - _donglePointPadding,
      maxX: point.x + _donglePointPadding,
      maxY: point.y + _donglePointPadding,
    );
  }

  final base = SelectionCalculator.computeElementWorldAabb(element);
  final headOffset = hasArrowhead ? _arrowheadPadding : _basePointPadding;
  final sideOffset = _donglePointPadding;
  final padding = _paddingFromHeading(heading, headOffset, sideOffset);
  return DrawRect(
    minX: base.minX - padding.left,
    minY: base.minY - padding.top,
    maxX: base.maxX + padding.right,
    maxY: base.maxY + padding.bottom,
  );
}

_BoundsPadding _paddingFromHeading(
  ElbowHeading heading,
  double headOffset,
  double sideOffset,
) => switch (heading) {
  ElbowHeading.up => _BoundsPadding(
    top: headOffset,
    right: sideOffset,
    bottom: sideOffset,
    left: sideOffset,
  ),
  ElbowHeading.right => _BoundsPadding(
    top: sideOffset,
    right: headOffset,
    bottom: sideOffset,
    left: sideOffset,
  ),
  ElbowHeading.down => _BoundsPadding(
    top: sideOffset,
    right: sideOffset,
    bottom: headOffset,
    left: sideOffset,
  ),
  ElbowHeading.left => _BoundsPadding(
    top: sideOffset,
    right: sideOffset,
    bottom: sideOffset,
    left: headOffset,
  ),
};

@immutable
class _BoundsPadding {
  const _BoundsPadding({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  final double top;
  final double right;
  final double bottom;
  final double left;
}

DrawPoint _donglePosition({
  required DrawRect bounds,
  required ElbowHeading heading,
  required DrawPoint point,
}) {
  switch (heading) {
    case ElbowHeading.up:
      return DrawPoint(x: point.x, y: bounds.minY);
    case ElbowHeading.right:
      return DrawPoint(x: bounds.maxX, y: point.y);
    case ElbowHeading.down:
      return DrawPoint(x: point.x, y: bounds.maxY);
    case ElbowHeading.left:
      return DrawPoint(x: bounds.minX, y: point.y);
  }
}

ElbowRouteResult routeElbowArrow({
  required DrawPoint start,
  required DrawPoint end,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
  required Map<String, ElementState> elementsById,
  ArrowheadStyle startArrowhead = ArrowheadStyle.none,
  ArrowheadStyle endArrowhead = ArrowheadStyle.none,
}) {
  final startElement = startBinding == null
      ? null
      : elementsById[startBinding.elementId];
  final endElement =
      endBinding == null ? null : elementsById[endBinding.elementId];

  final resolvedStart = startElement == null || startBinding == null
      ? start
      : ArrowBindingUtils.resolveBoundPoint(
            binding: startBinding,
            target: startElement,
            referencePoint: end,
          ) ??
          start;
  final resolvedEnd = endElement == null || endBinding == null
      ? end
      : ArrowBindingUtils.resolveBoundPoint(
            binding: endBinding,
            target: endElement,
            referencePoint: start,
          ) ??
          end;

  final vectorHeading = _vectorToHeading(
    resolvedEnd.x - resolvedStart.x,
    resolvedEnd.y - resolvedStart.y,
  );
  final startHeading = startElement == null
      ? vectorHeading
      : _headingForPointOnBounds(
          SelectionCalculator.computeElementWorldAabb(startElement),
          resolvedStart,
        );
  final endHeading = endElement == null
      ? _vectorToHeading(
          resolvedStart.x - resolvedEnd.x,
          resolvedStart.y - resolvedEnd.y,
        )
      : _headingForPointOnBounds(
          SelectionCalculator.computeElementWorldAabb(endElement),
          resolvedEnd,
        );

  if (startElement == null && endElement == null) {
    final simple = _fallbackPath(
      start: resolvedStart,
      end: resolvedEnd,
      startHeading: startHeading,
    );
    return ElbowRouteResult(
      points: simple,
      startPoint: resolvedStart,
      endPoint: resolvedEnd,
    );
  }

  final startBounds = _createBoundingBox(
    point: resolvedStart,
    element: startElement,
    heading: startHeading,
    hasArrowhead: startArrowhead != ArrowheadStyle.none,
  );
  final endBounds = _createBoundingBox(
    point: resolvedEnd,
    element: endElement,
    heading: endHeading,
    hasArrowhead: endArrowhead != ArrowheadStyle.none,
  );
  final startObstacle = _clampBounds(_inflateBounds(startBounds, _basePadding));
  final endObstacle = _clampBounds(_inflateBounds(endBounds, _basePadding));
  final commonBounds = _clampBounds(_inflateBounds(
    _unionBounds([startObstacle, endObstacle]),
    _basePadding,
  ));

  final startDongle = _donglePosition(
    bounds: startObstacle,
    heading: startHeading,
    point: resolvedStart,
  );
  final endDongle = _donglePosition(
    bounds: endObstacle,
    heading: endHeading,
    point: resolvedEnd,
  );

  final direct = _directPathIfClear(
    start: resolvedStart,
    end: resolvedEnd,
    obstacles: [startObstacle, endObstacle],
    startHeading: startHeading,
    endHeading: endHeading,
  );
  if (direct != null) {
    return ElbowRouteResult(
      points: direct,
      startPoint: resolvedStart,
      endPoint: resolvedEnd,
    );
  }

  final grid = _buildGrid(
    obstacles: [startObstacle, endObstacle],
    start: startDongle,
    startHeading: startHeading,
    end: endDongle,
    endHeading: endHeading,
    bounds: commonBounds,
  );
  final startNode = grid.nodeForPoint(startDongle);
  final endNode = grid.nodeForPoint(endDongle);

  final path = (startNode != null && endNode != null)
      ? _astar(
          grid: grid,
          start: startNode,
          end: endNode,
          startHeading: startHeading,
          endHeading: endHeading,
          obstacles: [startObstacle, endObstacle],
        )
      : null;

  final routed = path == null
      ? _fallbackPath(
          start: resolvedStart,
          end: resolvedEnd,
          startHeading: startHeading,
        )
      : _postProcessPath(
          path: path,
          startPoint: resolvedStart,
          endPoint: resolvedEnd,
          startDongle: startDongle,
          endDongle: endDongle,
        );

  final cleaned = _getCornerPoints(_removeShortSegments(routed));
  final clamped = cleaned.map(_clampPoint).toList(growable: false);

  return ElbowRouteResult(
    points: clamped,
    startPoint: resolvedStart,
    endPoint: resolvedEnd,
  );
}

ElbowRoutedPoints routeElbowArrowForElement({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  DrawPoint? startOverride,
  DrawPoint? endOverride,
}) {
  final basePoints = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  ).map((point) => DrawPoint(x: point.dx, y: point.dy)).toList();
  final localStart = startOverride ?? basePoints.first;
  final localEnd = endOverride ?? basePoints.last;

  final space = ElementSpace(rotation: element.rotation, origin: element.rect.center);
  final worldStart = space.toWorld(localStart);
  final worldEnd = space.toWorld(localEnd);

  final routed = routeElbowArrow(
    start: worldStart,
    end: worldEnd,
    startBinding: data.startBinding,
    endBinding: data.endBinding,
    elementsById: elementsById,
    startArrowhead: data.startArrowhead,
    endArrowhead: data.endArrowhead,
  );

  final localPoints = routed.points
      .map((point) => space.fromWorld(point))
      .toList(growable: false);

  return ElbowRoutedPoints(
    localPoints: localPoints,
    worldPoints: routed.points,
  );
}

List<DrawPoint>? _directPathIfClear({
  required DrawPoint start,
  required DrawPoint end,
  required List<DrawRect> obstacles,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
}) {
  final alignedX = (start.x - end.x).abs() <= _dedupThreshold;
  final alignedY = (start.y - end.y).abs() <= _dedupThreshold;
  if (!alignedX && !alignedY) {
    return null;
  }
  if (alignedY && (!startHeading.isHorizontal || !endHeading.isHorizontal)) {
    return null;
  }
  if (alignedX && (startHeading.isHorizontal || endHeading.isHorizontal)) {
    return null;
  }

  final mid = DrawPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2);
  for (final obstacle in obstacles) {
    if (_pointInBounds(mid, obstacle)) {
      return null;
    }
  }
  return [start, end];
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
  final points = path.map((node) => node.pos).toList();
  if (points.isEmpty) {
    return [startPoint, endPoint];
  }
  if (startDongle != startPoint && points.first != startPoint) {
    points.insert(0, startPoint);
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

  bool isHorizontal(DrawPoint a, DrawPoint b) =>
      (a.y - b.y).abs() <= (a.x - b.x).abs();

  var previousIsHorizontal = isHorizontal(points[0], points[1]);
  final result = <DrawPoint>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final nextIsHorizontal = isHorizontal(points[i], points[i + 1]);
    if (previousIsHorizontal != nextIsHorizontal) {
      result.add(points[i]);
    }
    previousIsHorizontal = nextIsHorizontal;
  }
  result.add(points.last);
  return result;
}

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
  bool closed = false;
  bool visited = false;
  _GridNode? parent;
}

@immutable
class _GridAddress {
  const _GridAddress({required this.col, required this.row});

  final int col;
  final int row;
}

_Grid _buildGrid({
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
    xs.add(obstacle.minX);
    xs.add(obstacle.maxX);
    ys.add(obstacle.minY);
    ys.add(obstacle.maxY);
  }

  xs.add(start.x);
  ys.add(start.y);
  xs.add(end.x);
  ys.add(end.y);

  xs.add(bounds.minX);
  xs.add(bounds.maxX);
  ys.add(bounds.minY);
  ys.add(bounds.maxY);

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
  final xIndex = <double, int>{
    for (var i = 0; i < sortedX.length; i++) sortedX[i]: i,
  };
  final yIndex = <double, int>{
    for (var i = 0; i < sortedY.length; i++) sortedY[i]: i,
  };

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

List<_GridNode> _astar({
  required _Grid grid,
  required _GridNode start,
  required _GridNode end,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required List<DrawRect> obstacles,
}) {
  final openSet = _BinaryHeap<_GridNode>((node) => node.f);
  openSet.push(start);

  final bendPenalty = _manhattanDistance(start.pos, end.pos);

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

    final neighbors = _neighborsForNode(grid, current);
    for (final entry in neighbors) {
      final neighbor = entry.node;
      if (neighbor == null) {
        continue;
      }
      final next = neighbor;
      if (next.closed) {
        continue;
      }

      final mid = DrawPoint(
        x: (current.pos.x + next.pos.x) / 2,
        y: (current.pos.y + next.pos.y) / 2,
      );
      if (_intersectsObstacle(mid, obstacles)) {
        continue;
      }

      final neighborHeading = entry.heading;
      final previousHeading = current.parent == null
          ? startHeading
          : _headingBetween(current.pos, current.parent!.pos);

      if (neighborHeading == _flipHeading(previousHeading)) {
        continue;
      }

      if (current.addr == start.addr &&
          neighborHeading == _flipHeading(startHeading)) {
        continue;
      }

      if (next.addr == end.addr &&
          neighborHeading == _flipHeading(endHeading)) {
        continue;
      }

      final directionChanged = neighborHeading != previousHeading;
      final moveCost = _manhattanDistance(current.pos, next.pos);
      final bendCost = directionChanged ? math.pow(bendPenalty, 3).toDouble() : 0;
      final gScore = current.g + moveCost + bendCost;

      if (!next.visited || gScore < next.g) {
        final hScore =
            _manhattanDistance(next.pos, end.pos) +
            _estimatedBendPenalty(
              start: next.pos,
              end: end.pos,
              startHeading: neighborHeading,
              endHeading: _flipHeading(endHeading),
              bendPenalty: bendPenalty,
            );
        next.parent = current;
        next.g = gScore;
        next.h = hScore;
        next.f = gScore + hScore;
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
  required double bendPenalty,
}) {
  if (startHeading.isHorizontal == endHeading.isHorizontal) {
    if (startHeading.isHorizontal && (start.y - end.y).abs() <= _dedupThreshold) {
      return 0;
    }
    if (!startHeading.isHorizontal &&
        (start.x - end.x).abs() <= _dedupThreshold) {
      return 0;
    }
    return math.pow(bendPenalty, 2).toDouble();
  }
  return math.pow(bendPenalty, 2).toDouble();
}

ElbowHeading _headingBetween(DrawPoint from, DrawPoint to) =>
    _vectorToHeading(from.x - to.x, from.y - to.y);

bool _intersectsObstacle(DrawPoint mid, List<DrawRect> obstacles) {
  for (final obstacle in obstacles) {
    if (_pointInBounds(mid, obstacle)) {
      return true;
    }
  }
  return false;
}

List<_GridNode> _reconstructPath(_GridNode current, _GridNode start) {
  final path = <_GridNode>[];
  var node = current;
  while (true) {
    path.insert(0, node);
    final parent = node.parent;
    if (parent == null) {
      break;
    }
    node = parent;
  }
  if (path.isEmpty) {
    return [start];
  }
  if (path.first.addr != start.addr) {
    path.insert(0, start);
  }
  return path;
}

class _NeighborEntry {
  const _NeighborEntry({required this.node, required this.heading});

  final _GridNode? node;
  final ElbowHeading heading;
}

List<_NeighborEntry> _neighborsForNode(_Grid grid, _GridNode node) {
  final col = node.addr.col;
  final row = node.addr.row;
  return [
    _NeighborEntry(
      node: grid.nodeAt(col, row - 1),
      heading: ElbowHeading.up,
    ),
    _NeighborEntry(
      node: grid.nodeAt(col + 1, row),
      heading: ElbowHeading.right,
    ),
    _NeighborEntry(
      node: grid.nodeAt(col, row + 1),
      heading: ElbowHeading.down,
    ),
    _NeighborEntry(
      node: grid.nodeAt(col - 1, row),
      heading: ElbowHeading.left,
    ),
  ];
}

class _BinaryHeap<T> {
  _BinaryHeap(this.score);

  final double Function(T) score;
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
    final elementScore = score(element);
    while (n > 0) {
      final parentN = ((n + 1) >> 1) - 1;
      final parent = _content[parentN];
      if (elementScore < score(parent)) {
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
    final elemScore = score(element);

    while (true) {
      final child2N = (n + 1) << 1;
      final child1N = child2N - 1;
      int? swap;
      var child1Score = 0.0;

      if (child1N < length) {
        final child1 = _content[child1N];
        child1Score = score(child1);
        if (child1Score < elemScore) {
          swap = child1N;
        }
      }

      if (child2N < length) {
        final child2 = _content[child2N];
        final child2Score = score(child2);
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
