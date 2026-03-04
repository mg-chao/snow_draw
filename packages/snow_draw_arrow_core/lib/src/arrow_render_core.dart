import 'dart:math' as math;

import 'arrow_geom.dart';
import 'arrow_types.dart';

typedef ArrowEndpointPosition = String;

const arrowEndpointPositionStart = 'start';
const arrowEndpointPositionEnd = 'end';

class ArrowheadPointsInput {
  const ArrowheadPointsInput({
    required this.arrowPoints,
    required this.strokeWidth,
    required this.curveOps,
    required this.position,
    required this.arrowhead,
  });

  final List<Point> arrowPoints;
  final double strokeWidth;
  final List<CurvePathOp> curveOps;
  final ArrowEndpointPosition position;
  final Arrowhead arrowhead;
}

class ArrowheadRenderPrimitivesInput extends ArrowheadPointsInput {
  const ArrowheadRenderPrimitivesInput({
    required super.arrowPoints,
    required super.strokeWidth,
    required super.curveOps,
    required super.position,
    required super.arrowhead,
    required this.strokeStyle,
  });

  final ArrowStrokeStyle strokeStyle;
}

sealed class ArrowheadRenderPrimitive {
  const ArrowheadRenderPrimitive({
    required this.kind,
    required this.dashMode,
    this.roughnessCap,
  });

  final String kind;
  final ArrowheadDashMode dashMode;
  final double? roughnessCap;
}

class ArrowheadLinePrimitive extends ArrowheadRenderPrimitive {
  const ArrowheadLinePrimitive({
    required this.from,
    required this.to,
    required super.dashMode,
    super.roughnessCap,
  }) : super(kind: 'line');

  final Point from;
  final Point to;
}

class ArrowheadPolygonPrimitive extends ArrowheadRenderPrimitive {
  const ArrowheadPolygonPrimitive({
    required this.points,
    required this.fillMode,
    required super.roughnessCap,
  }) : super(kind: 'polygon', dashMode: 'solid');

  final List<Point> points;
  final ArrowheadFillMode fillMode;
}

class ArrowheadCirclePrimitive extends ArrowheadRenderPrimitive {
  const ArrowheadCirclePrimitive({
    required this.center,
    required this.diameter,
    required this.fillMode,
    required super.roughnessCap,
  }) : super(kind: 'circle', dashMode: 'solid');

  final Point center;
  final double diameter;
  final ArrowheadFillMode fillMode;
}

double getArrowheadSize(Arrowhead arrowhead) {
  switch (arrowhead) {
    case 'arrow':
      return 25;
    case 'diamond':
    case 'diamond_outline':
      return 12;
    case 'crowfoot_many':
    case 'crowfoot_one':
    case 'crowfoot_one_or_many':
      return 20;
    default:
      return 15;
  }
}

double getArrowheadAngle(Arrowhead arrowhead) {
  switch (arrowhead) {
    case 'bar':
      return 90;
    case 'arrow':
      return 20;
    default:
      return 25;
  }
}

double _toRadians(double degrees) => (degrees * math.pi) / 180;

bool _isCurveOp(CurvePathOp? op) => op != null;

Point _getCurvePoint(CurvePathOp op, int xIndex, int yIndex) => <double>[
  op.data[xIndex],
  op.data[yIndex],
];

Point? _getCurveStartPoint(CurvePathOp? previousOp) {
  if (previousOp == null) {
    return null;
  }
  if (previousOp.op == 'move' && previousOp.data.length >= 2) {
    return <double>[previousOp.data[0], previousOp.data[1]];
  }
  if (previousOp.op == 'bcurveTo' && previousOp.data.length >= 6) {
    return <double>[previousOp.data[4], previousOp.data[5]];
  }
  return <double>[0, 0];
}

Point? _normalizeDirection(Point from, Point to) {
  final dx = to[0] - from[0];
  final dy = to[1] - from[1];
  final length = math.sqrt(dx * dx + dy * dy);
  if (length <= 1e-6) {
    return null;
  }
  return <double>[dx / length, dy / length];
}

Point _pointAtBezier(double t, Point p0, Point p1, Point p2, Point p3) {
  final oneMinusT = 1 - t;
  final oneMinusTSquared = oneMinusT * oneMinusT;
  final tSquared = t * t;
  final x =
      oneMinusT * oneMinusTSquared * p3[0] +
      3 * t * oneMinusTSquared * p2[0] +
      3 * tSquared * oneMinusT * p1[0] +
      p0[0] * tSquared * t;
  final y =
      oneMinusT * oneMinusTSquared * p3[1] +
      3 * t * oneMinusTSquared * p2[1] +
      3 * tSquared * oneMinusT * p1[1] +
      p0[1] * tSquared * t;
  return <double>[x, y];
}

double _getSegmentLength(
  List<Point> arrowPoints,
  ArrowEndpointPosition position,
) {
  if (arrowPoints.isEmpty) {
    return 0;
  }
  final currentPoint = position == arrowEndpointPositionEnd
      ? arrowPoints[arrowPoints.length - 1]
      : arrowPoints[0];
  final previousPoint = arrowPoints.length > 1
      ? position == arrowEndpointPositionEnd
            ? arrowPoints[arrowPoints.length - 2]
            : arrowPoints[1]
      : <double>[0, 0];
  return distance(currentPoint, previousPoint);
}

ArrowheadPoints? getArrowheadPoints(ArrowheadPointsInput input) {
  final arrowPoints = input.arrowPoints;
  final strokeWidth = input.strokeWidth;
  final curveOps = input.curveOps;
  final position = input.position;
  final arrowhead = input.arrowhead;

  if (arrowPoints.isEmpty || curveOps.length < 2) {
    return null;
  }

  final index = position == arrowEndpointPositionStart
      ? 1
      : curveOps.length - 1;
  final curveOp = index >= 0 && index < curveOps.length
      ? curveOps[index]
      : null;
  if (!_isCurveOp(curveOp) || curveOp!.data.length != 6) {
    return null;
  }

  final previousOp = curveOps[index - 1];
  final p0 = _getCurveStartPoint(previousOp);
  if (p0 == null) {
    return null;
  }

  final p1 = _getCurvePoint(curveOp, 0, 1);
  final p2 = _getCurvePoint(curveOp, 2, 3);
  final p3 = _getCurvePoint(curveOp, 4, 5);

  final endpoint = position == arrowEndpointPositionStart ? p0 : p3;
  final samplePoint = _pointAtBezier(0.3, p0, p1, p2, p3);
  final direction = _normalizeDirection(samplePoint, endpoint);
  if (direction == null) {
    return null;
  }

  final size = getArrowheadSize(arrowhead);
  final length = _getSegmentLength(arrowPoints, position);
  final lengthMultiplier =
      arrowhead == 'diamond' || arrowhead == 'diamond_outline' ? 0.25 : 0.5;
  final minSize = math.min(size, length * lengthMultiplier);
  final x2 = endpoint[0];
  final y2 = endpoint[1];
  final xs = x2 - direction[0] * minSize;
  final ys = y2 - direction[1] * minSize;

  if (arrowhead == 'dot' ||
      arrowhead == 'circle' ||
      arrowhead == 'circle_outline') {
    final diameter =
        math.sqrt((ys - y2) * (ys - y2) + (xs - x2) * (xs - x2)) +
        strokeWidth -
        2;
    return <double>[x2, y2, diameter];
  }

  final angle = getArrowheadAngle(arrowhead);
  if (arrowhead == 'crowfoot_many' || arrowhead == 'crowfoot_one_or_many') {
    final rotatedLeft = rotatePoint(
      <double>[x2, y2],
      <double>[xs, ys],
      _toRadians(-angle),
    );
    final rotatedRight = rotatePoint(
      <double>[x2, y2],
      <double>[xs, ys],
      _toRadians(angle),
    );
    return <double>[
      xs,
      ys,
      rotatedLeft[0],
      rotatedLeft[1],
      rotatedRight[0],
      rotatedRight[1],
    ];
  }

  final rotatedLeft = rotatePoint(
    <double>[xs, ys],
    <double>[x2, y2],
    _toRadians(-angle),
  );
  final rotatedRight = rotatePoint(
    <double>[xs, ys],
    <double>[x2, y2],
    _toRadians(angle),
  );
  final x3 = rotatedLeft[0];
  final y3 = rotatedLeft[1];
  final x4 = rotatedRight[0];
  final y4 = rotatedRight[1];

  if (arrowhead == 'diamond' || arrowhead == 'diamond_outline') {
    final previousPoint = position == arrowEndpointPositionStart
        ? arrowPoints.length > 1
              ? arrowPoints[1]
              : <double>[0, 0]
        : arrowPoints.length > 1
        ? arrowPoints[arrowPoints.length - 2]
        : <double>[0, 0];
    final oppositeSeed = position == arrowEndpointPositionStart
        ? <double>[x2 + minSize * 2, y2]
        : <double>[x2 - minSize * 2, y2];
    final oppositeAngle = position == arrowEndpointPositionStart
        ? math.atan2(previousPoint[1] - y2, previousPoint[0] - x2)
        : math.atan2(y2 - previousPoint[1], x2 - previousPoint[0]);
    final oppositePoint = rotatePoint(oppositeSeed, <double>[
      x2,
      y2,
    ], oppositeAngle);

    return <double>[x2, y2, x3, y3, oppositePoint[0], oppositePoint[1], x4, y4];
  }

  return <double>[x2, y2, x3, y3, x4, y4];
}

Point _toPoint(double x, double y) => <double>[x, y];

List<ArrowheadRenderPrimitive> getArrowheadRenderPrimitives(
  ArrowheadRenderPrimitivesInput input,
) {
  final points = getArrowheadPoints(input);
  if (points == null) {
    return <ArrowheadRenderPrimitive>[];
  }

  ArrowheadLinePrimitive line(
    Point from,
    Point to,
    ArrowheadDashMode dashMode, [
    double? roughnessCap,
  ]) => ArrowheadLinePrimitive(
    from: from,
    to: to,
    dashMode: dashMode,
    roughnessCap: roughnessCap,
  );

  ArrowheadPolygonPrimitive polygon(
    List<Point> polygonPoints,
    ArrowheadFillMode fillMode,
    double roughnessCap,
  ) => ArrowheadPolygonPrimitive(
    points: polygonPoints,
    fillMode: fillMode,
    roughnessCap: roughnessCap,
  );

  ArrowheadCirclePrimitive circle(
    Point center,
    double diameter,
    ArrowheadFillMode fillMode,
    double roughnessCap,
  ) => ArrowheadCirclePrimitive(
    center: center,
    diameter: diameter,
    fillMode: fillMode,
    roughnessCap: roughnessCap,
  );

  switch (input.arrowhead) {
    case 'dot':
    case 'circle':
      return <ArrowheadRenderPrimitive>[
        circle(_toPoint(points[0], points[1]), points[2], 'stroke', 0.5),
      ];
    case 'circle_outline':
      return <ArrowheadRenderPrimitive>[
        circle(_toPoint(points[0], points[1]), points[2], 'background', 0.5),
      ];
    case 'triangle':
    case 'triangle_outline':
      if (points.length != 6) {
        return <ArrowheadRenderPrimitive>[];
      }
      final x = points[0];
      final y = points[1];
      final x2 = points[2];
      final y2 = points[3];
      final x3 = points[4];
      final y3 = points[5];
      return <ArrowheadRenderPrimitive>[
        polygon(
          <Point>[
            _toPoint(x, y),
            _toPoint(x2, y2),
            _toPoint(x3, y3),
            _toPoint(x, y),
          ],
          input.arrowhead == 'triangle_outline' ? 'background' : 'stroke',
          1,
        ),
      ];
    case 'diamond':
    case 'diamond_outline':
      if (points.length != 8) {
        return <ArrowheadRenderPrimitive>[];
      }
      final x = points[0];
      final y = points[1];
      final x2 = points[2];
      final y2 = points[3];
      final x3 = points[4];
      final y3 = points[5];
      final x4 = points[6];
      final y4 = points[7];
      return <ArrowheadRenderPrimitive>[
        polygon(
          <Point>[
            _toPoint(x, y),
            _toPoint(x2, y2),
            _toPoint(x3, y3),
            _toPoint(x4, y4),
            _toPoint(x, y),
          ],
          input.arrowhead == 'diamond_outline' ? 'background' : 'stroke',
          1,
        ),
      ];
    case 'crowfoot_one':
      if (points.length != 6) {
        return <ArrowheadRenderPrimitive>[];
      }
      return <ArrowheadRenderPrimitive>[
        line(
          _toPoint(points[2], points[3]),
          _toPoint(points[4], points[5]),
          'inherit',
        ),
      ];
    case 'bar':
    case 'arrow':
    case 'crowfoot_many':
    case 'crowfoot_one_or_many':
    default:
      if (points.length != 6) {
        return <ArrowheadRenderPrimitive>[];
      }
      final x2 = points[0];
      final y2 = points[1];
      final x3 = points[2];
      final y3 = points[3];
      final x4 = points[4];
      final y4 = points[5];
      final dashMode = input.strokeStyle == 'dotted' ? 'dotted-cap' : 'solid';
      final primitives = <ArrowheadRenderPrimitive>[
        line(_toPoint(x3, y3), _toPoint(x2, y2), dashMode, 1),
        line(_toPoint(x4, y4), _toPoint(x2, y2), dashMode, 1),
      ];

      if (input.arrowhead == 'crowfoot_one_or_many') {
        final crowfootOnePoints = getArrowheadPoints(
          ArrowheadPointsInput(
            arrowPoints: input.arrowPoints,
            strokeWidth: input.strokeWidth,
            curveOps: input.curveOps,
            position: input.position,
            arrowhead: 'crowfoot_one',
          ),
        );
        if (crowfootOnePoints != null && crowfootOnePoints.length == 6) {
          primitives.add(
            line(
              _toPoint(crowfootOnePoints[2], crowfootOnePoints[3]),
              _toPoint(crowfootOnePoints[4], crowfootOnePoints[5]),
              dashMode,
              1,
            ),
          );
        }
      }

      return primitives;
  }
}

bool _isHorizontal(Point a, Point b) =>
    (a[0] - b[0]).abs() > (a[1] - b[1]).abs();

String _formatPathNumber(double value) {
  if (value == value.truncateToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

String generateElbowArrowPath(List<Point> points, double radius) {
  if (points.isEmpty) {
    return '';
  }
  if (points.length == 1) {
    return 'M ${_formatPathNumber(points[0][0])} '
        '${_formatPathNumber(points[0][1])}';
  }

  final subpoints = <Point>[];
  for (var i = 1; i < points.length - 1; i += 1) {
    final previous = points[i - 1];
    final next = points[i + 1];
    final point = points[i];
    final prevIsHorizontal = _isHorizontal(point, previous);
    final nextIsHorizontal = _isHorizontal(next, point);
    final corner = math.min(
      radius,
      math.min(
        distance(points[i], next) / 2,
        distance(points[i], previous) / 2,
      ),
    );

    if (prevIsHorizontal) {
      subpoints.add(<double>[
        if (previous[0] < point[0]) point[0] - corner else point[0] + corner,
        point[1],
      ]);
    } else {
      subpoints.add(<double>[
        point[0],
        if (previous[1] < point[1]) point[1] - corner else point[1] + corner,
      ]);
    }

    subpoints.add(point);

    if (nextIsHorizontal) {
      subpoints.add(<double>[
        if (next[0] < point[0]) point[0] - corner else point[0] + corner,
        point[1],
      ]);
    } else {
      subpoints.add(<double>[
        point[0],
        if (next[1] < point[1]) point[1] - corner else point[1] + corner,
      ]);
    }
  }

  final path = <String>[
    'M ${_formatPathNumber(points[0][0])} ${_formatPathNumber(points[0][1])}',
  ];
  for (var i = 0; i < subpoints.length; i += 3) {
    path
      ..add(
        'L ${_formatPathNumber(subpoints[i][0])} '
        '${_formatPathNumber(subpoints[i][1])}',
      )
      ..add(
        'Q ${_formatPathNumber(subpoints[i + 1][0])} '
        '${_formatPathNumber(subpoints[i + 1][1])}, '
        '${_formatPathNumber(subpoints[i + 2][0])} '
        '${_formatPathNumber(subpoints[i + 2][1])}',
      );
  }
  path.add(
    'L ${_formatPathNumber(points[points.length - 1][0])} '
    '${_formatPathNumber(points[points.length - 1][1])}',
  );
  return path.join(' ');
}
