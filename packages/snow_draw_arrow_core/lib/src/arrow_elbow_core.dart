import 'dart:math' as math;

import 'arrow_binding_core.dart';
import 'arrow_geom.dart';
import 'arrow_hit_test.dart';
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
// ignore: constant_identifier_names
const double BASE_PADDING = basePadding;

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
    point[0] > bounds[0] &&
    point[0] < bounds[2] &&
    point[1] > bounds[1] &&
    point[1] < bounds[3];

bool _segmentIntersectsBounds(Point a, Point b, _Bounds bounds) {
  const epsilon = 1e-9;
  final inner = <double>[
    bounds[0] + epsilon,
    bounds[1] + epsilon,
    bounds[2] - epsilon,
    bounds[3] - epsilon,
  ];

  if (inner[0] >= inner[2] || inner[1] >= inner[3]) {
    return false;
  }

  final vertical = (a[0] - b[0]).abs() <= _dedupThreshold;
  if (vertical) {
    final x = (a[0] + b[0]) / 2;
    if (x < inner[0] || x > inner[2]) {
      return false;
    }
    return _overlapLength(
          math.min(a[1], b[1]),
          math.max(a[1], b[1]),
          inner[1],
          inner[3],
        ) >
        epsilon;
  }

  final horizontal = (a[1] - b[1]).abs() <= _dedupThreshold;
  if (!horizontal) {
    return false;
  }

  final y = (a[1] + b[1]) / 2;
  if (y < inner[1] || y > inner[3]) {
    return false;
  }
  return _overlapLength(
        math.min(a[0], b[0]),
        math.max(a[0], b[0]),
        inner[0],
        inner[2],
      ) >
      epsilon;
}

double _overlapLength(double minA, double maxA, double minB, double maxB) =>
    math.min(maxA, maxB) - math.max(minA, minB);

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

_Bounds _commonAabb(List<_Bounds> aabbs) => <double>[
  aabbs.map((aabb) => aabb[0]).reduce(math.min),
  aabbs.map((aabb) => aabb[1]).reduce(math.min),
  aabbs.map((aabb) => aabb[2]).reduce(math.max),
  aabbs.map((aabb) => aabb[3]).reduce(math.max),
];

_Bounds _aabbForBindableWithOffset(
  BindableState bindable, [
  List<double>? offset,
]) {
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );
  final corners = <Point>[
    <double>[bindable.x, bindable.y],
    <double>[bindable.x + bindable.width, bindable.y],
    <double>[bindable.x + bindable.width, bindable.y + bindable.height],
    <double>[bindable.x, bindable.y + bindable.height],
  ];
  final rotated = corners
      .map((corner) => rotatePoint(corner, bindableCenter, bindable.angle))
      .toList(growable: false);

  final bounds = <double>[
    rotated.map((point) => point[0]).reduce(math.min),
    rotated.map((point) => point[1]).reduce(math.min),
    rotated.map((point) => point[0]).reduce(math.max),
    rotated.map((point) => point[1]).reduce(math.max),
  ];

  if (offset == null || offset.length < 4) {
    return bounds;
  }
  final topOffset = offset[0];
  final rightOffset = offset[1];
  final downOffset = offset[2];
  final leftOffset = offset[3];
  return <double>[
    bounds[0] - leftOffset,
    bounds[1] - topOffset,
    bounds[2] + rightOffset,
    bounds[3] + downOffset,
  ];
}

List<double> _offsetFromHeading(Heading heading, double head, double side) {
  switch (heading) {
    case 'up':
      return <double>[head, side, side, side];
    case 'right':
      return <double>[side, head, side, side];
    case 'down':
      return <double>[side, side, head, side];
    case 'left':
      return <double>[side, side, side, head];
  }
  return <double>[side, side, side, side];
}

double _vectorCross(Point a, Point b) => a[0] * b[1] - a[1] * b[0];

List<_Bounds> _generateDynamicAABBs({
  required _Bounds a,
  required _Bounds b,
  required _Bounds common,
  List<double>? startDifference,
  List<double>? endDifference,
  bool disableSideHack = false,
  _Bounds? startElementBounds,
  _Bounds? endElementBounds,
}) {
  final startEl = startElementBounds ?? a;
  final endEl = endElementBounds ?? b;
  final start = startDifference ?? const <double>[0, 0, 0, 0];
  final end = endDifference ?? const <double>[0, 0, 0, 0];
  final startUp = start[0];
  final startRight = start[1];
  final startDown = start[2];
  final startLeft = start[3];
  final endUp = end[0];
  final endRight = end[1];
  final endDown = end[2];
  final endLeft = end[3];

  final first = <double>[
    a[0] > b[2]
        ? (a[1] > b[3] || a[3] < b[1]
              ? math.min((startEl[0] + endEl[2]) / 2, a[0] - startLeft)
              : (startEl[0] + endEl[2]) / 2)
        : (a[0] > b[0] ? a[0] - startLeft : common[0] - startLeft),
    a[1] > b[3]
        ? (a[0] > b[2] || a[2] < b[0]
              ? math.min((startEl[1] + endEl[3]) / 2, a[1] - startUp)
              : (startEl[1] + endEl[3]) / 2)
        : (a[1] > b[1] ? a[1] - startUp : common[1] - startUp),
    a[2] < b[0]
        ? (a[1] > b[3] || a[3] < b[1]
              ? math.max((startEl[2] + endEl[0]) / 2, a[2] + startRight)
              : (startEl[2] + endEl[0]) / 2)
        : (a[2] < b[2] ? a[2] + startRight : common[2] + startRight),
    a[3] < b[1]
        ? (a[0] > b[2] || a[2] < b[0]
              ? math.max((startEl[3] + endEl[1]) / 2, a[3] + startDown)
              : (startEl[3] + endEl[1]) / 2)
        : (a[3] < b[3] ? a[3] + startDown : common[3] + startDown),
  ];

  final second = <double>[
    b[0] > a[2]
        ? (b[1] > a[3] || b[3] < a[1]
              ? math.min((endEl[0] + startEl[2]) / 2, b[0] - endLeft)
              : (endEl[0] + startEl[2]) / 2)
        : (b[0] > a[0] ? b[0] - endLeft : common[0] - endLeft),
    b[1] > a[3]
        ? (b[0] > a[2] || b[2] < a[0]
              ? math.min((endEl[1] + startEl[3]) / 2, b[1] - endUp)
              : (endEl[1] + startEl[3]) / 2)
        : (b[1] > a[1] ? b[1] - endUp : common[1] - endUp),
    b[2] < a[0]
        ? (b[1] > a[3] || b[3] < a[1]
              ? math.max((endEl[2] + startEl[0]) / 2, b[2] + endRight)
              : (endEl[2] + startEl[0]) / 2)
        : (b[2] < a[2] ? b[2] + endRight : common[2] + endRight),
    b[3] < a[1]
        ? (b[0] > a[2] || b[2] < a[0]
              ? math.max((endEl[3] + startEl[1]) / 2, b[3] + endDown)
              : (endEl[3] + startEl[1]) / 2)
        : (b[3] < a[3] ? b[3] + endDown : common[3] + endDown),
  ];

  final c = _commonAabb(<_Bounds>[first, second]);
  if (!disableSideHack &&
      first[2] - first[0] + second[2] - second[0] > c[2] - c[0] + 1e-11 &&
      first[3] - first[1] + second[3] - second[1] > c[3] - c[1] + 1e-11) {
    final endCenterX = (second[0] + second[2]) / 2;
    final endCenterY = (second[1] + second[3]) / 2;
    if (b[0] > a[2] && a[1] > b[3]) {
      final cX = first[2] + (second[0] - first[2]) / 2;
      final cY = second[3] + (first[1] - second[3]) / 2;
      if (_vectorCross(
            <double>[a[2] - endCenterX, a[1] - endCenterY],
            <double>[a[0] - endCenterX, a[3] - endCenterY],
          ) >
          0) {
        return <_Bounds>[
          <double>[first[0], first[1], cX, first[3]],
          <double>[cX, second[1], second[2], second[3]],
        ];
      }
      return <_Bounds>[
        <double>[first[0], cY, first[2], first[3]],
        <double>[second[0], second[1], second[2], cY],
      ];
    }

    if (a[2] < b[0] && a[3] < b[1]) {
      final cX = first[2] + (second[0] - first[2]) / 2;
      final cY = first[3] + (second[1] - first[3]) / 2;
      if (_vectorCross(
            <double>[a[0] - endCenterX, a[1] - endCenterY],
            <double>[a[2] - endCenterX, a[3] - endCenterY],
          ) >
          0) {
        return <_Bounds>[
          <double>[first[0], first[1], first[2], cY],
          <double>[second[0], cY, second[2], second[3]],
        ];
      }
      return <_Bounds>[
        <double>[first[0], first[1], cX, first[3]],
        <double>[cX, second[1], second[2], second[3]],
      ];
    }

    if (a[0] > b[2] && a[3] < b[1]) {
      final cX = second[2] + (first[0] - second[2]) / 2;
      final cY = first[3] + (second[1] - first[3]) / 2;
      if (_vectorCross(
            <double>[a[2] - endCenterX, a[1] - endCenterY],
            <double>[a[0] - endCenterX, a[3] - endCenterY],
          ) >
          0) {
        return <_Bounds>[
          <double>[cX, first[1], first[2], first[3]],
          <double>[second[0], second[1], cX, second[3]],
        ];
      }
      return <_Bounds>[
        <double>[first[0], first[1], first[2], cY],
        <double>[second[0], cY, second[2], second[3]],
      ];
    }

    if (a[0] > b[2] && a[1] > b[3]) {
      final cX = second[2] + (first[0] - second[2]) / 2;
      final cY = second[3] + (first[1] - second[3]) / 2;
      if (_vectorCross(
            <double>[a[0] - endCenterX, a[1] - endCenterY],
            <double>[a[2] - endCenterX, a[3] - endCenterY],
          ) >
          0) {
        return <_Bounds>[
          <double>[cX, first[1], first[2], first[3]],
          <double>[second[0], second[1], cX, second[3]],
        ];
      }
      return <_Bounds>[
        <double>[first[0], cY, first[2], first[3]],
        <double>[second[0], second[1], second[2], cY],
      ];
    }
  }

  return <_Bounds>[first, second];
}

Point _getDonglePosition(_Bounds bounds, Heading heading, Point point) {
  switch (heading) {
    case 'up':
      return <double>[point[0], bounds[1]];
    case 'right':
      return <double>[bounds[2], point[1]];
    case 'down':
      return <double>[point[0], bounds[3]];
    case 'left':
      return <double>[bounds[0], point[1]];
  }
  return <double>[point[0], point[1]];
}

_Grid _makeGrid(
  List<_Bounds> obstacles,
  Point start,
  Heading startHeading,
  Point end,
  Heading endHeading,
  _Bounds common,
) {
  final horizontal = <double>{};
  final vertical = <double>{};

  if (startHeading == 'left' || startHeading == 'right') {
    vertical.add(start[1]);
  } else {
    horizontal.add(start[0]);
  }

  if (endHeading == 'left' || endHeading == 'right') {
    vertical.add(end[1]);
  } else {
    horizontal.add(end[0]);
  }

  for (final obstacle in obstacles) {
    horizontal
      ..add(obstacle[0])
      ..add(obstacle[2]);
    vertical
      ..add(obstacle[1])
      ..add(obstacle[3]);
  }

  horizontal
    ..add(common[0])
    ..add(common[2]);
  vertical
    ..add(common[1])
    ..add(common[3]);

  final sortedX = horizontal.toList(growable: false)..sort();
  final sortedY = vertical.toList(growable: false)..sort();
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

List<_GridNode?> _neighborsOf(_GridNode node, _Grid grid) {
  _GridNode? at(int col, int row) {
    if (col < 0 || row < 0 || col >= grid.cols || row >= grid.rows) {
      return null;
    }
    return grid.nodes[row * grid.cols + col];
  }

  return <_GridNode?>[
    at(node.col, node.row - 1),
    at(node.col + 1, node.row),
    at(node.col, node.row + 1),
    at(node.col - 1, node.row),
  ];
}

_GridNode? _pointToGridNode(Point point, _Grid grid) =>
    grid.byCoord['${point[0]}:${point[1]}'];

Heading _neighborIndexToHeading(int index) {
  switch (index) {
    case 0:
      return 'up';
    case 1:
      return 'right';
    case 2:
      return 'down';
  }
  return 'left';
}

int _estimateSegmentCount(
  _GridNode start,
  _GridNode end,
  Heading startHeading,
  Heading endHeading,
) {
  if (endHeading == 'right') {
    switch (startHeading) {
      case 'right':
        if (start.x >= end.x) {
          return 4;
        }
        if (start.y == end.y) {
          return 0;
        }
        return 2;
      case 'up':
        if (start.y > end.y && start.x < end.x) {
          return 1;
        }
        return 3;
      case 'down':
        if (start.y < end.y && start.x < end.x) {
          return 1;
        }
        return 3;
      case 'left':
        if (start.y == end.y) {
          return 4;
        }
        return 2;
    }
  } else if (endHeading == 'left') {
    switch (startHeading) {
      case 'right':
        if (start.y == end.y) {
          return 4;
        }
        return 2;
      case 'up':
        if (start.y > end.y && start.x > end.x) {
          return 1;
        }
        return 3;
      case 'down':
        if (start.y < end.y && start.x > end.x) {
          return 1;
        }
        return 3;
      case 'left':
        if (start.x <= end.x) {
          return 4;
        }
        if (start.y == end.y) {
          return 0;
        }
        return 2;
    }
  } else if (endHeading == 'up') {
    switch (startHeading) {
      case 'right':
        if (start.y > end.y && start.x < end.x) {
          return 1;
        }
        return 3;
      case 'up':
        if (start.y >= end.y) {
          return 4;
        }
        if (start.x == end.x) {
          return 0;
        }
        return 2;
      case 'down':
        if (start.x == end.x) {
          return 4;
        }
        return 2;
      case 'left':
        if (start.y > end.y && start.x > end.x) {
          return 1;
        }
        return 3;
    }
  } else if (endHeading == 'down') {
    switch (startHeading) {
      case 'right':
        if (start.y < end.y && start.x < end.x) {
          return 1;
        }
        return 3;
      case 'up':
        if (start.x == end.x) {
          return 4;
        }
        return 2;
      case 'down':
        if (start.y <= end.y) {
          return 4;
        }
        if (start.x == end.x) {
          return 0;
        }
        return 2;
      case 'left':
        if (start.y < end.y && start.x > end.x) {
          return 1;
        }
        return 3;
    }
  }
  return 0;
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
  Set<String> closedNodeCoords,
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
    1.0,
    manhattan(<double>[start.x, start.y], <double>[end.x, end.y]),
  );
  final bendPenaltySquared = math.pow(bendMultiplier, 2).toDouble();
  final bendPenaltyCubed = math.pow(bendMultiplier, 3).toDouble();

  while (open.isNotEmpty) {
    open.sort((left, right) => left.f.compareTo(right.f));
    final current = open.removeAt(0);

    if (current.node.x == end.x && current.node.y == end.y) {
      return _reconstructPath(current.key, visited);
    }

    final candidates = _neighborsOf(current.node, grid);
    for (var index = 0; index < candidates.length; index += 1) {
      final candidate = candidates[index];
      if (candidate == null) {
        continue;
      }
      final candidateCoord = '${candidate.x}:${candidate.y}';
      if (closedNodeCoords.contains(candidateCoord) &&
          !(candidate.col == end.col && candidate.row == end.row)) {
        continue;
      }

      final neighborHeading = _neighborIndexToHeading(index);
      final reverse = reverseHeading(current.heading);
      final neighborIsReverseRoute =
          neighborHeading == reverse ||
          (candidate.col == start.col &&
              candidate.row == start.row &&
              neighborHeading == startHeading) ||
          (candidate.col == end.col &&
              candidate.row == end.row &&
              neighborHeading == endHeading);
      if (neighborIsReverseRoute) {
        continue;
      }

      final neighborHalfPoint = <double>[
        (candidate.x + current.node.x) / 2,
        (candidate.y + current.node.y) / 2,
      ];
      final blocked = obstacles.any(
        (obstacle) => _pointInBounds(neighborHalfPoint, obstacle),
      );
      if (blocked) {
        continue;
      }

      final directionChanged = current.heading != neighborHeading;
      final g =
          current.g +
          manhattan(
            <double>[current.node.x, current.node.y],
            <double>[candidate.x, candidate.y],
          ) +
          (directionChanged ? bendPenaltyCubed : 0);
      final estBendCount = _estimateSegmentCount(
        candidate,
        end,
        neighborHeading,
        endHeading,
      );
      final h =
          manhattan(
            <double>[candidate.x, candidate.y],
            <double>[end.x, end.y],
          ) +
          estBendCount * bendPenaltySquared;
      final f = g + h;

      final key = _keyForState(candidate, neighborHeading);
      final existing = visited[key];
      if (existing != null && existing.g <= g) {
        continue;
      }

      final nextState = _QueueNode(
        key: key,
        node: candidate,
        heading: neighborHeading,
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

List<Point> _getElbowArrowCornerPoints(List<Point> points) {
  if (points.length <= 1) {
    return points
        .map((point) => <double>[point[0], point[1]])
        .toList(growable: false);
  }

  var previousHorizontal =
      (points[0][1] - points[1][1]).abs() < (points[0][0] - points[1][0]).abs();
  final cornerPoints = <Point>[];
  for (var index = 0; index < points.length; index += 1) {
    final point = points[index];
    if (index == 0 || index == points.length - 1) {
      cornerPoints.add(<double>[point[0], point[1]]);
      continue;
    }

    final next = points[index + 1];
    final nextHorizontal =
        (point[1] - next[1]).abs() < (point[0] - next[0]).abs();
    if (previousHorizontal == nextHorizontal) {
      previousHorizontal = nextHorizontal;
      continue;
    }
    previousHorizontal = nextHorizontal;
    cornerPoints.add(<double>[point[0], point[1]]);
  }
  return cornerPoints;
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

Heading _getBindPointHeading({
  required Point point,
  required Point otherPoint,
  required BindableState? hoveredElement,
  required Point origPoint,
  double? zoom,
}) {
  if (hoveredElement == null) {
    return vectorToHeading(point, otherPoint);
  }

  final distanceAtBindPoint = distanceToBindableOutline(point, hoveredElement);
  final bindPointAabb = _aabbForBindableWithOffset(hoveredElement, <double>[
    distanceAtBindPoint,
    distanceAtBindPoint,
    distanceAtBindPoint,
    distanceAtBindPoint,
  ]);

  return getHeadingForElbowSnap(
    point: point,
    otherPoint: otherPoint,
    bindable: hoveredElement,
    aabb: bindPointAabb,
    originPoint: origPoint,
    zoom: zoom,
  );
}

_EndpointAndHeading _computeEndpointAndHeading(
  ArrowState arrow,
  Map<String, BindableState> bindablesById,
  String side, {
  double? zoom,
}) {
  final isStart = side == 'start';
  final binding = isStart ? arrow.startBinding : arrow.endBinding;
  final oppositeBinding = isStart ? arrow.endBinding : arrow.startBinding;
  final originPoint = getPointAtIndexGlobal(arrow, isStart ? 0 : -1);

  final bindable = binding == null ? null : bindablesById[binding.elementId];
  final point = bindable == null || binding == null
      ? originPoint
      : getGlobalFixedPoint(binding, bindable);

  final oppositeBindable = oppositeBinding == null
      ? null
      : bindablesById[oppositeBinding.elementId];
  final otherPoint = oppositeBindable == null || oppositeBinding == null
      ? getPointAtIndexGlobal(arrow, isStart ? -1 : 0)
      : getGlobalFixedPoint(oppositeBinding, oppositeBindable);

  if (bindable == null) {
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

  return _EndpointAndHeading(
    point: point,
    heading: _getBindPointHeading(
      point: point,
      otherPoint: otherPoint,
      hoveredElement: bindable,
      origPoint: originPoint,
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
  List<Point> _points,
) {
  if (fixedSegments == null || fixedSegments.isEmpty) {
    return null;
  }
  return fixedSegments
      .map(
        (segment) => FixedSegment(
          index: segment.index,
          start: <double>[segment.start[0], segment.start[1]],
          end: <double>[segment.end[0], segment.end[1]],
        ),
      )
      .toList(growable: false);
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
  final startBinding = routeArrow.startBinding;
  final endBinding = routeArrow.endBinding;
  final hoveredStartElement = startBinding == null
      ? null
      : bindablesById[startBinding.elementId];
  final hoveredEndElement = endBinding == null
      ? null
      : bindablesById[endBinding.elementId];

  final origStartGlobalPoint = getPointAtIndexGlobal(routeArrow, 0);
  final origEndGlobalPoint = getPointAtIndexGlobal(routeArrow, -1);
  final startGlobalPoint = hoveredStartElement == null || startBinding == null
      ? origStartGlobalPoint
      : getGlobalFixedPoint(startBinding, hoveredStartElement);
  final endGlobalPoint = hoveredEndElement == null || endBinding == null
      ? origEndGlobalPoint
      : getGlobalFixedPoint(endBinding, hoveredEndElement);

  final startHeading = _getBindPointHeading(
    point: startGlobalPoint,
    otherPoint: endGlobalPoint,
    hoveredElement: hoveredStartElement,
    origPoint: origStartGlobalPoint,
    zoom: zoom,
  );
  final endHeading = _getBindPointHeading(
    point: endGlobalPoint,
    otherPoint: startGlobalPoint,
    hoveredElement: hoveredEndElement,
    origPoint: origEndGlobalPoint,
    zoom: zoom,
  );

  final startPointBounds = <double>[
    startGlobalPoint[0] - 2,
    startGlobalPoint[1] - 2,
    startGlobalPoint[0] + 2,
    startGlobalPoint[1] + 2,
  ];
  final endPointBounds = <double>[
    endGlobalPoint[0] - 2,
    endGlobalPoint[1] - 2,
    endGlobalPoint[0] + 2,
    endGlobalPoint[1] + 2,
  ];

  final startElementBounds = hoveredStartElement == null
      ? startPointBounds
      : _aabbForBindableWithOffset(
          hoveredStartElement,
          _offsetFromHeading(
            startHeading,
            (routeArrow.startArrowhead == null
                    ? getBindingGap(hoveredStartElement, true) * 2
                    : getBindingGap(hoveredStartElement, true) * 6)
                .toDouble(),
            1,
          ),
        );
  final endElementBounds = hoveredEndElement == null
      ? endPointBounds
      : _aabbForBindableWithOffset(
          hoveredEndElement,
          _offsetFromHeading(
            endHeading,
            (routeArrow.endArrowhead == null
                    ? getBindingGap(hoveredEndElement, true) * 2
                    : getBindingGap(hoveredEndElement, true) * 6)
                .toDouble(),
            1,
          ),
        );

  final boundsOverlap =
      _pointInBounds(
        startGlobalPoint,
        hoveredEndElement == null
            ? endPointBounds
            : _aabbForBindableWithOffset(
                hoveredEndElement,
                _offsetFromHeading(endHeading, BASE_PADDING, BASE_PADDING),
              ),
      ) ||
      _pointInBounds(
        endGlobalPoint,
        hoveredStartElement == null
            ? startPointBounds
            : _aabbForBindableWithOffset(
                hoveredStartElement,
                _offsetFromHeading(startHeading, BASE_PADDING, BASE_PADDING),
              ),
      );

  final commonBounds = _commonAabb(
    boundsOverlap
        ? <_Bounds>[startPointBounds, endPointBounds]
        : <_Bounds>[startElementBounds, endElementBounds],
  );
  final hasBoundElements =
      hoveredStartElement != null || hoveredEndElement != null;
  final dynamicAABBs = _generateDynamicAABBs(
    a: boundsOverlap ? startPointBounds : startElementBounds,
    b: boundsOverlap ? endPointBounds : endElementBounds,
    common: commonBounds,
    startDifference: boundsOverlap
        ? _offsetFromHeading(
            startHeading,
            hasBoundElements ? BASE_PADDING : 0,
            0,
          )
        : _offsetFromHeading(
            startHeading,
            hasBoundElements
                ? BASE_PADDING -
                      (routeArrow.startArrowhead == null
                          ? baseBindingGapElbow * 2
                          : baseBindingGapElbow * 6)
                : 0,
            BASE_PADDING,
          ),
    endDifference: boundsOverlap
        ? _offsetFromHeading(endHeading, hasBoundElements ? BASE_PADDING : 0, 0)
        : _offsetFromHeading(
            endHeading,
            hasBoundElements
                ? BASE_PADDING -
                      (routeArrow.endArrowhead == null
                          ? baseBindingGapElbow * 2
                          : baseBindingGapElbow * 6)
                : 0,
            BASE_PADDING,
          ),
    disableSideHack: boundsOverlap,
    startElementBounds: hoveredStartElement == null
        ? null
        : _aabbForBindableWithOffset(hoveredStartElement),
    endElementBounds: hoveredEndElement == null
        ? null
        : _aabbForBindableWithOffset(hoveredEndElement),
  );

  final startDonglePosition = _getDonglePosition(
    dynamicAABBs[0],
    startHeading,
    startGlobalPoint,
  );
  final endDonglePosition = _getDonglePosition(
    dynamicAABBs[1],
    endHeading,
    endGlobalPoint,
  );

  final grid = _makeGrid(
    dynamicAABBs,
    startDonglePosition,
    startHeading,
    endDonglePosition,
    endHeading,
    commonBounds,
  );

  final startDongle = _pointToGridNode(startDonglePosition, grid);
  final endDongle = _pointToGridNode(endDonglePosition, grid);
  final endNode = _pointToGridNode(endGlobalPoint, grid);
  final startNode = _pointToGridNode(startGlobalPoint, grid);
  final closedNodeCoords = <String>{
    if (endNode != null && hoveredEndElement != null)
      '${endNode.x}:${endNode.y}',
    if (startNode != null && routeArrow.startBinding != null)
      '${startNode.x}:${startNode.y}',
  };

  final dongleOverlap =
      startDongle != null &&
      endDongle != null &&
      (_pointInBounds(startDonglePosition, dynamicAABBs[1]) ||
          _pointInBounds(endDonglePosition, dynamicAABBs[0]));

  List<Point>? route;
  final routeStart = startDongle ?? startNode;
  final routeEnd = endDongle ?? endNode;
  if (routeStart != null && routeEnd != null) {
    route = _routeAStar(
      routeStart,
      routeEnd,
      startHeading,
      endHeading,
      grid,
      dongleOverlap ? const <_Bounds>[] : dynamicAABBs,
      closedNodeCoords,
    );
  }

  List<Point> routedPoints;
  if (route == null) {
    routedPoints = <Point>[
      <double>[startGlobalPoint[0], startGlobalPoint[1]],
      <double>[endGlobalPoint[0], endGlobalPoint[1]],
    ];
  } else {
    routedPoints = route
        .map((point) => <double>[point[0], point[1]])
        .toList(growable: true);
    if (startDongle != null) {
      routedPoints.insert(0, <double>[
        startGlobalPoint[0],
        startGlobalPoint[1],
      ]);
    }
    if (endDongle != null) {
      routedPoints.add(<double>[endGlobalPoint[0], endGlobalPoint[1]]);
    }
  }

  var effectiveGlobalPoints = _getElbowArrowCornerPoints(
    _removeShortSegments(routedPoints),
  );

  if (fixedSegments != null && fixedSegments.isNotEmpty) {
    final fixedApplied = _applyFixedSegments(
      effectiveGlobalPoints,
      routeArrow.copyWith(fixedSegments: fixedSegments, setFixedSegments: true),
    );
    effectiveGlobalPoints = _getElbowArrowCornerPoints(
      _removeShortSegments(fixedApplied),
    );
  }

  if (validateInvariants && !validateElbowPoints(effectiveGlobalPoints)) {
    effectiveGlobalPoints = _ensureOrthogonal(<Point>[
      <double>[startGlobalPoint[0], startGlobalPoint[1]],
      <double>[endGlobalPoint[0], endGlobalPoint[1]],
    ]);
  }

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
    final renormalizedLocalPoints = filteredPoints
        .map((point) => <double>[point[0] - arrow.x, point[1] - arrow.y])
        .toList(growable: false);
    return _routeAndNormalizeElbowPatch(
      arrow: arrow.copyWith(points: renormalizedLocalPoints),
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
  final localRebuiltFixedSegments = rebuiltFixedSegments
      .map(
        (segment) => segment.copyWith(
          start: <double>[
            segment.start[0] - startGlobalPoint[0],
            segment.start[1] - startGlobalPoint[1],
          ],
          end: <double>[
            segment.end[0] - startGlobalPoint[0],
            segment.end[1] - startGlobalPoint[1],
          ],
        ),
      )
      .toList(growable: false);

  return _normalizePatchWithMetaFromGlobalPoints(
    newPoints,
    maxCoordinate,
    fixedSegments: localRebuiltFixedSegments,
    startIsSpecial: startIsSpecial,
    endIsSpecial: endIsSpecial,
  );
}

int? _deletedFixedSegmentIndex(
  List<FixedSegment>? previous,
  List<FixedSegment> next,
) {
  final previousIndices =
      previous?.map((segment) => segment.index).toSet() ?? <int>{};
  final nextIndices = next.map((segment) => segment.index).toSet();
  for (final index in previousIndices) {
    if (!nextIndices.contains(index)) {
      return index;
    }
  }
  return null;
}

int? _activelyModifiedFixedSegmentPosition(
  List<FixedSegment>? previous,
  List<FixedSegment> next,
) {
  if (next.isEmpty) {
    return null;
  }
  if (previous == null || previous.isEmpty) {
    return 0;
  }
  for (var index = 0; index < next.length; index += 1) {
    final current = next[index];
    final prevIndex = previous.indexWhere(
      (segment) => segment.index == current.index,
    );
    if (prevIndex == -1) {
      return index;
    }
    final previousSegment = previous[prevIndex];
    final movedOnXAxis =
        current.start[0] != previousSegment.start[0] &&
        current.end[0] != previousSegment.end[0];
    final movedOnYAxis =
        current.start[1] != previousSegment.start[1] &&
        current.end[1] != previousSegment.end[1];
    if (movedOnXAxis != movedOnYAxis) {
      return index;
    }
  }
  return null;
}

bool _headingForPointIsHorizontal(Point point, Point origin) =>
    isHorizontalHeading(vectorToHeading(point, origin));

ArrowPatch _handleSegmentReleasePort({
  required ArrowState arrow,
  required Map<String, BindableState> bindablesById,
  required List<FixedSegment> fixedSegments,
  required double zoom,
  required double maxCoordinate,
  required bool validateInvariants,
}) {
  final previousFixedSegments = arrow.fixedSegments;
  if (previousFixedSegments == null || previousFixedSegments.isEmpty) {
    return <String, dynamic>{'points': arrow.points};
  }

  final nextFixedSegmentIndices = fixedSegments
      .map((segment) => segment.index)
      .toSet();
  final deletedSegmentPosition = previousFixedSegments.indexWhere(
    (segment) => !nextFixedSegmentIndices.contains(segment.index),
  );

  if (deletedSegmentPosition == -1 ||
      deletedSegmentPosition >= previousFixedSegments.length) {
    return <String, dynamic>{'points': arrow.points};
  }

  final deletedIdx = previousFixedSegments[deletedSegmentPosition].index;
  final prevSegment = deletedSegmentPosition > 0
      ? previousFixedSegments[deletedSegmentPosition - 1]
      : null;
  final nextSegment = deletedSegmentPosition + 1 < previousFixedSegments.length
      ? previousFixedSegments[deletedSegmentPosition + 1]
      : null;

  final subPathX = arrow.x + (prevSegment?.end[0] ?? 0);
  final subPathY = arrow.y + (prevSegment?.end[1] ?? 0);
  final subPathTargetGlobal = <double>[
    arrow.x + (nextSegment?.start[0] ?? arrow.points.last[0]),
    arrow.y + (nextSegment?.start[1] ?? arrow.points.last[1]),
  ];

  final subPathArrow = arrow.copyWith(
    x: subPathX,
    y: subPathY,
    points: <Point>[
      <double>[0, 0],
      <double>[
        subPathTargetGlobal[0] - subPathX,
        subPathTargetGlobal[1] - subPathY,
      ],
    ],
    startBinding: prevSegment == null ? arrow.startBinding : null,
    setStartBinding: true,
    endBinding: nextSegment == null ? arrow.endBinding : null,
    setEndBinding: true,
    startArrowhead: null,
    setStartArrowhead: true,
    endArrowhead: null,
    setEndArrowhead: true,
    fixedSegments: null,
    setFixedSegments: true,
  );

  final restoredPatch = _routeAndNormalizeElbowPatch(
    arrow: subPathArrow,
    bindablesById: bindablesById,
    fixedSegments: null,
    zoom: zoom,
    maxCoordinate: maxCoordinate,
    validateInvariants: validateInvariants,
    startIsSpecial: null,
    endIsSpecial: null,
  );
  final restoredPoints = _asPointListOrNull(restoredPatch['points']);
  final restoredX = restoredPatch['x'] is num
      ? (restoredPatch['x'] as num).toDouble()
      : subPathX;
  final restoredY = restoredPatch['y'] is num
      ? (restoredPatch['y'] as num).toDouble()
      : subPathY;

  if (restoredPoints == null || restoredPoints.length < 2) {
    throw StateError(
      "Property 'points' is required in the update returned by normalizeArrowElementUpdate()",
    );
  }

  final nextPoints = <Point>[];

  if (prevSegment != null) {
    for (var index = 0; index < prevSegment.index; index += 1) {
      nextPoints.add(<double>[
        arrow.x + arrow.points[index][0],
        arrow.y + arrow.points[index][1],
      ]);
    }
  }

  for (final point in restoredPoints) {
    nextPoints.add(<double>[restoredX + point[0], restoredY + point[1]]);
  }

  if (nextSegment != null) {
    for (
      var index = nextSegment.index;
      index < arrow.points.length;
      index += 1
    ) {
      nextPoints.add(<double>[
        arrow.x + arrow.points[index][0],
        arrow.y + arrow.points[index][1],
      ]);
    }
  }

  final originalSegmentCountDiff =
      (nextSegment?.index ?? arrow.points.length) -
      (prevSegment?.index ?? 0) -
      1;
  final nextFixedSegments = fixedSegments
      .map((segment) {
        if (segment.index > deletedIdx) {
          return segment.copyWith(
            index:
                segment.index -
                originalSegmentCountDiff +
                (restoredPoints.length - 1),
          );
        }
        return segment.copyWith(
          start: <double>[segment.start[0], segment.start[1]],
          end: <double>[segment.end[0], segment.end[1]],
        );
      })
      .toList(growable: true);

  final simplifiedPoints = <Point>[];
  for (var index = 0; index < nextPoints.length; index += 1) {
    final point = nextPoints[index];
    final prev = index > 0 ? nextPoints[index - 1] : null;
    final next = index + 1 < nextPoints.length ? nextPoints[index + 1] : null;

    if (prev != null && next != null) {
      final prevHeading = vectorToHeading(prev, point);
      final nextHeading = vectorToHeading(point, next);

      if (prevHeading == nextHeading) {
        for (
          var segmentIndex = 0;
          segmentIndex < nextFixedSegments.length;
          segmentIndex += 1
        ) {
          final segment = nextFixedSegments[segmentIndex];
          if (segment.index > index) {
            nextFixedSegments[segmentIndex] = segment.copyWith(
              index: segment.index - 1,
            );
          }
        }
        continue;
      } else if (prevHeading == reverseHeading(nextHeading)) {
        for (
          var segmentIndex = 0;
          segmentIndex < nextFixedSegments.length;
          segmentIndex += 1
        ) {
          final segment = nextFixedSegments[segmentIndex];
          if (segment.index > index) {
            nextFixedSegments[segmentIndex] = segment.copyWith(
              index: segment.index + 1,
            );
          }
        }
        simplifiedPoints.add(<double>[point[0], point[1]]);
        simplifiedPoints.add(<double>[point[0], point[1]]);
        continue;
      }
    }

    simplifiedPoints.add(<double>[point[0], point[1]]);
  }

  return _normalizePatchWithMetaFromGlobalPoints(
    simplifiedPoints,
    maxCoordinate,
    fixedSegments: nextFixedSegments,
    startIsSpecial: false,
    endIsSpecial: false,
  );
}

ArrowPatch _handleSegmentMovePort({
  required ArrowState arrow,
  required List<FixedSegment> fixedSegments,
  required Heading startHeading,
  required Heading endHeading,
  required BindableState? hoveredStartElement,
  required BindableState? hoveredEndElement,
  required double maxCoordinate,
}) {
  final activelyModifiedSegmentIdx = _activelyModifiedFixedSegmentPosition(
    arrow.fixedSegments,
    fixedSegments,
  );
  if (activelyModifiedSegmentIdx == null) {
    return <String, dynamic>{'points': arrow.points};
  }

  final firstSegmentIdx =
      arrow.fixedSegments?.indexWhere((segment) => segment.index == 1) ?? -1;
  final lastSegmentIdx =
      arrow.fixedSegments?.indexWhere(
        (segment) => segment.index == arrow.points.length - 1,
      ) ??
      -1;

  final movedSegment = fixedSegments[activelyModifiedSegmentIdx];
  final segmentLength = distance(movedSegment.start, movedSegment.end);
  final segmentIsTooShort = segmentLength < BASE_PADDING + 5;

  if (firstSegmentIdx == -1 &&
      movedSegment.index == 1 &&
      hoveredStartElement != null) {
    final startIsHorizontal = isHorizontalHeading(startHeading);
    final startIsPositive = startIsHorizontal
        ? startHeading == 'right'
        : startHeading == 'down';
    final padding = startIsPositive
        ? (segmentIsTooShort ? segmentLength / 2 : BASE_PADDING)
        : (segmentIsTooShort ? -segmentLength / 2 : -BASE_PADDING);
    fixedSegments[activelyModifiedSegmentIdx] = movedSegment.copyWith(
      start: <double>[
        movedSegment.start[0] + (startIsHorizontal ? padding : 0),
        movedSegment.start[1] + (!startIsHorizontal ? padding : 0),
      ],
    );
  }

  if (lastSegmentIdx == -1 &&
      movedSegment.index == arrow.points.length - 1 &&
      hoveredEndElement != null) {
    final endIsHorizontal = isHorizontalHeading(endHeading);
    final endIsPositive = endIsHorizontal
        ? endHeading == 'right'
        : endHeading == 'down';
    final padding = endIsPositive
        ? (segmentIsTooShort ? segmentLength / 2 : BASE_PADDING)
        : (segmentIsTooShort ? -segmentLength / 2 : -BASE_PADDING);
    final current = fixedSegments[activelyModifiedSegmentIdx];
    fixedSegments[activelyModifiedSegmentIdx] = current.copyWith(
      end: <double>[
        current.end[0] + (endIsHorizontal ? padding : 0),
        current.end[1] + (!endIsHorizontal ? padding : 0),
      ],
    );
  }

  final nextFixedSegments = fixedSegments
      .map(
        (segment) => segment.copyWith(
          start: <double>[
            arrow.x + segment.start[0],
            arrow.y + segment.start[1],
          ],
          end: <double>[arrow.x + segment.end[0], arrow.y + segment.end[1]],
        ),
      )
      .toList(growable: false);

  final newPoints = arrow.points
      .map((point) => <double>[arrow.x + point[0], arrow.y + point[1]])
      .toList(growable: true);

  final activeSegment = nextFixedSegments[activelyModifiedSegmentIdx];
  final startIdx = activeSegment.index - 1;
  final endIdx = activeSegment.index;
  final start = activeSegment.start;
  final end = activeSegment.end;

  final prevSegmentIsHorizontal =
      startIdx - 1 >= 0 &&
          startIdx < newPoints.length &&
          !pointsEqual(newPoints[startIdx], newPoints[startIdx - 1])
      ? _headingForPointIsHorizontal(
          newPoints[startIdx - 1],
          newPoints[startIdx],
        )
      : null;
  final nextSegmentIsHorizontal =
      endIdx + 1 < newPoints.length &&
          !pointsEqual(newPoints[endIdx], newPoints[endIdx + 1])
      ? _headingForPointIsHorizontal(newPoints[endIdx + 1], newPoints[endIdx])
      : null;

  if (prevSegmentIsHorizontal != null) {
    final dir = prevSegmentIsHorizontal ? 1 : 0;
    newPoints[startIdx - 1][dir] = start[dir];
  }
  newPoints[startIdx] = <double>[start[0], start[1]];
  newPoints[endIdx] = <double>[end[0], end[1]];
  if (nextSegmentIsHorizontal != null) {
    final dir = nextSegmentIsHorizontal ? 1 : 0;
    newPoints[endIdx + 1][dir] = end[dir];
  }

  final previousSegmentIdx = nextFixedSegments.indexWhere(
    (segment) => segment.index == startIdx,
  );
  if (previousSegmentIdx != -1) {
    final prevSegment = nextFixedSegments[previousSegmentIdx];
    final dir = _headingForPointIsHorizontal(prevSegment.end, prevSegment.start)
        ? 1
        : 0;
    nextFixedSegments[previousSegmentIdx] = prevSegment.copyWith(
      start: <double>[
        dir == 0 ? start[0] : prevSegment.start[0],
        dir == 1 ? start[1] : prevSegment.start[1],
      ],
      end: <double>[start[0], start[1]],
    );
  }

  final followingSegmentIdx = nextFixedSegments.indexWhere(
    (segment) => segment.index == endIdx + 1,
  );
  if (followingSegmentIdx != -1) {
    final nextSegment = nextFixedSegments[followingSegmentIdx];
    final dir = _headingForPointIsHorizontal(nextSegment.end, nextSegment.start)
        ? 1
        : 0;
    nextFixedSegments[followingSegmentIdx] = nextSegment.copyWith(
      end: <double>[
        dir == 0 ? end[0] : nextSegment.end[0],
        dir == 1 ? end[1] : nextSegment.end[1],
      ],
      start: <double>[end[0], end[1]],
    );
  }

  if (firstSegmentIdx == -1 && startIdx == 0) {
    final startIsHorizontal = hoveredStartElement != null
        ? isHorizontalHeading(startHeading)
        : _headingForPointIsHorizontal(newPoints[1], newPoints[0]);
    newPoints.insert(0, <double>[
      startIsHorizontal ? start[0] : arrow.x + arrow.points[0][0],
      !startIsHorizontal ? start[1] : arrow.y + arrow.points[0][1],
    ]);

    if (hoveredStartElement != null) {
      newPoints.insert(0, <double>[
        arrow.x + arrow.points[0][0],
        arrow.y + arrow.points[0][1],
      ]);
    }

    for (var index = 0; index < nextFixedSegments.length; index += 1) {
      final segment = nextFixedSegments[index];
      nextFixedSegments[index] = segment.copyWith(
        index: segment.index + (hoveredStartElement != null ? 2 : 1),
      );
    }
  }

  if (lastSegmentIdx == -1 && endIdx == arrow.points.length - 1) {
    final endIsHorizontal = isHorizontalHeading(endHeading);
    newPoints.add(<double>[
      endIsHorizontal ? end[0] : arrow.x + arrow.points.last[0],
      !endIsHorizontal ? end[1] : arrow.y + arrow.points.last[1],
    ]);
    if (hoveredEndElement != null) {
      newPoints.add(<double>[
        arrow.x + arrow.points.last[0],
        arrow.y + arrow.points.last[1],
      ]);
    }
  }

  return _normalizePatchWithMetaFromGlobalPoints(
    newPoints,
    maxCoordinate,
    fixedSegments: nextFixedSegments
        .map(
          (segment) => segment.copyWith(
            start: <double>[
              segment.start[0] - arrow.x,
              segment.start[1] - arrow.y,
            ],
            end: <double>[segment.end[0] - arrow.x, segment.end[1] - arrow.y],
          ),
        )
        .toList(growable: false),
    startIsSpecial: false,
    endIsSpecial: false,
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
  var hoveredStartElement = startElement;
  var hoveredEndElement = endElement;
  if (isDragging) {
    final bindables = bindablesById.values.toList(growable: false);
    final startGlobal = <double>[
      nextArrow.x + updatedPoints.first[0],
      nextArrow.y + updatedPoints.first[1],
    ];
    final endGlobal = <double>[
      nextArrow.x + updatedPoints.last[0],
      nextArrow.y + updatedPoints.last[1],
    ];
    final tolerance = maxBindingDistance(zoom);
    hoveredStartElement = pickHoveredBindableForFocus(
      startGlobal,
      nextArrow,
      bindables,
      tolerance: tolerance,
    );
    hoveredEndElement = pickHoveredBindableForFocus(
      endGlobal,
      nextArrow,
      bindables,
      tolerance: tolerance,
    );
  }
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
  final missingBindingSentinel = Object();
  final startBindingUpdate = hasStartBindingUpdate
      ? updates['startBinding']
      : missingBindingSentinel;
  final endBindingUpdate = hasEndBindingUpdate
      ? updates['endBinding']
      : missingBindingSentinel;

  if (startBindingUpdate == arrow.startBinding &&
      endBindingUpdate == arrow.endBinding &&
      hasNoopPointsUpdate &&
      areUpdatedPointsValid) {
    return const <String, dynamic>{};
  }

  if (hasPointsUpdate && hasFixedSegmentsUpdate) {
    return <String, dynamic>{...updates};
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
    return _handleSegmentReleasePort(
      arrow: arrow,
      bindablesById: bindablesById,
      fixedSegments: fixedSegments,
      zoom: zoom,
      maxCoordinate: maxCoordinate,
      validateInvariants: validateInvariants,
    );
  }

  if (!hasPointsUpdate) {
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
    return _handleSegmentMovePort(
      arrow: arrow,
      fixedSegments: fixedSegments
          .map(
            (segment) => segment.copyWith(
              start: <double>[segment.start[0], segment.start[1]],
              end: <double>[segment.end[0], segment.end[1]],
            ),
          )
          .toList(growable: true),
      startHeading: startEndpoint.heading,
      endHeading: endEndpoint.heading,
      hoveredStartElement: hoveredStartElement,
      hoveredEndElement: hoveredEndElement,
      maxCoordinate: maxCoordinate,
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
    arrow: arrow,
    updatedPoints: updatedPoints,
    fixedSegments: fixedSegments,
    startHeading: startEndpoint.heading,
    endHeading: endEndpoint.heading,
    startGlobalPoint: startEndpoint.point,
    endGlobalPoint: endEndpoint.point,
    hoveredStartElement: hoveredStartElement,
    hoveredEndElement: hoveredEndElement,
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
