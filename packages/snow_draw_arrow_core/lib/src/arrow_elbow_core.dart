import 'dart:math' as math;

import 'arrow_binding_core.dart';
import 'arrow_geom.dart';
import 'arrow_types.dart';

typedef _Bounds = List<double>;

class _GridNode {
  const _GridNode({
    required this.x,
    required this.y,
    required this.col,
    required this.row,
  });

  final double x;
  final double y;
  final int col;
  final int row;
}

class _Grid {
  const _Grid({
    required this.nodes,
    required this.byCoord,
    required this.cols,
    required this.rows,
  });

  final List<_GridNode> nodes;
  final Map<String, _GridNode> byCoord;
  final int cols;
  final int rows;
}

class _QueueNode {
  const _QueueNode({
    required this.key,
    required this.node,
    required this.heading,
    required this.g,
    required this.f,
    required this.parentKey,
  });

  final String key;
  final _GridNode node;
  final Heading heading;
  final double g;
  final double f;
  final String? parentKey;
}

class _EndpointAndHeading {
  const _EndpointAndHeading({
    required this.point,
    required this.heading,
    required this.obstacle,
  });

  final Point point;
  final Heading heading;
  final _Bounds? obstacle;
}

class _ResizeArrowData {
  const _ResizeArrowData({
    required this.startBinding,
    required this.endBinding,
    required this.fixedSegments,
  });

  final FixedPointBinding? startBinding;
  final FixedPointBinding? endBinding;
  final List<FixedSegment>? fixedSegments;
}

const double _dedupThreshold = 1;
const double basePadding = 40;

_Bounds _obstacleForBindable(BindableState bindable, double gap) {
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );
  final corners = <Point>[
    <double>[bindable.x - gap, bindable.y - gap],
    <double>[bindable.x + bindable.width + gap, bindable.y - gap],
    <double>[
      bindable.x + bindable.width + gap,
      bindable.y + bindable.height + gap,
    ],
    <double>[bindable.x - gap, bindable.y + bindable.height + gap],
  ];
  final rotated = corners
      .map((corner) => rotatePoint(corner, bindableCenter, bindable.angle))
      .toList(growable: false);

  final minX = rotated.map((point) => point[0]).reduce(math.min);
  final minY = rotated.map((point) => point[1]).reduce(math.min);
  final maxX = rotated.map((point) => point[0]).reduce(math.max);
  final maxY = rotated.map((point) => point[1]).reduce(math.max);
  return <double>[minX, minY, maxX, maxY];
}

bool _pointInBounds(Point point, _Bounds bounds) =>
    point[0] >= bounds[0] &&
    point[0] <= bounds[2] &&
    point[1] >= bounds[1] &&
    point[1] <= bounds[3];

bool _segmentIntersectsBounds(Point a, Point b, _Bounds bounds) {
  final midpoint = <double>[(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
  return _pointInBounds(midpoint, bounds);
}

_Bounds _commonBounds(List<Point> points, double padding) {
  final xs = points.map((point) => point[0]);
  final ys = points.map((point) => point[1]);
  return <double>[
    xs.reduce(math.min) - padding,
    ys.reduce(math.min) - padding,
    xs.reduce(math.max) + padding,
    ys.reduce(math.max) + padding,
  ];
}

_Grid _makeGrid(List<_Bounds> obstacles, Point start, Point end) {
  final xs = <double>{start[0], end[0]};
  final ys = <double>{start[1], end[1]};

  for (final obstacle in obstacles) {
    xs
      ..add(obstacle[0])
      ..add(obstacle[2]);
    ys
      ..add(obstacle[1])
      ..add(obstacle[3]);
  }

  final sortedX = xs.toList(growable: false)..sort();
  final sortedY = ys.toList(growable: false)..sort();
  final nodes = <_GridNode>[];
  final byCoord = <String, _GridNode>{};

  for (var row = 0; row < sortedY.length; row += 1) {
    for (var col = 0; col < sortedX.length; col += 1) {
      final node = _GridNode(
        x: sortedX[col],
        y: sortedY[row],
        col: col,
        row: row,
      );
      nodes.add(node);
      byCoord['${node.x}:${node.y}'] = node;
    }
  }

  return _Grid(
    nodes: nodes,
    byCoord: byCoord,
    cols: sortedX.length,
    rows: sortedY.length,
  );
}

List<_GridNode> _neighborsOf(_GridNode node, _Grid grid) {
  _GridNode? at(int col, int row) {
    if (col < 0 || row < 0 || col >= grid.cols || row >= grid.rows) {
      return null;
    }
    return grid.nodes[row * grid.cols + col];
  }

  final up = at(node.col, node.row - 1);
  final right = at(node.col + 1, node.row);
  final down = at(node.col, node.row + 1);
  final left = at(node.col - 1, node.row);

  final neighbors = <_GridNode>[];
  if (up != null) {
    neighbors.add(up);
  }
  if (right != null) {
    neighbors.add(right);
  }
  if (down != null) {
    neighbors.add(down);
  }
  if (left != null) {
    neighbors.add(left);
  }

  return neighbors;
}

Heading _headingBetween(_GridNode from, _GridNode to) {
  if (to.x > from.x) {
    return 'right';
  }
  if (to.x < from.x) {
    return 'left';
  }
  if (to.y > from.y) {
    return 'down';
  }
  return 'up';
}

List<Point> _reconstructPath(String endKey, Map<String, _QueueNode> visited) {
  final out = <Point>[];
  String? key = endKey;
  while (key != null) {
    final node = visited[key];
    if (node == null) {
      break;
    }
    out.add(<double>[node.node.x, node.node.y]);
    key = node.parentKey;
  }
  return out.reversed.toList(growable: false);
}

String _keyForState(_GridNode node, Heading heading) =>
    '${node.x}:${node.y}:$heading';

List<Point>? _routeAStar(
  _GridNode start,
  _GridNode end,
  Heading startHeading,
  Heading endHeading,
  _Grid grid,
  List<_Bounds> obstacles,
) {
  final open = <_QueueNode>[];
  final visited = <String, _QueueNode>{};

  final startState = _QueueNode(
    key: _keyForState(start, startHeading),
    node: start,
    heading: startHeading,
    g: 0,
    f: manhattan(<double>[start.x, start.y], <double>[end.x, end.y]),
    parentKey: null,
  );
  open.add(startState);
  visited[startState.key] = startState;

  final bendMultiplier = math.max(
    1,
    manhattan(<double>[start.x, start.y], <double>[end.x, end.y]),
  );

  while (open.isNotEmpty) {
    open.sort((left, right) => left.f.compareTo(right.f));
    final current = open.removeAt(0);

    if (current.node.x == end.x && current.node.y == end.y) {
      return _reconstructPath(current.key, visited);
    }

    final candidates = _neighborsOf(current.node, grid);
    for (final candidate in candidates) {
      final nextHeading = _headingBetween(current.node, candidate);
      if (nextHeading == reverseHeading(current.heading)) {
        continue;
      }

      if (candidate.x == end.x &&
          candidate.y == end.y &&
          nextHeading == reverseHeading(endHeading)) {
        continue;
      }

      final blocked = obstacles.any(
        (obstacle) => _segmentIntersectsBounds(
          <double>[current.node.x, current.node.y],
          <double>[candidate.x, candidate.y],
          obstacle,
        ),
      );
      if (blocked) {
        continue;
      }

      final bendPenalty = current.heading == nextHeading
          ? 0.0
          : math.pow(bendMultiplier, 2).toDouble();
      final g =
          current.g +
          manhattan(
            <double>[current.node.x, current.node.y],
            <double>[candidate.x, candidate.y],
          ) +
          bendPenalty;
      final h =
          manhattan(
            <double>[candidate.x, candidate.y],
            <double>[end.x, end.y],
          ) +
          (nextHeading == endHeading ? 0 : bendMultiplier);
      final f = g + h;

      final key = _keyForState(candidate, nextHeading);
      final existing = visited[key];
      if (existing != null && existing.g <= g) {
        continue;
      }

      final nextState = _QueueNode(
        key: key,
        node: candidate,
        heading: nextHeading,
        g: g,
        f: f,
        parentKey: current.key,
      );
      visited[key] = nextState;
      open.add(nextState);
    }
  }

  return null;
}

List<Point> _removeShortSegments(List<Point> points) {
  if (points.length < 3) {
    return points
        .map((point) => <double>[point[0], point[1]])
        .toList(growable: false);
  }

  final out = <Point>[
    <double>[points[0][0], points[0][1]],
  ];
  for (var index = 1; index < points.length - 1; index += 1) {
    final previous = out[out.length - 1];
    final current = points[index];
    if (distance(previous, current) <= _dedupThreshold) {
      continue;
    }
    out.add(<double>[current[0], current[1]]);
  }

  final last = points[points.length - 1];
  out.add(<double>[last[0], last[1]]);
  return out;
}

List<Point> _applyFixedSegments(List<Point> points, ArrowState arrow) {
  final fixedSegments = arrow.fixedSegments;
  if (fixedSegments == null || fixedSegments.isEmpty) {
    return points;
  }

  final out = points
      .map((point) => <double>[point[0], point[1]])
      .toList(growable: false);

  for (final fixed in fixedSegments) {
    if (fixed.index <= 0 || fixed.index >= out.length) {
      continue;
    }
    out[fixed.index - 1] = <double>[
      arrow.x + fixed.start[0],
      arrow.y + fixed.start[1],
    ];
    out[fixed.index] = <double>[arrow.x + fixed.end[0], arrow.y + fixed.end[1]];
  }

  return out;
}

List<Point> _ensureOrthogonal(List<Point> points) {
  if (points.length < 2) {
    return points
        .map((point) => <double>[point[0], point[1]])
        .toList(growable: false);
  }

  final result = <Point>[
    <double>[points[0][0], points[0][1]],
  ];
  for (var index = 1; index < points.length; index += 1) {
    final prev = result[result.length - 1];
    final current = points[index];
    final sameX = (prev[0] - current[0]).abs() <= 1e-6;
    final sameY = (prev[1] - current[1]).abs() <= 1e-6;
    if (sameX || sameY) {
      result.add(<double>[current[0], current[1]]);
      continue;
    }

    final bend = <double>[current[0], prev[1]];
    result
      ..add(bend)
      ..add(<double>[current[0], current[1]]);
  }

  return dedupeCollinearPoints(result);
}

_EndpointAndHeading _computeEndpointAndHeading(
  ArrowState arrow,
  Map<String, BindableState> bindablesById,
  String side, {
  double? zoom,
}) {
  final isStart = side == 'start';
  final binding = isStart ? arrow.startBinding : arrow.endBinding;
  final point = getPointAtIndexGlobal(arrow, isStart ? 0 : -1);

  if (binding == null) {
    final otherPoint = getPointAtIndexGlobal(arrow, isStart ? -1 : 0);
    return _EndpointAndHeading(
      point: point,
      heading: getHeadingForElbowSnap(
        point: point,
        otherPoint: otherPoint,
        zoom: zoom,
      ),
      obstacle: null,
    );
  }

  final bindable = bindablesById[binding.elementId];
  if (bindable == null) {
    final otherPoint = getPointAtIndexGlobal(arrow, isStart ? -1 : 0);
    return _EndpointAndHeading(
      point: point,
      heading: getHeadingForElbowSnap(
        point: point,
        otherPoint: otherPoint,
        zoom: zoom,
      ),
      obstacle: null,
    );
  }

  final fixedPoint = getGlobalFixedPoint(binding, bindable);
  final otherPoint = getPointAtIndexGlobal(arrow, isStart ? -1 : 0);
  return _EndpointAndHeading(
    point: fixedPoint,
    heading: getHeadingForElbowSnap(
      point: fixedPoint,
      otherPoint: otherPoint,
      bindable: bindable,
      zoom: zoom,
    ),
    obstacle: _obstacleForBindable(bindable, getBindingGap(bindable, true)),
  );
}

List<Point> _applyPointUpdate(List<Point> points, List<Point>? updatedPoints) {
  if (updatedPoints == null) {
    return points
        .map((point) => <double>[point[0], point[1]])
        .toList(growable: false);
  }

  if (updatedPoints.length == 2 && points.length > 2) {
    return points
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key;
          final point = entry.value;
          if (index == 0) {
            return <double>[updatedPoints[0][0], updatedPoints[0][1]];
          }
          if (index == points.length - 1) {
            return <double>[updatedPoints[1][0], updatedPoints[1][1]];
          }
          return <double>[point[0], point[1]];
        })
        .toList(growable: false);
  }

  return updatedPoints
      .map((point) => <double>[point[0], point[1]])
      .toList(growable: false);
}

List<Point> _toGlobalPoints(ArrowState arrow, List<Point> points) => points
    .map((point) => <double>[arrow.x + point[0], arrow.y + point[1]])
    .toList(growable: false);

List<Point> _clonePoints(List<Point> points) =>
    points.map((point) => <double>[point[0], point[1]]).toList(growable: false);

List<FixedSegment>? _cloneFixedSegments(List<FixedSegment>? segments) {
  if (segments == null) {
    return null;
  }
  return segments
      .map(
        (segment) => FixedSegment(
          index: segment.index,
          start: <double>[segment.start[0], segment.start[1]],
          end: <double>[segment.end[0], segment.end[1]],
        ),
      )
      .toList(growable: false);
}

List<FixedSegment>? _normalizeFixedSegmentsFromPoints(
  List<FixedSegment>? fixedSegments,
  List<Point> points,
) {
  if (fixedSegments == null || fixedSegments.isEmpty || points.length < 2) {
    return null;
  }

  final normalized = <FixedSegment>[];
  for (final segment in fixedSegments) {
    final index = segment.index;
    if (index <= 0 || index >= points.length) {
      continue;
    }
    if (index == 1 || index == points.length - 1) {
      continue;
    }

    normalized.add(
      FixedSegment(
        index: index,
        start: <double>[points[index - 1][0], points[index - 1][1]],
        end: <double>[points[index][0], points[index][1]],
      ),
    );
  }
  return normalized.isEmpty ? null : normalized;
}

ArrowPatch _normalizePatchWithMetaFromLocalPoints(
  ArrowState arrow,
  List<Point> localPoints,
  double maxCoordinate, {
  List<FixedSegment>? fixedSegments,
  bool? startIsSpecial,
  bool? endIsSpecial,
}) {
  final normalized = normalizeArrowFromGlobalPoints(
    _toGlobalPoints(arrow, localPoints),
    maxCoordinate,
  );
  final normalizedFixedSegments = _normalizeFixedSegmentsFromPoints(
    fixedSegments,
    normalized.points,
  );
  return <String, dynamic>{
    'x': normalized.x,
    'y': normalized.y,
    'points': normalized.points,
    'width': normalized.width,
    'height': normalized.height,
    'fixedSegments': normalizedFixedSegments,
    'startIsSpecial': startIsSpecial,
    'endIsSpecial': endIsSpecial,
  };
}

ArrowPatch _normalizePatchWithMetaFromGlobalPoints(
  List<Point> globalPoints,
  double maxCoordinate, {
  List<FixedSegment>? fixedSegments,
  bool? startIsSpecial,
  bool? endIsSpecial,
}) {
  final normalized = normalizeArrowFromGlobalPoints(
    globalPoints,
    maxCoordinate,
  );
  final normalizedFixedSegments = _normalizeFixedSegmentsFromPoints(
    fixedSegments,
    normalized.points,
  );
  return <String, dynamic>{
    'x': normalized.x,
    'y': normalized.y,
    'points': normalized.points,
    'width': normalized.width,
    'height': normalized.height,
    'fixedSegments': normalizedFixedSegments,
    'startIsSpecial': startIsSpecial,
    'endIsSpecial': endIsSpecial,
  };
}

bool _isHeadingPositive(Heading heading) =>
    heading == 'right' || heading == 'down';

Point _pointAt(List<Point> points, int index, String errorMessage) {
  if (index < 0 || index >= points.length) {
    throw StateError(errorMessage);
  }
  return points[index];
}

bool _isAxisAlignedSegment(FixedSegment segment) =>
    segment.start[0] == segment.end[0] || segment.start[1] == segment.end[1];

void _throwInvariant(String message) {
  throw StateError(message);
}

void _validateUpdateInvariants(
  ArrowState arrow,
  ElbowUpdatePatch updates,
  List<Point> updatedPoints,
  List<FixedSegment>? fixedSegments,
) {
  final updatedPointCount = updates.containsKey('points')
      ? _asPointListOrNull(updates['points'])?.length
      : null;
  if (updatedPointCount != null &&
      updatedPointCount != 2 &&
      updatedPointCount != arrow.points.length) {
    _throwInvariant(
      'Updated point array length must match the arrow point length, contain exactly the new start and end points or not be specified at all (i.e. you cannot add new points between start and end manually to elbow arrows)',
    );
  }

  final currentFixedSegments = arrow.fixedSegments;
  if (currentFixedSegments != null &&
      currentFixedSegments.any((segment) => !_isAxisAlignedSegment(segment))) {
    _throwInvariant('Fixed segments must be either horizontal or vertical');
  }

  if (fixedSegments != null &&
      fixedSegments.any((segment) => !_isAxisAlignedSegment(segment))) {
    _throwInvariant(
      'Updates to fixed segments must be either horizontal or vertical',
    );
  }

  if (!validateElbowPoints(arrow.points)) {
    _throwInvariant(
      'Elbow arrow segments must be either horizontal or vertical',
    );
  }

  if (fixedSegments != null && fixedSegments.isNotEmpty) {
    final startPoint = updatedPoints.first;
    final endPoint = updatedPoints.last;
    final hasFirstFixed = fixedSegments.any(
      (segment) => segment.index == 1 && pointsEqual(segment.start, startPoint),
    );
    final hasLastFixed = fixedSegments.any(
      (segment) =>
          segment.index == updatedPoints.length - 1 &&
          pointsEqual(segment.end, endPoint),
    );
    if (hasFirstFixed || hasLastFixed) {
      _throwInvariant('The first and last segments cannot be fixed');
    }
  }
}

ArrowPatch _routeAndNormalizeElbowPatch({
  required ArrowState arrow,
  required Map<String, BindableState> bindablesById,
  required List<FixedSegment>? fixedSegments,
  required double zoom,
  required double maxCoordinate,
  required bool validateInvariants,
  required bool? startIsSpecial,
  required bool? endIsSpecial,
}) {
  final routeArrow = arrow.copyWith(
    fixedSegments: fixedSegments,
    setFixedSegments: true,
  );
  final start = _computeEndpointAndHeading(
    routeArrow,
    bindablesById,
    'start',
    zoom: zoom,
  );
  final end = _computeEndpointAndHeading(
    routeArrow,
    bindablesById,
    'end',
    zoom: zoom,
  );

  final obstacles =
      <_Bounds>[
            for (final bindable in bindablesById.values)
              _obstacleForBindable(bindable, getBindingGap(bindable, true)),
          ]
          .where((obstacle) {
            final startIsInside = _pointInBounds(start.point, obstacle);
            final endIsInside = _pointInBounds(end.point, obstacle);
            return !startIsInside && !endIsInside;
          })
          .toList(growable: false);

  final bounds = _commonBounds(<Point>[
    ..._toGlobalPoints(routeArrow, routeArrow.points),
    start.point,
    end.point,
  ], basePadding);
  final grid = _makeGrid(
    <_Bounds>[...obstacles, bounds],
    start.point,
    end.point,
  );
  final startNode = grid.byCoord['${start.point[0]}:${start.point[1]}'];
  final endNode = grid.byCoord['${end.point[0]}:${end.point[1]}'];

  List<Point>? route;
  if (startNode != null && endNode != null) {
    route = _routeAStar(
      startNode,
      endNode,
      start.heading,
      end.heading,
      grid,
      obstacles,
    );
  }

  final orthogonalRoute = route == null || route.isEmpty
      ? _ensureOrthogonal(<Point>[start.point, end.point])
      : _ensureOrthogonal(route);
  final dedupedRoute = _removeShortSegments(orthogonalRoute);
  final withFixedSegments = _applyFixedSegments(dedupedRoute, routeArrow);
  final orthogonal = _ensureOrthogonal(withFixedSegments);

  final fallbackPoints = _ensureOrthogonal(<Point>[start.point, end.point]);
  final effectiveGlobalPoints =
      validateInvariants && !validateElbowPoints(orthogonal)
      ? fallbackPoints
      : orthogonal;

  final normalized = normalizeArrowFromGlobalPoints(
    effectiveGlobalPoints,
    maxCoordinate,
  );
  final normalizedFixedSegments = _normalizeFixedSegmentsFromPoints(
    fixedSegments,
    normalized.points,
  );
  return <String, dynamic>{
    'x': normalized.x,
    'y': normalized.y,
    'points': normalized.points,
    'width': normalized.width,
    'height': normalized.height,
    'fixedSegments': normalizedFixedSegments,
    'startIsSpecial': startIsSpecial,
    'endIsSpecial': endIsSpecial,
  };
}

ArrowPatch _handleSegmentRenormalization(
  ArrowState arrow,
  Map<String, BindableState> bindablesById,
  bool validateInvariants,
  double maxCoordinate, {
  double zoom = 1,
}) {
  final nextFixedSegments = _cloneFixedSegments(arrow.fixedSegments);
  if (nextFixedSegments == null) {
    return <String, dynamic>{
      'x': arrow.x,
      'y': arrow.y,
      'points': _clonePoints(arrow.points),
      'fixedSegments': null,
      'startIsSpecial': arrow.startIsSpecial,
      'endIsSpecial': arrow.endIsSpecial,
      'width': arrow.width,
      'height': arrow.height,
    };
  }

  final points = _toGlobalPoints(arrow, arrow.points);
  final nextPoints = <Point>[];

  for (var index = 0; index < points.length; index += 1) {
    final point = points[index];
    if (index < 2) {
      nextPoints.add(point);
      continue;
    }

    final currentHeading = vectorToHeading(points[index - 1], point);
    final previousHeading = vectorToHeading(
      points[index - 2],
      points[index - 1],
    );
    if (currentHeading == previousHeading) {
      final prevSegmentIdx = nextFixedSegments.indexWhere(
        (segment) => segment.index == index - 1,
      );
      final segmentIdx = nextFixedSegments.indexWhere(
        (segment) => segment.index == index,
      );
      if (segmentIdx != -1) {
        nextFixedSegments[segmentIdx] = nextFixedSegments[segmentIdx].copyWith(
          start: <double>[
            points[index - 2][0] - arrow.x,
            points[index - 2][1] - arrow.y,
          ],
        );
      }
      if (prevSegmentIdx != -1) {
        nextFixedSegments.removeAt(prevSegmentIdx);
      }
      if (nextPoints.isNotEmpty) {
        nextPoints.removeLast();
      }
      for (
        var segmentIndex = 0;
        segmentIndex < nextFixedSegments.length;
        segmentIndex += 1
      ) {
        final segment = nextFixedSegments[segmentIndex];
        if (segment.index > index - 1) {
          nextFixedSegments[segmentIndex] = segment.copyWith(
            index: segment.index - 1,
          );
        }
      }
    }
    nextPoints.add(point);
  }

  final filteredPoints = <Point>[];
  for (var index = 0; index < nextPoints.length; index += 1) {
    final point = nextPoints[index];
    if (index < 3) {
      filteredPoints.add(point);
      continue;
    }
    if (distance(nextPoints[index - 2], nextPoints[index - 1]) <
        _dedupThreshold) {
      final prevPrevSegmentIdx = nextFixedSegments.indexWhere(
        (segment) => segment.index == index - 2,
      );
      final prevSegmentIdx = nextFixedSegments.indexWhere(
        (segment) => segment.index == index - 1,
      );
      if (prevSegmentIdx != -1) {
        nextFixedSegments.removeAt(prevSegmentIdx);
      }
      if (prevPrevSegmentIdx != -1 &&
          prevPrevSegmentIdx < nextFixedSegments.length) {
        nextFixedSegments.removeAt(prevPrevSegmentIdx);
      }
      if (filteredPoints.length >= 2) {
        filteredPoints.removeLast();
        filteredPoints.removeLast();
      } else {
        filteredPoints.clear();
      }
      for (
        var segmentIndex = 0;
        segmentIndex < nextFixedSegments.length;
        segmentIndex += 1
      ) {
        final segment = nextFixedSegments[segmentIndex];
        if (segment.index > index - 2) {
          nextFixedSegments[segmentIndex] = segment.copyWith(
            index: segment.index - 2,
          );
        }
      }

      final isHorizontal = isHorizontalHeading(
        vectorToHeading(nextPoints[index - 1], point),
      );
      filteredPoints.add(<double>[
        !isHorizontal ? nextPoints[index - 2][0] : point[0],
        isHorizontal ? nextPoints[index - 2][1] : point[1],
      ]);
      continue;
    }
    filteredPoints.add(point);
  }

  final fixedSegments = nextFixedSegments
      .where(
        (segment) =>
            segment.index != 1 && segment.index != filteredPoints.length - 1,
      )
      .toList(growable: false);
  if (fixedSegments.isEmpty) {
    return _routeAndNormalizeElbowPatch(
      arrow: arrow,
      bindablesById: bindablesById,
      fixedSegments: null,
      zoom: zoom,
      maxCoordinate: maxCoordinate,
      validateInvariants: validateInvariants,
      startIsSpecial: null,
      endIsSpecial: null,
    );
  }

  if (validateInvariants && !validateElbowPoints(filteredPoints)) {
    _throwInvariant('Invalid elbow points with fixed segments');
  }
  return _normalizePatchWithMetaFromLocalPoints(
    arrow,
    filteredPoints
        .map((point) => <double>[point[0] - arrow.x, point[1] - arrow.y])
        .toList(growable: false),
    maxCoordinate,
    fixedSegments: fixedSegments,
    startIsSpecial: arrow.startIsSpecial,
    endIsSpecial: arrow.endIsSpecial,
  );
}

ArrowPatch _handleEndpointDrag({
  required ArrowState arrow,
  required List<Point> updatedPoints,
  required List<FixedSegment> fixedSegments,
  required Heading startHeading,
  required Heading endHeading,
  required Point startGlobalPoint,
  required Point endGlobalPoint,
  required BindableState? hoveredStartElement,
  required BindableState? hoveredEndElement,
  required double maxCoordinate,
}) {
  var startIsSpecial = arrow.startIsSpecial;
  var endIsSpecial = arrow.endIsSpecial;

  final globalUpdatedPoints = updatedPoints
      .asMap()
      .entries
      .map((entry) {
        final index = entry.key;
        final point = entry.value;
        if (index == 0 || index == updatedPoints.length - 1) {
          return <double>[arrow.x + point[0], arrow.y + point[1]];
        }
        return <double>[
          arrow.x + arrow.points[index][0],
          arrow.y + arrow.points[index][1],
        ];
      })
      .toList(growable: false);

  final startAnchor = updatedPoints.first;
  final nextFixedSegments = fixedSegments
      .map(
        (segment) => FixedSegment(
          index: segment.index,
          start: <double>[
            arrow.x + (segment.start[0] - startAnchor[0]),
            arrow.y + (segment.start[1] - startAnchor[1]),
          ],
          end: <double>[
            arrow.x + (segment.end[0] - startAnchor[0]),
            arrow.y + (segment.end[1] - startAnchor[1]),
          ],
        ),
      )
      .toList(growable: false);

  final newPoints = <Point>[];
  final offset = 2 + ((startIsSpecial ?? false) ? 1 : 0);
  final endOffset = 2 + ((endIsSpecial ?? false) ? 1 : 0);
  while (newPoints.length + offset < globalUpdatedPoints.length - endOffset) {
    newPoints.add(globalUpdatedPoints[newPoints.length + offset]);
  }

  {
    final startSpecial = startIsSpecial ?? false;
    final secondPoint = _pointAt(
      globalUpdatedPoints,
      startSpecial ? 2 : 1,
      'Second and third points must exist when handling endpoint drag ($startSpecial)',
    );
    final thirdPoint = _pointAt(
      globalUpdatedPoints,
      startSpecial ? 3 : 2,
      'Second and third points must exist when handling endpoint drag ($startSpecial)',
    );

    final startIsHorizontal = isHorizontalHeading(startHeading);
    final secondIsHorizontal = isHorizontalHeading(
      vectorToHeading(thirdPoint, secondPoint),
    );

    if (hoveredStartElement != null &&
        startIsHorizontal == secondIsHorizontal) {
      final positive = _isHeadingPositive(startHeading);
      final startPadding = positive ? basePadding : -basePadding;

      newPoints.insert(0, <double>[
        !secondIsHorizontal
            ? thirdPoint[0]
            : startGlobalPoint[0] + startPadding,
        secondIsHorizontal ? thirdPoint[1] : startGlobalPoint[1] + startPadding,
      ]);
      newPoints.insert(0, <double>[
        startIsHorizontal
            ? startGlobalPoint[0] + startPadding
            : startGlobalPoint[0],
        !startIsHorizontal
            ? startGlobalPoint[1] + startPadding
            : startGlobalPoint[1],
      ]);

      if (!startSpecial) {
        startIsSpecial = true;
        for (var index = 0; index < nextFixedSegments.length; index += 1) {
          final segment = nextFixedSegments[index];
          if (segment.index > 1) {
            nextFixedSegments[index] = segment.copyWith(
              index: segment.index + 1,
            );
          }
        }
      }
    } else {
      newPoints.insert(0, <double>[
        !secondIsHorizontal ? secondPoint[0] : startGlobalPoint[0],
        secondIsHorizontal ? secondPoint[1] : startGlobalPoint[1],
      ]);
      if (startSpecial) {
        startIsSpecial = false;
        for (var index = 0; index < nextFixedSegments.length; index += 1) {
          final segment = nextFixedSegments[index];
          if (segment.index > 1) {
            nextFixedSegments[index] = segment.copyWith(
              index: segment.index - 1,
            );
          }
        }
      }
    }

    newPoints.insert(0, <double>[startGlobalPoint[0], startGlobalPoint[1]]);
  }

  {
    final endSpecial = endIsSpecial ?? false;
    final secondToLastPoint = _pointAt(
      globalUpdatedPoints,
      globalUpdatedPoints.length - (endSpecial ? 3 : 2),
      'Second and third to last points must exist when handling endpoint drag ($endSpecial)',
    );
    final thirdToLastPoint = _pointAt(
      globalUpdatedPoints,
      globalUpdatedPoints.length - (endSpecial ? 4 : 3),
      'Second and third to last points must exist when handling endpoint drag ($endSpecial)',
    );

    final endIsHorizontal = isHorizontalHeading(endHeading);
    final secondIsHorizontal = isHorizontalHeading(
      vectorToHeading(thirdToLastPoint, secondToLastPoint),
    );

    if (hoveredEndElement != null && endIsHorizontal == secondIsHorizontal) {
      final positive = _isHeadingPositive(endHeading);
      final endPadding = positive ? basePadding : -basePadding;

      newPoints.add(<double>[
        !secondIsHorizontal
            ? thirdToLastPoint[0]
            : endGlobalPoint[0] + endPadding,
        secondIsHorizontal
            ? thirdToLastPoint[1]
            : endGlobalPoint[1] + endPadding,
      ]);
      newPoints.add(<double>[
        endIsHorizontal ? endGlobalPoint[0] + endPadding : endGlobalPoint[0],
        !endIsHorizontal ? endGlobalPoint[1] + endPadding : endGlobalPoint[1],
      ]);
      if (!endSpecial) {
        endIsSpecial = true;
      }
    } else {
      newPoints.add(<double>[
        !secondIsHorizontal ? secondToLastPoint[0] : endGlobalPoint[0],
        secondIsHorizontal ? secondToLastPoint[1] : endGlobalPoint[1],
      ]);
      if (endSpecial) {
        endIsSpecial = false;
      }
    }
  }

  newPoints.add(<double>[endGlobalPoint[0], endGlobalPoint[1]]);

  final rebuiltFixedSegments = nextFixedSegments
      .where((segment) => segment.index > 0 && segment.index < newPoints.length)
      .map(
        (segment) => FixedSegment(
          index: segment.index,
          start: <double>[
            newPoints[segment.index - 1][0],
            newPoints[segment.index - 1][1],
          ],
          end: <double>[
            newPoints[segment.index][0],
            newPoints[segment.index][1],
          ],
        ),
      )
      .toList(growable: false);

  return _normalizePatchWithMetaFromGlobalPoints(
    newPoints,
    maxCoordinate,
    fixedSegments: rebuiltFixedSegments,
    startIsSpecial: startIsSpecial,
    endIsSpecial: endIsSpecial,
  );
}

bool _hasElbowUpdates(ElbowUpdatePatch updates) =>
    updates.containsKey('points') ||
    updates.containsKey('fixedSegments') ||
    updates.containsKey('startBinding') ||
    updates.containsKey('endBinding');

Map<String, dynamic> _asStringDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    final out = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String) {
        out[key] = entry.value;
      }
    }
    return out;
  }
  return <String, dynamic>{};
}

EngineContext _readEngineContext(Object? value) {
  if (value is EngineContext) {
    return value;
  }
  if (value is Map<String, dynamic>) {
    return normalizeEngineContext(value);
  }
  if (value is Map) {
    return normalizeEngineContext(_asStringDynamicMap(value));
  }
  return defaultEngineContext;
}

Point? _asPointOrNull(Object? value) {
  if (value is List && value.length >= 2) {
    final x = value[0];
    final y = value[1];
    if (x is num && y is num) {
      return <double>[x.toDouble(), y.toDouble()];
    }
  }
  return null;
}

List<Point>? _asPointListOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    return null;
  }

  final points = <Point>[];
  for (final item in value) {
    final point = _asPointOrNull(item);
    if (point != null) {
      points.add(point);
    }
  }
  return points;
}

FixedPointBinding? _asBindingOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is FixedPointBinding) {
    return value.copyWith(
      fixedPoint: <double>[value.fixedPoint[0], value.fixedPoint[1]],
    );
  }

  if (value is Map) {
    final elementId = value['elementId'];
    final mode = value['mode'];
    final fixedPoint = _asPointOrNull(value['fixedPoint']);
    if (elementId is String && mode is String && fixedPoint != null) {
      return FixedPointBinding(
        elementId: elementId,
        fixedPoint: fixedPoint,
        mode: mode,
      );
    }
  }

  return null;
}

FixedSegment? _asFixedSegmentOrNull(Object? value) {
  if (value is FixedSegment) {
    return value.copyWith(
      start: <double>[value.start[0], value.start[1]],
      end: <double>[value.end[0], value.end[1]],
    );
  }

  if (value is Map) {
    final index = value['index'];
    final start = _asPointOrNull(value['start']);
    final end = _asPointOrNull(value['end']);
    if (index is num && start != null && end != null) {
      return FixedSegment(start: start, end: end, index: index.toInt());
    }
  }

  return null;
}

List<FixedSegment>? _asFixedSegmentListOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    return null;
  }

  final segments = <FixedSegment>[];
  for (final item in value) {
    final segment = _asFixedSegmentOrNull(item);
    if (segment != null) {
      segments.add(segment);
    }
  }
  return segments;
}

_ResizeArrowData _readResizeArrowData(Object? value) {
  if (value is ArrowState) {
    return _ResizeArrowData(
      startBinding: value.startBinding,
      endBinding: value.endBinding,
      fixedSegments: value.fixedSegments,
    );
  }

  if (value is Map) {
    return _ResizeArrowData(
      startBinding: _asBindingOrNull(value['startBinding']),
      endBinding: _asBindingOrNull(value['endBinding']),
      fixedSegments: _asFixedSegmentListOrNull(value['fixedSegments']),
    );
  }

  return const _ResizeArrowData(
    startBinding: null,
    endBinding: null,
    fixedSegments: null,
  );
}

ElbowUpdatePatch _normalizeElbowUpdatePatch(ElbowUpdatePatch updates) {
  final normalized = <String, dynamic>{};

  if (updates.containsKey('points')) {
    final points = _asPointListOrNull(updates['points']);
    if (points != null) {
      normalized['points'] = points;
    }
  }

  if (updates.containsKey('fixedSegments')) {
    normalized['fixedSegments'] = _asFixedSegmentListOrNull(
      updates['fixedSegments'],
    );
  }

  if (updates.containsKey('startBinding')) {
    final value = updates['startBinding'];
    normalized['startBinding'] = value == null ? null : _asBindingOrNull(value);
  }

  if (updates.containsKey('endBinding')) {
    final value = updates['endBinding'];
    normalized['endBinding'] = value == null ? null : _asBindingOrNull(value);
  }

  return normalized;
}

ArrowPatch _updateElbowArrowPointsPort(
  ArrowState arrow,
  Map<String, BindableState> bindablesById,
  ElbowUpdatePatch updates,
  Map<String, dynamic> options,
) {
  final maxCoordinateValue = options['maxCoordinate'];
  final maxCoordinate =
      maxCoordinateValue is num &&
          maxCoordinateValue.isFinite &&
          maxCoordinateValue > 0
      ? maxCoordinateValue.toDouble()
      : defaultEngineContext.maxCoordinate;

  if (arrow.points.length < 2) {
    return <String, dynamic>{'points': updates['points'] ?? arrow.points};
  }

  final hasPointsUpdate = updates.containsKey('points');
  final hasFixedSegmentsUpdate = updates.containsKey('fixedSegments');
  final hasStartBindingUpdate = updates.containsKey('startBinding');
  final hasEndBindingUpdate = updates.containsKey('endBinding');
  final validateInvariants = options['validateInvariants'] == true;
  final isDragging = options['isDragging'] == true;
  final zoomValue = options['zoom'];
  final zoom = zoomValue is num ? zoomValue.toDouble() : 1.0;

  final nextFixedSegments = _cloneFixedSegments(
    hasFixedSegmentsUpdate
        ? _asFixedSegmentListOrNull(updates['fixedSegments'])
        : arrow.fixedSegments,
  );
  final updatedPoints = hasPointsUpdate
      ? _applyPointUpdate(arrow.points, _asPointListOrNull(updates['points']))
      : _clonePoints(arrow.points);

  if (validateInvariants) {
    _validateUpdateInvariants(arrow, updates, updatedPoints, nextFixedSegments);
  }

  final nextArrow = arrow.copyWith(
    points: updatedPoints,
    fixedSegments: nextFixedSegments,
    setFixedSegments: true,
    startBinding: hasStartBindingUpdate
        ? _asBindingOrNull(updates['startBinding'])
        : arrow.startBinding,
    setStartBinding: hasStartBindingUpdate,
    endBinding: hasEndBindingUpdate
        ? _asBindingOrNull(updates['endBinding'])
        : arrow.endBinding,
    setEndBinding: hasEndBindingUpdate,
  );
  final startBinding = nextArrow.startBinding;
  final endBinding = nextArrow.endBinding;
  final startElement = startBinding == null
      ? null
      : bindablesById[startBinding.elementId];
  final endElement = endBinding == null
      ? null
      : bindablesById[endBinding.elementId];
  final areUpdatedPointsValid = validateElbowPoints(updatedPoints);

  final hasRestUpdates = hasPointsUpdate || hasFixedSegmentsUpdate;
  if (((startBinding != null &&
              startElement == null &&
              areUpdatedPointsValid) ||
          (endBinding != null && endElement == null && areUpdatedPointsValid) ||
          ((startBinding != null || endBinding != null) &&
              bindablesById.isEmpty &&
              areUpdatedPointsValid) ||
          (!hasRestUpdates &&
              (startElement?.id != startBinding?.elementId ||
                  endElement?.id != endBinding?.elementId))) &&
      areUpdatedPointsValid) {
    return _normalizePatchWithMetaFromLocalPoints(
      arrow,
      updatedPoints,
      maxCoordinate,
      fixedSegments: arrow.fixedSegments,
      startIsSpecial: arrow.startIsSpecial,
      endIsSpecial: arrow.endIsSpecial,
    );
  }

  if (!hasPointsUpdate &&
      !hasFixedSegmentsUpdate &&
      !hasStartBindingUpdate &&
      !hasEndBindingUpdate) {
    return _handleSegmentRenormalization(
      arrow,
      bindablesById,
      validateInvariants,
      maxCoordinate,
      zoom: zoom,
    );
  }

  final pointsUpdate = _asPointListOrNull(updates['points']);
  final hasNoopPointsUpdate = (pointsUpdate ?? const <Point>[]).indexed.every((
    entry,
  ) {
    final index = entry.$1;
    final point = entry.$2;
    return pointsEqual(
      point,
      index < arrow.points.length ? arrow.points[index] : <double>[0, 0],
    );
  });

  if ((hasPointsUpdate ||
          hasFixedSegmentsUpdate ||
          hasStartBindingUpdate ||
          hasEndBindingUpdate) &&
      updates['startBinding'] == arrow.startBinding &&
      updates['endBinding'] == arrow.endBinding &&
      hasNoopPointsUpdate &&
      areUpdatedPointsValid) {
    return const <String, dynamic>{};
  }

  if (hasPointsUpdate && hasFixedSegmentsUpdate) {
    return <String, dynamic>{...updates};
  }

  if (isDragging && hasPointsUpdate) {
    return _normalizePatchWithMetaFromLocalPoints(
      nextArrow,
      nextArrow.points,
      maxCoordinate,
      fixedSegments: nextArrow.fixedSegments,
      startIsSpecial: nextArrow.startIsSpecial,
      endIsSpecial: nextArrow.endIsSpecial,
    );
  }

  final fixedSegments = nextArrow.fixedSegments;
  if (fixedSegments == null || fixedSegments.isEmpty) {
    return _routeAndNormalizeElbowPatch(
      arrow: nextArrow,
      bindablesById: bindablesById,
      fixedSegments: null,
      zoom: zoom,
      maxCoordinate: maxCoordinate,
      validateInvariants: validateInvariants,
      startIsSpecial: null,
      endIsSpecial: null,
    );
  }

  if ((arrow.fixedSegments?.length ?? 0) > fixedSegments.length) {
    return _routeAndNormalizeElbowPatch(
      arrow: nextArrow,
      bindablesById: bindablesById,
      fixedSegments: fixedSegments,
      zoom: zoom,
      maxCoordinate: maxCoordinate,
      validateInvariants: validateInvariants,
      startIsSpecial: false,
      endIsSpecial: false,
    );
  }

  if (!hasPointsUpdate) {
    return _routeAndNormalizeElbowPatch(
      arrow: nextArrow,
      bindablesById: bindablesById,
      fixedSegments: fixedSegments,
      zoom: zoom,
      maxCoordinate: maxCoordinate,
      validateInvariants: validateInvariants,
      startIsSpecial: false,
      endIsSpecial: false,
    );
  }

  final startEndpoint = _computeEndpointAndHeading(
    nextArrow,
    bindablesById,
    'start',
    zoom: zoom,
  );
  final endEndpoint = _computeEndpointAndHeading(
    nextArrow,
    bindablesById,
    'end',
    zoom: zoom,
  );
  return _handleEndpointDrag(
    arrow: nextArrow,
    updatedPoints: updatedPoints,
    fixedSegments: fixedSegments,
    startHeading: startEndpoint.heading,
    endHeading: endEndpoint.heading,
    startGlobalPoint: startEndpoint.point,
    endGlobalPoint: endEndpoint.point,
    hoveredStartElement: startElement,
    hoveredEndElement: endElement,
    maxCoordinate: maxCoordinate,
  );
}

ArrowPatch updateElbowArrowPatch(UpdateElbowArrowInput input) {
  final arrow = input['arrow'] as ArrowState;
  final updates = _normalizeElbowUpdatePatch(
    _asStringDynamicMap(input['updates']),
  );
  final bindables = (input['bindables'] as List).whereType<BindableState>();
  final context = _readEngineContext(input['context']);
  final options = _asStringDynamicMap(input['options']);

  final bindablesById = <String, BindableState>{
    for (final bindable in bindables) bindable.id: bindable,
  };

  final patch = _updateElbowArrowPointsPort(
    arrow,
    bindablesById,
    updates,
    <String, dynamic>{
      'isDragging': options['isDragging'] == true,
      'zoom': context.zoom,
      if (options.containsKey('validateInvariants'))
        'validateInvariants': options['validateInvariants'] == true,
      'maxCoordinate': context.maxCoordinate,
    },
  );

  if (!_hasElbowUpdates(updates)) {
    return patch;
  }

  return <String, dynamic>{
    ...patch,
    if (!patch.containsKey('fixedSegments') &&
        updates.containsKey('fixedSegments'))
      'fixedSegments': updates['fixedSegments'],
    if (updates.containsKey('startBinding'))
      'startBinding': updates['startBinding'],
    if (updates.containsKey('endBinding')) 'endBinding': updates['endBinding'],
  };
}

ArrowPatch _recomputeElbowFallbackPatch(RecomputeElbowInput input) {
  final arrow = input['arrow'] as ArrowState;
  final bindables = (input['bindables'] as List).whereType<BindableState>();
  final context = _readEngineContext(input['context']);

  final bindablesById = <String, BindableState>{
    for (final bindable in bindables) bindable.id: bindable,
  };

  final start = _computeEndpointAndHeading(
    arrow,
    bindablesById,
    'start',
    zoom: context.zoom,
  );
  final end = _computeEndpointAndHeading(
    arrow,
    bindablesById,
    'end',
    zoom: context.zoom,
  );

  final orthogonal = _ensureOrthogonal(<Point>[start.point, end.point]);
  final withFixedSegments = _applyFixedSegments(orthogonal, arrow);
  final patch = normalizeArrowFromGlobalPoints(
    withFixedSegments,
    context.maxCoordinate,
  );

  return <String, dynamic>{
    'x': patch.x,
    'y': patch.y,
    'points': patch.points,
    'width': patch.width,
    'height': patch.height,
  };
}

ArrowPatch recomputeElbowPatch(RecomputeElbowInput input) {
  final arrow = input['arrow'] as ArrowState;
  final bindables = (input['bindables'] as List).whereType<BindableState>();
  final context = _readEngineContext(input['context']);
  final bindablesById = <String, BindableState>{
    for (final bindable in bindables) bindable.id: bindable,
  };

  final patch = _updateElbowArrowPointsPort(
    arrow,
    bindablesById,
    const <String, dynamic>{},
    <String, dynamic>{
      'isDragging': false,
      'zoom': context.zoom,
      'maxCoordinate': context.maxCoordinate,
    },
  );

  final resolvedX = patch['x'] is num
      ? (patch['x'] as num).toDouble()
      : arrow.x;
  final resolvedY = patch['y'] is num
      ? (patch['y'] as num).toDouble()
      : arrow.y;
  final resolvedPoints = _asPointListOrNull(patch['points']) ?? arrow.points;

  final isOutOfBounds =
      resolvedX.abs() > context.maxCoordinate ||
      resolvedY.abs() > context.maxCoordinate;
  final hasInvalidOrthogonalPath =
      resolvedPoints.length >= 2 && !validateElbowPoints(resolvedPoints);

  if (isOutOfBounds || hasInvalidOrthogonalPath) {
    return _recomputeElbowFallbackPatch(input);
  }

  return patch;
}

ArrowPatch moveFixedSegment({
  required ArrowState arrow,
  required int segmentIndex,
  required Point delta,
}) {
  final fixedSegments = arrow.fixedSegments;
  if (fixedSegments == null) {
    return <String, dynamic>{'fixedSegments': null};
  }

  final next = fixedSegments
      .map((segment) {
        if (segment.index != segmentIndex) {
          return segment;
        }
        return segment.copyWith(
          start: <double>[
            segment.start[0] + delta[0],
            segment.start[1] + delta[1],
          ],
          end: <double>[segment.end[0] + delta[0], segment.end[1] + delta[1]],
        );
      })
      .toList(growable: false);

  return <String, dynamic>{'fixedSegments': next};
}

MoveFixedSegmentToPointResult moveFixedSegmentToPoint(
  MoveFixedSegmentToPointInput input,
) {
  final arrow = input['arrow'] as ArrowState;
  final segmentIndexValue = input['segmentIndex'];
  final pointer =
      _asPointOrNull(input['pointer']) ?? <double>[arrow.x, arrow.y];
  final segmentIndex = segmentIndexValue is num
      ? segmentIndexValue.toInt()
      : -1;

  if (segmentIndex <= 0 || segmentIndex >= arrow.points.length) {
    return const MoveFixedSegmentToPointResult(
      patch: <String, dynamic>{},
      activeSegmentIndex: null,
      activeSegmentMidPoint: null,
    );
  }

  final isHorizontal = isHorizontalHeading(
    vectorToHeading(arrow.points[segmentIndex - 1], arrow.points[segmentIndex]),
  );
  final localPointer = <double>[pointer[0] - arrow.x, pointer[1] - arrow.y];

  final segmentsByIndex = <int, FixedSegment>{};
  for (final segment in arrow.fixedSegments ?? const <FixedSegment>[]) {
    segmentsByIndex[segment.index] = segment;
  }

  final startX = isHorizontal
      ? arrow.points[segmentIndex - 1][0]
      : localPointer[0];
  final startY = isHorizontal
      ? localPointer[1]
      : arrow.points[segmentIndex - 1][1];
  final endX = isHorizontal ? arrow.points[segmentIndex][0] : localPointer[0];
  final endY = isHorizontal ? localPointer[1] : arrow.points[segmentIndex][1];

  segmentsByIndex[segmentIndex] = FixedSegment(
    index: segmentIndex,
    start: <double>[startX, startY],
    end: <double>[endX, endY],
  );

  final fixedSegments = segmentsByIndex.values.toList(growable: false)
    ..sort((left, right) => left.index.compareTo(right.index));

  FixedSegment? activeSegment;
  for (final segment in fixedSegments) {
    if (segment.index == segmentIndex) {
      activeSegment = segment;
      break;
    }
  }

  return MoveFixedSegmentToPointResult(
    patch: <String, dynamic>{
      'fixedSegments': fixedSegments.isNotEmpty ? fixedSegments : null,
    },
    activeSegmentIndex: activeSegment?.index,
    activeSegmentMidPoint: activeSegment == null
        ? null
        : <double>[
            arrow.x + (activeSegment.start[0] + activeSegment.end[0]) / 2,
            arrow.y + (activeSegment.start[1] + activeSegment.end[1]) / 2,
          ],
  );
}

ArrowPatch releaseFixedSegment({
  required ArrowState arrow,
  required int segmentIndex,
}) {
  final next = (arrow.fixedSegments ?? const <FixedSegment>[])
      .where((segment) => segment.index != segmentIndex)
      .toList(growable: false);
  return <String, dynamic>{'fixedSegments': next.isNotEmpty ? next : null};
}

bool validateElbowPoints(
  List<Point> points, [
  double tolerance = _dedupThreshold,
]) => points
    .asMap()
    .entries
    .skip(1)
    .every(
      (entry) =>
          (entry.value[0] - points[entry.key - 1][0]).abs() < tolerance ||
          (entry.value[1] - points[entry.key - 1][1]).abs() < tolerance,
    );

List<String> validateElbowInvariant(ArrowState arrow) {
  final issues = <String>[];
  if (!arrow.elbowed) {
    return issues;
  }

  if (arrow.points.length < 2) {
    issues.add('elbow arrow must contain at least two points');
  }
  if (!isOrthogonalPath(arrow.points)) {
    issues.add('elbow arrow path must be orthogonal');
  }

  final fixedSegments = arrow.fixedSegments;
  if (fixedSegments != null) {
    for (final fixed in fixedSegments) {
      if (fixed.index <= 0 || fixed.index >= arrow.points.length) {
        issues.add(
          'fixed segment index ${fixed.index} is outside points range',
        );
      }
    }
  }

  return issues;
}

Point _mirrorFixedPoint(Point fixedPoint, bool flipX, bool flipY) => <double>[
  if (flipX) -fixedPoint[0] + 1 else fixedPoint[0],
  if (flipY) -fixedPoint[1] + 1 else fixedPoint[1],
];

ArrowPatch computeElbowResizePatch(ComputeElbowResizePatchInput input) {
  final patch = <String, dynamic>{};
  final arrow = _readResizeArrowData(input['arrow']);
  final points = _asPointListOrNull(input['points']);
  final flipX = input['flipX'] == true;
  final flipY = input['flipY'] == true;

  final startBinding = arrow.startBinding;
  if (startBinding != null) {
    patch['startBinding'] = startBinding.copyWith(
      fixedPoint: _mirrorFixedPoint(startBinding.fixedPoint, flipX, flipY),
    );
  }

  final endBinding = arrow.endBinding;
  if (endBinding != null) {
    patch['endBinding'] = endBinding.copyWith(
      fixedPoint: _mirrorFixedPoint(endBinding.fixedPoint, flipX, flipY),
    );
  }

  final fixedSegments = arrow.fixedSegments;
  if (fixedSegments != null && points != null) {
    patch['fixedSegments'] = fixedSegments
        .map((segment) {
          final startIndex = segment.index - 1;
          final endIndex = segment.index;
          final start = startIndex >= 0 && startIndex < points.length
              ? points[startIndex]
              : null;
          final end = endIndex >= 0 && endIndex < points.length
              ? points[endIndex]
              : null;

          if (start == null || end == null) {
            return segment;
          }
          return segment.copyWith(start: start, end: end);
        })
        .toList(growable: false);
  }

  return patch;
}

ArrowPatch updateElbowArrowPoints(Map<String, dynamic> input) =>
    input.containsKey('updates')
    ? updateElbowArrowPatch(input)
    : recomputeElbowPatch(input);
