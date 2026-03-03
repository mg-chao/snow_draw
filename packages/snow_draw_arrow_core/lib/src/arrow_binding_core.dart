import 'dart:math' as math;

import 'arrow_geom.dart';
import 'arrow_hit_test.dart';
import 'arrow_types.dart';

const double baseBindingGap = 5;
const double baseBindingGapElbow = 5;
const double baseArrowMinLength = 10;

typedef DirectionalLinkDirection = String;

class DirectionalLinkBounds {
  const DirectionalLinkBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

class DirectionalLinkArrow {
  const DirectionalLinkArrow({
    required this.x,
    required this.y,
    required this.points,
  });

  final double x;
  final double y;
  final List<Point> points;
}

typedef EndpointBindingStrategies = ({
  EndpointBindingStrategy? start,
  EndpointBindingStrategy? end,
});
typedef _BindingMutation = ({bool changed, FixedPointBinding? binding});
typedef _LineSegment = List<Point>;
typedef _CubicCurve = List<Point>;
typedef _IntersectionBounds = List<double>;

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    final out = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is String) {
        out[entry.key as String] = entry.value;
      }
    }
    return out;
  }
  return null;
}

ArrowState? _readArrow(Object? value) => value is ArrowState ? value : null;

Point? _readPoint(Object? value) {
  if (value is! List || value.length < 2) {
    return null;
  }
  final x = value[0];
  final y = value[1];
  if (x is! num || y is! num || !x.isFinite || !y.isFinite) {
    return null;
  }
  return <double>[x.toDouble(), y.toDouble()];
}

Point _readPointOrZero(Object? value) => _readPoint(value) ?? <double>[0, 0];

List<BindableState> _readBindables(Object? value) {
  if (value is List<BindableState>) {
    return value;
  }
  if (value is List) {
    return value.whereType<BindableState>().toList(growable: false);
  }
  return const <BindableState>[];
}

EngineContext _readContext(Object? value) {
  if (value is EngineContext) {
    return value;
  }
  return normalizeEngineContext(_asMap(value));
}

bool _isTrue(Map<String, dynamic>? options, String key) =>
    options?[key] == true;

Map<int, Point> _normalizePointUpdates(Object? updates) {
  final out = <int, Point>{};

  if (updates is List<PointUpdate>) {
    for (final update in updates) {
      out[update.index] = <double>[update.point[0], update.point[1]];
    }
    return out;
  }

  if (updates is List) {
    for (final item in updates) {
      if (item is PointUpdate) {
        out[item.index] = <double>[item.point[0], item.point[1]];
        continue;
      }

      final map = _asMap(item);
      if (map == null) {
        continue;
      }
      final indexValue = map['index'];
      final pointValue = map['point'];
      final index = indexValue is int
          ? indexValue
          : indexValue is num
          ? indexValue.toInt()
          : int.tryParse('$indexValue');
      final point = _readPoint(pointValue);
      if (index == null || point == null) {
        continue;
      }
      out[index] = point;
    }
    return out;
  }

  if (updates is Map<int, Point>) {
    for (final entry in updates.entries) {
      out[entry.key] = <double>[entry.value[0], entry.value[1]];
    }
    return out;
  }

  if (updates is Map) {
    for (final entry in updates.entries) {
      final index = entry.key is int
          ? entry.key as int
          : int.tryParse('${entry.key}');
      final point = _readPoint(entry.value);
      if (index == null || point == null) {
        continue;
      }
      out[index] = point;
    }
  }

  return out;
}

Map<String, BindableState> _normalizeBindableLookup(Object? bindables) {
  if (bindables is Map<String, BindableState>) {
    return bindables;
  }

  final out = <String, BindableState>{};
  if (bindables is List<BindableState>) {
    for (final bindable in bindables) {
      out[bindable.id] = bindable;
    }
    return out;
  }

  if (bindables is List) {
    for (final bindable in bindables.whereType<BindableState>()) {
      out[bindable.id] = bindable;
    }
    return out;
  }

  if (bindables is Map) {
    for (final entry in bindables.entries) {
      if (entry.key is String && entry.value is BindableState) {
        out[entry.key as String] = entry.value as BindableState;
      }
    }
  }

  return out;
}

Point _clonePoint(Point point) => <double>[point[0], point[1]];

List<Point> _clonePoints(List<Point> points) =>
    points.map(_clonePoint).toList(growable: true);

Bounds _aabbForBindable(BindableState bindable, [List<double>? offset]) {
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );
  final topLeft = rotatePoint(
    <double>[bindable.x, bindable.y],
    bindableCenter,
    bindable.angle,
  );
  final topRight = rotatePoint(
    <double>[bindable.x + bindable.width, bindable.y],
    bindableCenter,
    bindable.angle,
  );
  final bottomRight = rotatePoint(
    <double>[bindable.x + bindable.width, bindable.y + bindable.height],
    bindableCenter,
    bindable.angle,
  );
  final bottomLeft = rotatePoint(
    <double>[bindable.x, bindable.y + bindable.height],
    bindableCenter,
    bindable.angle,
  );

  final bounds = <double>[
    math.min(
      math.min(topLeft[0], topRight[0]),
      math.min(bottomRight[0], bottomLeft[0]),
    ),
    math.min(
      math.min(topLeft[1], topRight[1]),
      math.min(bottomRight[1], bottomLeft[1]),
    ),
    math.max(
      math.max(topLeft[0], topRight[0]),
      math.max(bottomRight[0], bottomLeft[0]),
    ),
    math.max(
      math.max(topLeft[1], topRight[1]),
      math.max(bottomRight[1], bottomLeft[1]),
    ),
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

Point _scaleFromOrigin(Point point, Point origin, double factor) => <double>[
  origin[0] + (point[0] - origin[0]) * factor,
  origin[1] + (point[1] - origin[1]) * factor,
];

bool _pointInTriangle(Point point, Point a, Point b, Point c) {
  double sign(Point p1, Point p2, Point p3) =>
      (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1]);

  final d1 = sign(point, a, b);
  final d2 = sign(point, b, c);
  final d3 = sign(point, c, a);
  final hasNegative = d1 < 0 || d2 < 0 || d3 < 0;
  final hasPositive = d1 > 0 || d2 > 0 || d3 > 0;
  return !(hasNegative && hasPositive);
}

String _headingForPointFromBindable(
  Point point,
  BindableState bindable,
  Bounds aabb,
) {
  final shape = canonicalizeBindableShape(bindable.shape);
  final midPoint = <double>[
    aabb[0] + (aabb[2] - aabb[0]) / 2,
    aabb[1] + (aabb[3] - aabb[1]) / 2,
  ];

  if (shape == 'diamond') {
    return headingFromBindable(point, bindable);
  }

  const searchConeMultiplier = 2.0;
  final topLeft = _scaleFromOrigin(
    <double>[aabb[0], aabb[1]],
    midPoint,
    searchConeMultiplier,
  );
  final topRight = _scaleFromOrigin(
    <double>[aabb[2], aabb[1]],
    midPoint,
    searchConeMultiplier,
  );
  final bottomLeft = _scaleFromOrigin(
    <double>[aabb[0], aabb[3]],
    midPoint,
    searchConeMultiplier,
  );
  final bottomRight = _scaleFromOrigin(
    <double>[aabb[2], aabb[3]],
    midPoint,
    searchConeMultiplier,
  );

  if (_pointInTriangle(point, topLeft, topRight, midPoint)) {
    return 'up';
  }
  if (_pointInTriangle(point, topRight, bottomRight, midPoint)) {
    return 'right';
  }
  if (_pointInTriangle(point, bottomRight, bottomLeft, midPoint)) {
    return 'down';
  }
  return 'left';
}

Point? _normalizeVector(Point from, Point to) {
  final dx = to[0] - from[0];
  final dy = to[1] - from[1];
  final length = math.sqrt(dx * dx + dy * dy);
  if (length <= 1e-6) {
    return null;
  }
  return <double>[dx / length, dy / length];
}

Point _pointFromVector(Point origin, Point direction, double magnitude) =>
    <double>[
      origin[0] + direction[0] * magnitude,
      origin[1] + direction[1] * magnitude,
    ];

Point? _lineIntersection(Point a1, Point a2, Point b1, Point b2) {
  final dxa = a2[0] - a1[0];
  final dya = a2[1] - a1[1];
  final dxb = b2[0] - b1[0];
  final dyb = b2[1] - b1[1];
  final denominator = dxa * dyb - dya * dxb;
  if (denominator.abs() < 1e-9) {
    return null;
  }

  final dx = b1[0] - a1[0];
  final dy = b1[1] - a1[1];
  final t = (dx * dyb - dy * dxb) / denominator;
  final u = (dx * dya - dy * dxa) / denominator;
  if (t < 0 || t > 1 || u < 0 || u > 1) {
    return null;
  }
  return <double>[a1[0] + t * dxa, a1[1] + t * dya];
}

double _distanceToLineSegment(Point point, _LineSegment line) {
  final x = point[0];
  final y = point[1];
  final x1 = line[0][0];
  final y1 = line[0][1];
  final x2 = line[1][0];
  final y2 = line[1][1];
  final a = x - x1;
  final b = y - y1;
  final c = x2 - x1;
  final d = y2 - y1;
  final dot = a * c + b * d;
  final lengthSq = c * c + d * d;
  final parameter = lengthSq != 0 ? dot / lengthSq : -1;

  var projectedX = x1;
  var projectedY = y1;
  if (parameter > 0 && parameter < 1) {
    projectedX = x1 + parameter * c;
    projectedY = y1 + parameter * d;
  } else if (parameter >= 1) {
    projectedX = x2;
    projectedY = y2;
  }

  final dx = x - projectedX;
  final dy = y - projectedY;
  return math.sqrt(dx * dx + dy * dy);
}

bool _pointOnLineSegment(
  Point point,
  _LineSegment line, [
  double threshold = EPSILON,
]) {
  final distanceFromLine = _distanceToLineSegment(point, line);
  if (distanceFromLine == 0) {
    return true;
  }
  return distanceFromLine < threshold;
}

Point? _linesIntersectAt(_LineSegment a, _LineSegment b) {
  final a1 = a[1][1] - a[0][1];
  final b1 = a[0][0] - a[1][0];
  final a2 = b[1][1] - b[0][1];
  final b2 = b[0][0] - b[1][0];
  final determinant = a1 * b2 - a2 * b1;
  if (determinant == 0) {
    return null;
  }
  final c1 = a1 * a[0][0] + b1 * a[0][1];
  final c2 = a2 * b[0][0] + b2 * b[0][1];
  return <double>[
    (c1 * b2 - c2 * b1) / determinant,
    (a1 * c2 - a2 * c1) / determinant,
  ];
}

Point? _pickClosestPointTo(Point target, List<Point> points) {
  if (points.isEmpty) {
    return null;
  }
  Point? candidate;
  var bestDistance = double.infinity;
  for (final point in points) {
    final nextDistance = distanceSq(target, point);
    if (nextDistance < bestDistance) {
      bestDistance = nextDistance;
      candidate = point;
    }
  }
  return candidate;
}

Point? _pickFirstByTsDistanceSort(List<Point> points) {
  if (points.isEmpty) {
    return null;
  }
  final sorted = points.toList(growable: false)
    ..sort((left, right) {
      final delta = distanceSq(left, right);
      if (delta < 0) {
        return -1;
      }
      if (delta > 0) {
        return 1;
      }
      return 0;
    });
  return sorted.first;
}

_LineSegment _makeLineSegment(Point from, Point to) => <Point>[
  <double>[from[0], from[1]],
  <double>[to[0], to[1]],
];

_IntersectionBounds _segmentBounds(_LineSegment segment) {
  final left = math.min(segment[0][0], segment[1][0]);
  final top = math.min(segment[0][1], segment[1][1]);
  final right = math.max(segment[0][0], segment[1][0]);
  final bottom = math.max(segment[0][1], segment[1][1]);
  return <double>[left, top, right, bottom];
}

_IntersectionBounds _curveBounds(_CubicCurve curve) {
  var minX = curve[0][0];
  var minY = curve[0][1];
  var maxX = curve[0][0];
  var maxY = curve[0][1];
  for (final point in curve) {
    if (point[0] < minX) {
      minX = point[0];
    }
    if (point[1] < minY) {
      minY = point[1];
    }
    if (point[0] > maxX) {
      maxX = point[0];
    }
    if (point[1] > maxY) {
      maxY = point[1];
    }
  }
  return <double>[minX, minY, maxX, maxY];
}

bool _boundsIntersect(_IntersectionBounds a, _IntersectionBounds b) {
  return a[0] <= b[2] && a[2] >= b[0] && a[1] <= b[3] && a[3] >= b[1];
}

Point _cubicPointAt(_CubicCurve curve, double t) {
  final oneMinusT = 1 - t;
  final b0 = oneMinusT * oneMinusT * oneMinusT;
  final b1 = 3 * oneMinusT * oneMinusT * t;
  final b2 = 3 * oneMinusT * t * t;
  final b3 = t * t * t;
  return <double>[
    b0 * curve[0][0] + b1 * curve[1][0] + b2 * curve[2][0] + b3 * curve[3][0],
    b0 * curve[0][1] + b1 * curve[1][1] + b2 * curve[2][1] + b3 * curve[3][1],
  ];
}

Point _cubicTangentAt(_CubicCurve curve, double t) {
  return <double>[
    -3 * (1 - t) * (1 - t) * curve[0][0] +
        3 * (1 - t) * (1 - t) * curve[1][0] -
        6 * t * (1 - t) * curve[1][0] -
        3 * t * t * curve[2][0] +
        6 * t * (1 - t) * curve[2][0] +
        3 * t * t * curve[3][0],
    -3 * (1 - t) * (1 - t) * curve[0][1] +
        3 * (1 - t) * (1 - t) * curve[1][1] -
        6 * t * (1 - t) * curve[1][1] -
        3 * t * t * curve[2][1] +
        6 * t * (1 - t) * curve[2][1] +
        3 * t * t * curve[3][1],
  ];
}

Point _normalizeVectorXY(Point vec) {
  final length = math.sqrt(vec[0] * vec[0] + vec[1] * vec[1]);
  if (length <= 1e-9) {
    return <double>[0, 0];
  }
  return <double>[vec[0] / length, vec[1] / length];
}

Point _vectorNormal(Point vec) => <double>[vec[1], -vec[0]];

List<Point> _curveOffsetPoints(
  _CubicCurve curve,
  double offset, [
  int steps = 50,
]) {
  final points = <Point>[];
  for (var index = 0; index <= steps; index += 1) {
    final t = index / steps;
    final point = _cubicPointAt(curve, t);
    final tangent = _cubicTangentAt(curve, t);
    final normal = _vectorNormal(_normalizeVectorXY(tangent));
    points.add(<double>[
      point[0] + normal[0] * offset,
      point[1] + normal[1] * offset,
    ]);
  }
  return points;
}

List<_CubicCurve>? _curveCatmullRomCubicApproxPoints(
  List<Point> points, [
  double tension = 0.5,
]) {
  if (points.length < 2) {
    return null;
  }

  final curves = <_CubicCurve>[];
  for (var index = 0; index < points.length - 1; index += 1) {
    final p0 = points[index - 1 < 0 ? 0 : index - 1];
    final p1 = points[index];
    final p2 =
        points[index + 1 >= points.length ? points.length - 1 : index + 1];
    final p3 =
        points[index + 2 >= points.length ? points.length - 1 : index + 2];
    final tangent1 = <double>[
      (p2[0] - p0[0]) * tension,
      (p2[1] - p0[1]) * tension,
    ];
    final tangent2 = <double>[
      (p3[0] - p1[0]) * tension,
      (p3[1] - p1[1]) * tension,
    ];

    final cp1x = p1[0] + tangent1[0] / 3;
    final cp1y = p1[1] + tangent1[1] / 3;
    final cp2x = p2[0] - tangent2[0] / 3;
    final cp2y = p2[1] - tangent2[1] / 3;
    curves.add(<Point>[
      <double>[p1[0], p1[1]],
      <double>[cp1x, cp1y],
      <double>[cp2x, cp2y],
      <double>[p2[0], p2[1]],
    ]);
  }
  return curves;
}

List<double>? _solveWithAnalyticalJacobian(
  _CubicCurve curve,
  _LineSegment lineSegment,
  double initialT,
  double initialS, [
  double tolerance = 1e-3,
  int iterLimit = 10,
]) {
  var t = initialT;
  var s = initialS;
  var error = double.infinity;
  var iter = 0;

  while (error >= tolerance) {
    if (iter >= iterLimit) {
      return null;
    }

    final oneMinusT = 1 - t;
    final oneMinusT2 = oneMinusT * oneMinusT;
    final oneMinusT3 = oneMinusT2 * oneMinusT;
    final t2 = t * t;
    final t3 = t2 * t;

    final bezierX =
        oneMinusT3 * curve[0][0] +
        3 * oneMinusT2 * t * curve[1][0] +
        3 * oneMinusT * t2 * curve[2][0] +
        t3 * curve[3][0];
    final bezierY =
        oneMinusT3 * curve[0][1] +
        3 * oneMinusT2 * t * curve[1][1] +
        3 * oneMinusT * t2 * curve[2][1] +
        t3 * curve[3][1];
    final lineX =
        lineSegment[0][0] + s * (lineSegment[1][0] - lineSegment[0][0]);
    final lineY =
        lineSegment[0][1] + s * (lineSegment[1][1] - lineSegment[0][1]);

    final fx = bezierX - lineX;
    final fy = bezierY - lineY;
    error = fx.abs() + fy.abs();
    if (error < tolerance) {
      break;
    }

    final dfxDt =
        -3 * oneMinusT2 * curve[0][0] +
        3 * oneMinusT2 * curve[1][0] -
        6 * oneMinusT * t * curve[1][0] -
        3 * t2 * curve[2][0] +
        6 * oneMinusT * t * curve[2][0] +
        3 * t2 * curve[3][0];
    final dfyDt =
        -3 * oneMinusT2 * curve[0][1] +
        3 * oneMinusT2 * curve[1][1] -
        6 * oneMinusT * t * curve[1][1] -
        3 * t2 * curve[2][1] +
        6 * oneMinusT * t * curve[2][1] +
        3 * t2 * curve[3][1];
    final dfxDs = -(lineSegment[1][0] - lineSegment[0][0]);
    final dfyDs = -(lineSegment[1][1] - lineSegment[0][1]);

    final determinant = dfxDt * dfyDs - dfxDs * dfyDt;
    if (determinant.abs() < 1e-12) {
      return null;
    }

    final inverseDeterminant = 1 / determinant;
    final dt = inverseDeterminant * (dfyDs * -fx - dfxDs * -fy);
    final ds = inverseDeterminant * (-dfyDt * -fx + dfxDt * -fy);
    t += dt;
    s += ds;
    iter += 1;
  }

  return <double>[t, s];
}

Point? _resolveCurveLineIntersection(
  List<double> guess,
  _LineSegment segment,
  _CubicCurve curve,
) {
  final solution = _solveWithAnalyticalJacobian(
    curve,
    segment,
    guess[0],
    guess[1],
    1e-2,
    4,
  );
  if (solution == null) {
    return null;
  }

  final t = solution[0];
  final s = solution[1];
  if (t < 0 || t > 1 || s < 0 || s > 1) {
    return null;
  }
  return _cubicPointAt(curve, t);
}

List<Point> _curveIntersectLineSegment(
  _CubicCurve curve,
  _LineSegment segment,
) {
  const guesses = <List<double>>[
    <double>[0.5, 0],
    <double>[0.2, 0],
    <double>[0.8, 0],
  ];
  for (final guess in guesses) {
    final intersection = _resolveCurveLineIntersection(guess, segment, curve);
    if (intersection != null) {
      return <Point>[intersection];
    }
  }
  return <Point>[];
}

int _resolveRoundnessType(BindableRoundnessType type) {
  if (type is String) {
    final lower = type.toLowerCase();
    if (lower == 'legacy') {
      return bindableRoundness['LEGACY']!;
    }
    if (lower == 'proportional') {
      return bindableRoundness['PROPORTIONAL']!;
    }
    if (lower == 'adaptive') {
      return bindableRoundness['ADAPTIVE']!;
    }
  }
  if (type is num) {
    final value = type.toInt();
    if (value == 1 || value == 2 || value == 3) {
      return value;
    }
  }
  return bindableRoundness['LEGACY']!;
}

double _getCornerRadius(double size, BindableState bindable) {
  final roundness = bindable.roundness;
  if (roundness == null) {
    return 0;
  }
  final roundnessType = _resolveRoundnessType(roundness.type);
  if (roundnessType == bindableRoundness['LEGACY']! ||
      roundnessType == bindableRoundness['PROPORTIONAL']!) {
    return size * 0.25;
  }
  if (roundnessType == bindableRoundness['ADAPTIVE']!) {
    final fixedRadius = roundness.value ?? 32;
    final cutoffSize = fixedRadius / 0.25;
    if (size <= cutoffSize) {
      return size * 0.25;
    }
    return fixedRadius;
  }
  return 0;
}

List<Object> _deconstructRectanguloid(
  BindableState bindable, [
  double offset = 0,
]) {
  final minX = bindable.x;
  final minY = bindable.y;
  final maxX = bindable.x + bindable.width;
  final maxY = bindable.y + bindable.height;

  var radius = _getCornerRadius(
    math.min(bindable.width, bindable.height),
    bindable,
  );
  if (radius == 0) {
    radius = 0.01;
  }

  final top = _makeLineSegment(
    <double>[minX + radius, minY],
    <double>[maxX - radius, minY],
  );
  final right = _makeLineSegment(
    <double>[maxX, minY + radius],
    <double>[maxX, maxY - radius],
  );
  final bottom = _makeLineSegment(
    <double>[minX + radius, maxY],
    <double>[maxX - radius, maxY],
  );
  final left = _makeLineSegment(
    <double>[minX, maxY - radius],
    <double>[minX, minY + radius],
  );

  final baseCorners = <_CubicCurve>[
    <Point>[
      left[1],
      <double>[
        left[1][0] + (2 / 3) * (minX - left[1][0]),
        left[1][1] + (2 / 3) * (minY - left[1][1]),
      ],
      <double>[
        top[0][0] + (2 / 3) * (minX - top[0][0]),
        top[0][1] + (2 / 3) * (minY - top[0][1]),
      ],
      top[0],
    ],
    <Point>[
      top[1],
      <double>[
        top[1][0] + (2 / 3) * (maxX - top[1][0]),
        top[1][1] + (2 / 3) * (minY - top[1][1]),
      ],
      <double>[
        right[0][0] + (2 / 3) * (maxX - right[0][0]),
        right[0][1] + (2 / 3) * (minY - right[0][1]),
      ],
      right[0],
    ],
    <Point>[
      right[1],
      <double>[
        right[1][0] + (2 / 3) * (maxX - right[1][0]),
        right[1][1] + (2 / 3) * (maxY - right[1][1]),
      ],
      <double>[
        bottom[1][0] + (2 / 3) * (maxX - bottom[1][0]),
        bottom[1][1] + (2 / 3) * (maxY - bottom[1][1]),
      ],
      bottom[1],
    ],
    <Point>[
      bottom[0],
      <double>[
        bottom[0][0] + (2 / 3) * (minX - bottom[0][0]),
        bottom[0][1] + (2 / 3) * (maxY - bottom[0][1]),
      ],
      <double>[
        left[0][0] + (2 / 3) * (minX - left[0][0]),
        left[0][1] + (2 / 3) * (maxY - left[0][1]),
      ],
      left[0],
    ],
  ];

  final cornerGroups = offset > 0
      ? baseCorners
            .map(
              (corner) =>
                  _curveCatmullRomCubicApproxPoints(
                    _curveOffsetPoints(corner, offset),
                  ) ??
                  <_CubicCurve>[corner],
            )
            .toList(growable: false)
      : <List<_CubicCurve>>[
          <_CubicCurve>[baseCorners[0]],
          <_CubicCurve>[baseCorners[1]],
          <_CubicCurve>[baseCorners[2]],
          <_CubicCurve>[baseCorners[3]],
        ];

  final sides = <_LineSegment>[
    _makeLineSegment(
      cornerGroups[0][cornerGroups[0].length - 1][3],
      cornerGroups[1][0][0],
    ),
    _makeLineSegment(
      cornerGroups[1][cornerGroups[1].length - 1][3],
      cornerGroups[2][0][0],
    ),
    _makeLineSegment(
      cornerGroups[2][cornerGroups[2].length - 1][3],
      cornerGroups[3][0][0],
    ),
    _makeLineSegment(
      cornerGroups[3][cornerGroups[3].length - 1][3],
      cornerGroups[0][0][0],
    ),
  ];
  final corners = cornerGroups.expand((group) => group).toList(growable: false);
  return <Object>[sides, corners];
}

List<double> _getDiamondPoints(BindableState bindable) {
  final topX = (bindable.width / 2).floorToDouble() + 1;
  const topY = 0.0;
  final rightX = bindable.width;
  final rightY = (bindable.height / 2).floorToDouble() + 1;
  final bottomX = topX;
  final bottomY = bindable.height;
  const leftX = 0.0;
  final leftY = rightY;
  return <double>[topX, topY, rightX, rightY, bottomX, bottomY, leftX, leftY];
}

List<_CubicCurve> _getDiamondBaseCorners(BindableState bindable) {
  final points = _getDiamondPoints(bindable);
  final topX = points[0];
  final topY = points[1];
  final rightX = points[2];
  final rightY = points[3];
  final bottomX = points[4];
  final bottomY = points[5];
  final leftX = points[6];
  final leftY = points[7];
  final verticalRadius = bindable.roundness != null
      ? _getCornerRadius((topX - leftX).abs(), bindable)
      : (topX - leftX) * 0.01;
  final horizontalRadius = bindable.roundness != null
      ? _getCornerRadius((rightY - topY).abs(), bindable)
      : (rightY - topY) * 0.01;

  final top = <double>[bindable.x + topX, bindable.y + topY];
  final right = <double>[bindable.x + rightX, bindable.y + rightY];
  final bottom = <double>[bindable.x + bottomX, bindable.y + bottomY];
  final left = <double>[bindable.x + leftX, bindable.y + leftY];

  return <_CubicCurve>[
    <Point>[
      <double>[right[0] - verticalRadius, right[1] - horizontalRadius],
      right,
      right,
      <double>[right[0] - verticalRadius, right[1] + horizontalRadius],
    ],
    <Point>[
      <double>[bottom[0] + verticalRadius, bottom[1] - horizontalRadius],
      bottom,
      bottom,
      <double>[bottom[0] - verticalRadius, bottom[1] - horizontalRadius],
    ],
    <Point>[
      <double>[left[0] + verticalRadius, left[1] + horizontalRadius],
      left,
      left,
      <double>[left[0] + verticalRadius, left[1] - horizontalRadius],
    ],
    <Point>[
      <double>[top[0] - verticalRadius, top[1] + horizontalRadius],
      top,
      top,
      <double>[top[0] + verticalRadius, top[1] + horizontalRadius],
    ],
  ];
}

List<Object> _deconstructDiamond(BindableState bindable, [double offset = 0]) {
  final baseCorners = _getDiamondBaseCorners(bindable);
  final cornerGroups = baseCorners
      .map(
        (corner) =>
            _curveCatmullRomCubicApproxPoints(
              _curveOffsetPoints(corner, offset),
            ) ??
            <_CubicCurve>[corner],
      )
      .toList(growable: false);
  final sides = <_LineSegment>[
    _makeLineSegment(
      cornerGroups[0][cornerGroups[0].length - 1][3],
      cornerGroups[1][0][0],
    ),
    _makeLineSegment(
      cornerGroups[1][cornerGroups[1].length - 1][3],
      cornerGroups[2][0][0],
    ),
    _makeLineSegment(
      cornerGroups[2][cornerGroups[2].length - 1][3],
      cornerGroups[3][0][0],
    ),
    _makeLineSegment(
      cornerGroups[3][cornerGroups[3].length - 1][3],
      cornerGroups[0][0][0],
    ),
  ];
  final corners = cornerGroups.expand((group) => group).toList(growable: false);
  return <Object>[sides, corners];
}

Point? _lineSegmentIntersectionPoints(
  _LineSegment line,
  _LineSegment segment, [
  double threshold = EPSILON,
]) {
  final candidate = _linesIntersectAt(line, segment);
  if (candidate == null ||
      !_pointOnLineSegment(candidate, segment, threshold) ||
      !_pointOnLineSegment(candidate, line, threshold)) {
    return null;
  }
  return candidate;
}

List<Point> _lineIntersections(
  List<_LineSegment> lines,
  _LineSegment segment,
  List<Point> out,
) {
  for (final line in lines) {
    final intersection = _lineSegmentIntersectionPoints(line, segment);
    if (intersection != null) {
      out.add(intersection);
    }
  }
  return out;
}

List<Point> _curveIntersections(
  List<_CubicCurve> curves,
  _LineSegment segment,
  List<Point> out,
) {
  final lineBounds = _segmentBounds(segment);
  for (final curve in curves) {
    if (!_boundsIntersect(_curveBounds(curve), lineBounds)) {
      continue;
    }
    final hits = _curveIntersectLineSegment(curve, segment);
    if (hits.isNotEmpty) {
      out.addAll(hits);
    }
  }
  return out;
}

List<Point> _dedupePoints(List<Point> points, [double epsilon = 1e-6]) {
  final out = <Point>[];
  for (final point in points) {
    final exists = out.any(
      (existing) =>
          (existing[0] - point[0]).abs() <= epsilon &&
          (existing[1] - point[1]).abs() <= epsilon,
    );
    if (!exists) {
      out.add(point);
    }
  }
  return out;
}

List<Point> _rectangleIntersectionsApprox(
  Point start,
  Point end,
  BindableState bindable,
  double gap,
) {
  final minX = bindable.x - gap;
  final minY = bindable.y - gap;
  final maxX = bindable.x + bindable.width + gap;
  final maxY = bindable.y + bindable.height + gap;
  final corners = <Point>[
    <double>[minX, minY],
    <double>[maxX, minY],
    <double>[maxX, maxY],
    <double>[minX, maxY],
  ];
  final sides = <_LineSegment>[
    _makeLineSegment(corners[0], corners[1]),
    _makeLineSegment(corners[1], corners[2]),
    _makeLineSegment(corners[2], corners[3]),
    _makeLineSegment(corners[3], corners[0]),
  ];

  final intersections = <Point>[];
  for (final side in sides) {
    final intersection = _lineIntersection(start, end, side[0], side[1]);
    if (intersection != null) {
      intersections.add(intersection);
    }
  }
  return intersections;
}

List<Point> _rectangleIntersections(
  Point start,
  Point end,
  BindableState bindable,
  double gap,
) {
  final segment = _makeLineSegment(start, end);
  final deconstructed = _deconstructRectanguloid(bindable, gap);
  final sides = deconstructed[0] as List<_LineSegment>;
  final corners = deconstructed[1] as List<_CubicCurve>;
  final intersections = <Point>[];
  _lineIntersections(sides, segment, intersections);
  _curveIntersections(corners, segment, intersections);
  return intersections.isNotEmpty
      ? intersections
      : _rectangleIntersectionsApprox(start, end, bindable, gap);
}

List<Point> _diamondIntersectionsSimple(
  Point start,
  Point end,
  BindableState bindable,
  double gap,
) {
  final cx = bindable.x + bindable.width / 2;
  final cy = bindable.y + bindable.height / 2;
  final top = <double>[cx, bindable.y - gap];
  final right = <double>[bindable.x + bindable.width + gap, cy];
  final bottom = <double>[cx, bindable.y + bindable.height + gap];
  final left = <double>[bindable.x - gap, cy];
  final sides = <_LineSegment>[
    _makeLineSegment(top, right),
    _makeLineSegment(right, bottom),
    _makeLineSegment(bottom, left),
    _makeLineSegment(left, top),
  ];

  final intersections = <Point>[];
  for (final side in sides) {
    final intersection = _lineIntersection(start, end, side[0], side[1]);
    if (intersection != null) {
      intersections.add(intersection);
    }
  }
  return intersections;
}

List<Point> _diamondIntersectionsApprox(
  Point start,
  Point end,
  BindableState bindable,
  double gap,
) {
  final baseCorners = _getDiamondBaseCorners(bindable);
  final cornerPolylines = baseCorners
      .map((curve) => _curveOffsetPoints(curve, gap))
      .toList(growable: false);
  final intersections = <Point>[];

  for (final corner in cornerPolylines) {
    for (var index = 1; index < corner.length; index += 1) {
      final intersection = _lineIntersection(
        start,
        end,
        corner[index - 1],
        corner[index],
      );
      if (intersection != null) {
        intersections.add(intersection);
      }
    }
  }

  for (var index = 0; index < cornerPolylines.length; index += 1) {
    final current = cornerPolylines[index];
    final next = cornerPolylines[(index + 1) % cornerPolylines.length];
    final sideStart = current[current.length - 1];
    final sideEnd = next[0];
    final intersection = _lineIntersection(start, end, sideStart, sideEnd);
    if (intersection != null) {
      intersections.add(intersection);
    }
  }

  final resolved = _dedupePoints(intersections);
  return resolved.isNotEmpty
      ? resolved
      : _diamondIntersectionsSimple(start, end, bindable, gap);
}

List<Point> _diamondIntersections(
  Point start,
  Point end,
  BindableState bindable,
  double gap,
) {
  final segment = _makeLineSegment(start, end);
  final deconstructed = _deconstructDiamond(bindable, gap);
  final sides = deconstructed[0] as List<_LineSegment>;
  final corners = deconstructed[1] as List<_CubicCurve>;
  final intersections = <Point>[];
  _lineIntersections(sides, segment, intersections);
  _curveIntersections(corners, segment, intersections);
  return intersections.isNotEmpty
      ? intersections
      : _diamondIntersectionsApprox(start, end, bindable, gap);
}

List<Point> _ellipseIntersections(
  Point start,
  Point end,
  BindableState bindable,
  double gap,
) {
  final cx = bindable.x + bindable.width / 2;
  final cy = bindable.y + bindable.height / 2;
  final rx = math.max(bindable.width / 2 + gap, 1e-6);
  final ry = math.max(bindable.height / 2 + gap, 1e-6);
  final dx = end[0] - start[0];
  final dy = end[1] - start[1];

  final a = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry);
  final b =
      (2 * (start[0] - cx) * dx) / (rx * rx) +
      (2 * (start[1] - cy) * dy) / (ry * ry);
  final c =
      ((start[0] - cx) * (start[0] - cx)) / (rx * rx) +
      ((start[1] - cy) * (start[1] - cy)) / (ry * ry) -
      1;

  final delta = b * b - 4 * a * c;
  if (delta < 0 || a.abs() < 1e-9) {
    return const <Point>[];
  }

  final intersections = <Point>[];
  final sqrtDelta = math.sqrt(delta);
  final t1 = (-b - sqrtDelta) / (2 * a);
  final t2 = (-b + sqrtDelta) / (2 * a);
  if (t1 >= 0 && t1 <= 1) {
    intersections.add(<double>[start[0] + t1 * dx, start[1] + t1 * dy]);
  }
  if (t2 >= 0 && t2 <= 1) {
    intersections.add(<double>[start[0] + t2 * dx, start[1] + t2 * dy]);
  }
  return intersections;
}

List<Point> _intersectOutline(
  Point from,
  Point to,
  BindableState bindable,
  double gap,
) {
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );
  final localFrom = unrotatePoint(from, bindableCenter, bindable.angle);
  final localTo = unrotatePoint(to, bindableCenter, bindable.angle);
  final localBindable = bindable.copyWith(angle: 0);
  final localShape = canonicalizeBindableShape(localBindable.shape);

  late final List<Point> intersections;
  if (localShape == 'rectangle') {
    intersections = _rectangleIntersections(
      localFrom,
      localTo,
      localBindable,
      gap,
    );
  } else if (localShape == 'ellipse') {
    intersections = _ellipseIntersections(
      localFrom,
      localTo,
      localBindable,
      gap,
    );
  } else {
    intersections = _diamondIntersections(
      localFrom,
      localTo,
      localBindable,
      gap,
    );
  }

  return intersections
      .map((point) => rotatePoint(point, bindableCenter, bindable.angle))
      .toList(growable: false);
}

List<List<Point>> _getDiagonalGuideSegments(BindableState bindable) {
  final shape = canonicalizeBindableShape(bindable.shape);
  final c = center(bindable.x, bindable.y, bindable.width, bindable.height);

  List<Point> shrink(List<Point> segment, double offset) {
    final from = segment[0];
    final to = segment[1];
    final len = distance(from, to);
    if (len <= 1e-6 || len <= offset * 2) {
      return <Point>[from, to];
    }
    final dx = (to[0] - from[0]) / len;
    final dy = (to[1] - from[1]) / len;
    return <Point>[
      <double>[from[0] + dx * offset, from[1] + dy * offset],
      <double>[to[0] - dx * offset, to[1] - dy * offset],
    ];
  }

  if (shape == 'rectangle') {
    final topLeft = rotatePoint(
      <double>[bindable.x, bindable.y],
      c,
      bindable.angle,
    );
    final topRight = rotatePoint(
      <double>[bindable.x + bindable.width, bindable.y],
      c,
      bindable.angle,
    );
    final bottomRight = rotatePoint(
      <double>[bindable.x + bindable.width, bindable.y + bindable.height],
      c,
      bindable.angle,
    );
    final bottomLeft = rotatePoint(
      <double>[bindable.x, bindable.y + bindable.height],
      c,
      bindable.angle,
    );
    return <List<Point>>[
      shrink(<Point>[topLeft, bottomRight], 15),
      shrink(<Point>[topRight, bottomLeft], 15),
    ];
  }

  final topCenter = rotatePoint(
    <double>[bindable.x + bindable.width / 2, bindable.y],
    c,
    bindable.angle,
  );
  final bottomCenter = rotatePoint(
    <double>[bindable.x + bindable.width / 2, bindable.y + bindable.height],
    c,
    bindable.angle,
  );
  final leftCenter = rotatePoint(
    <double>[bindable.x, bindable.y + bindable.height / 2],
    c,
    bindable.angle,
  );
  final rightCenter = rotatePoint(
    <double>[bindable.x + bindable.width, bindable.y + bindable.height / 2],
    c,
    bindable.angle,
  );
  return <List<Point>>[
    <Point>[topCenter, bottomCenter],
    <Point>[leftCenter, rightCenter],
  ];
}

List<Point> _getSnapOutlineMidPointCandidates(BindableState bindable) {
  final shape = canonicalizeBindableShape(bindable.shape);
  final c = center(bindable.x, bindable.y, bindable.width, bindable.height);

  if (shape == 'diamond') {
    final topX = (bindable.width / 2).floorToDouble() + 1;
    const topY = 0.0;
    final rightX = bindable.width;
    final rightY = (bindable.height / 2).floorToDouble() + 1;
    final bottomX = topX;
    final bottomY = bindable.height;
    const leftX = 0.0;
    final leftY = rightY;

    final verticalRadius = (topX - leftX) * 0.01;
    final horizontalRadius = (rightY - topY) * 0.01;

    final top = <double>[bindable.x + topX, bindable.y + topY];
    final right = <double>[bindable.x + rightX, bindable.y + rightY];
    final bottom = <double>[bindable.x + bottomX, bindable.y + bottomY];
    final left = <double>[bindable.x + leftX, bindable.y + leftY];

    Point bezierAtHalf(Point p0, Point p1, Point p2, Point p3) {
      const t = 0.5;
      const oneMinusT = 1 - t;
      final b0 = math.pow(oneMinusT, 3).toDouble();
      final b1 = 3 * t * math.pow(oneMinusT, 2).toDouble();
      final b2 = 3 * math.pow(t, 2).toDouble() * oneMinusT;
      final b3 = math.pow(t, 3).toDouble();
      return <double>[
        b0 * p0[0] + b1 * p1[0] + b2 * p2[0] + b3 * p3[0],
        b0 * p0[1] + b1 * p1[1] + b2 * p2[1] + b3 * p3[1],
      ];
    }

    final corners = <Point>[
      bezierAtHalf(
        <double>[right[0] - verticalRadius, right[1] - horizontalRadius],
        right,
        right,
        <double>[right[0] - verticalRadius, right[1] + horizontalRadius],
      ),
      bezierAtHalf(
        <double>[bottom[0] + verticalRadius, bottom[1] - horizontalRadius],
        bottom,
        bottom,
        <double>[bottom[0] - verticalRadius, bottom[1] - horizontalRadius],
      ),
      bezierAtHalf(
        <double>[left[0] + verticalRadius, left[1] + horizontalRadius],
        left,
        left,
        <double>[left[0] + verticalRadius, left[1] - horizontalRadius],
      ),
      bezierAtHalf(
        <double>[top[0] - verticalRadius, top[1] + horizontalRadius],
        top,
        top,
        <double>[top[0] + verticalRadius, top[1] + horizontalRadius],
      ),
    ];

    return corners
        .map((point) => rotatePoint(point, c, bindable.angle))
        .toList(growable: false);
  }

  final right = rotatePoint(
    <double>[bindable.x + bindable.width, bindable.y + bindable.height / 2],
    c,
    bindable.angle,
  );
  final bottom = rotatePoint(
    <double>[bindable.x + bindable.width / 2, bindable.y + bindable.height],
    c,
    bindable.angle,
  );
  final left = rotatePoint(
    <double>[bindable.x, bindable.y + bindable.height / 2],
    c,
    bindable.angle,
  );
  final top = rotatePoint(
    <double>[bindable.x + bindable.width / 2, bindable.y],
    c,
    bindable.angle,
  );
  return <Point>[right, bottom, left, top];
}

_BindingMutation _addOrRemoveBindingPatch({
  required ArrowState arrow,
  required ArrowEndpointEdge edge,
  required EndpointBindingStrategy? strategy,
  required FixedPointBinding? previousBinding,
  required List<BindablePatch> bindablePatches,
  required List<ArrowEngineEvent> events,
  required Set<String> reorderTargetIds,
  required String arrowId,
}) {
  if (strategy == null) {
    return (changed: false, binding: previousBinding);
  }

  if (strategy.mode == null) {
    if (previousBinding != null) {
      bindablePatches.add(
        BindablePatch(
          id: previousBinding.elementId,
          removeBoundArrowId: arrowId,
        ),
      );
      events.add(BindingBrokenEvent(arrowId: arrowId, edge: edge));
    }
    return (changed: true, binding: null);
  }

  final element = strategy.element;
  final focusPoint = strategy.focusPoint;
  if (element == null || focusPoint == null) {
    return (changed: false, binding: previousBinding);
  }

  final binding = _toBinding(arrow, edge, element, strategy.mode!, focusPoint);
  if (previousBinding == null ||
      previousBinding.elementId != binding.elementId) {
    if (previousBinding != null) {
      bindablePatches.add(
        BindablePatch(
          id: previousBinding.elementId,
          removeBoundArrowId: arrowId,
        ),
      );
    }
    bindablePatches.add(
      BindablePatch(id: binding.elementId, addBoundArrowId: arrowId),
    );
    if (!reorderTargetIds.contains(binding.elementId)) {
      reorderTargetIds.add(binding.elementId);
      events.add(
        ReorderArrowEvent(arrowId: arrowId, bindableId: binding.elementId),
      );
    }
  }
  return (changed: true, binding: binding);
}

double _pointsWidth(List<Point> points) {
  if (points.isEmpty) {
    return 0;
  }
  var minValue = points[0][0];
  var maxValue = points[0][0];
  for (final point in points) {
    if (point[0] < minValue) {
      minValue = point[0];
    }
    if (point[0] > maxValue) {
      maxValue = point[0];
    }
  }
  return maxValue - minValue;
}

double _pointsHeight(List<Point> points) {
  if (points.isEmpty) {
    return 0;
  }
  var minValue = points[0][1];
  var maxValue = points[0][1];
  for (final point in points) {
    if (point[1] < minValue) {
      minValue = point[1];
    }
    if (point[1] > maxValue) {
      maxValue = point[1];
    }
  }
  return maxValue - minValue;
}

EngineResult _emptyEngineResult() => const EngineResult(
  arrowPatch: <String, dynamic>{},
  bindablePatches: <BindablePatch>[],
  suggestedBinding: null,
  events: <ArrowEngineEvent>[],
);

DirectionalLinkArrow createDirectionalLinkArrow(
  DirectionalLinkBounds start,
  DirectionalLinkBounds end,
  DirectionalLinkDirection direction, {
  double padding = 6,
}) {
  var startX = 0.0;
  var startY = 0.0;

  if (direction == 'up') {
    startX = start.x + start.width / 2;
    startY = start.y - padding;
  } else if (direction == 'down') {
    startX = start.x + start.width / 2;
    startY = start.y + start.height + padding;
  } else if (direction == 'right') {
    startX = start.x + start.width + padding;
    startY = start.y + start.height / 2;
  } else if (direction == 'left') {
    startX = start.x - padding;
    startY = start.y + start.height / 2;
  }

  var endX = 0.0;
  var endY = 0.0;

  if (direction == 'up') {
    endX = end.x + end.width / 2 - startX;
    endY = end.y + end.height - startY + padding;
  } else if (direction == 'down') {
    endX = end.x + end.width / 2 - startX;
    endY = end.y - startY - padding;
  } else if (direction == 'right') {
    endX = end.x - startX - padding;
    endY = end.y - startY + end.height / 2;
  } else if (direction == 'left') {
    endX = end.x + end.width - startX + padding;
    endY = end.y - startY + end.height / 2;
  }

  return DirectionalLinkArrow(
    x: startX,
    y: startY,
    points: <Point>[
      <double>[0, 0],
      <double>[endX, endY],
    ],
  );
}

List<Point> offsetArrowEndpointsForBindingOverlap(
  List<Point> points, {
  double delta = 0.5,
}) {
  if (points.length < 2 || !delta.isFinite || delta <= 0) {
    return points;
  }

  final endPointIndex = points.length - 1;
  final prevPoint = points[endPointIndex - 1];
  final endPoint = points[endPointIndex];
  final startPoint = points[0];
  final nextPoints = points
      .map((point) => <double>[point[0], point[1]])
      .toList(growable: true);
  var changed = false;

  if (endPoint[0] > prevPoint[0]) {
    nextPoints[0][0] = startPoint[0] + delta;
    nextPoints[endPointIndex][0] = endPoint[0] - delta;
    changed = true;
  }
  if (endPoint[0] < prevPoint[0]) {
    nextPoints[0][0] = startPoint[0] - delta;
    nextPoints[endPointIndex][0] = endPoint[0] + delta;
    changed = true;
  }
  if (endPoint[1] > prevPoint[1]) {
    nextPoints[0][1] = startPoint[1] + delta;
    nextPoints[endPointIndex][1] = endPoint[1] - delta;
    changed = true;
  }
  if (endPoint[1] < prevPoint[1]) {
    nextPoints[0][1] = startPoint[1] - delta;
    nextPoints[endPointIndex][1] = endPoint[1] + delta;
    changed = true;
  }

  return changed ? nextPoints : points;
}

double getBindingGap(BindableState bindTarget, bool elbowed) =>
    (elbowed ? baseBindingGapElbow : baseBindingGap) +
    bindTarget.strokeWidth / 2;

double maxBindingDistance(double zoom) {
  final baseDistance = math.max(baseBindingGap, 15).toDouble();
  final safeZoom = zoom < 1 ? zoom : 1;
  return clamp(baseDistance / (safeZoom * 1.5), baseDistance, baseDistance * 2);
}

Point avoidRectangularCorner(
  ArrowState arrow,
  BindableState bindable,
  Point point,
) {
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );
  final local = unrotatePoint(point, bindableCenter, bindable.angle);
  final bindingGap = getBindingGap(bindable, arrow.elbowed);

  if (local[0] < bindable.x && local[1] < bindable.y) {
    if (local[1] - bindable.y > -bindingGap) {
      return rotatePoint(
        <double>[bindable.x - bindingGap, bindable.y],
        bindableCenter,
        bindable.angle,
      );
    }
    return rotatePoint(
      <double>[bindable.x, bindable.y - bindingGap],
      bindableCenter,
      bindable.angle,
    );
  }

  if (local[0] < bindable.x && local[1] > bindable.y + bindable.height) {
    if (local[0] - bindable.x > -bindingGap) {
      return rotatePoint(
        <double>[bindable.x, bindable.y + bindable.height + bindingGap],
        bindableCenter,
        bindable.angle,
      );
    }
    return rotatePoint(
      <double>[bindable.x - bindingGap, bindable.y + bindable.height],
      bindableCenter,
      bindable.angle,
    );
  }

  if (local[0] > bindable.x + bindable.width &&
      local[1] > bindable.y + bindable.height) {
    if (local[0] - bindable.x < bindable.width + bindingGap) {
      return rotatePoint(
        <double>[
          bindable.x + bindable.width,
          bindable.y + bindable.height + bindingGap,
        ],
        bindableCenter,
        bindable.angle,
      );
    }
    return rotatePoint(
      <double>[
        bindable.x + bindable.width + bindingGap,
        bindable.y + bindable.height,
      ],
      bindableCenter,
      bindable.angle,
    );
  }

  if (local[0] > bindable.x + bindable.width && local[1] < bindable.y) {
    if (local[0] - bindable.x < bindable.width + bindingGap) {
      return rotatePoint(
        <double>[bindable.x + bindable.width, bindable.y - bindingGap],
        bindableCenter,
        bindable.angle,
      );
    }
    return rotatePoint(
      <double>[bindable.x + bindable.width + bindingGap, bindable.y],
      bindableCenter,
      bindable.angle,
    );
  }

  return point;
}

Point? snapToMid(
  BindableState bindable,
  Point point, {
  double tolerance = 0.05,
  ArrowState? arrow,
}) {
  final shape = canonicalizeBindableShape(bindable.shape);
  final bindableCenterRaw = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );
  final bindableCenter = <double>[
    bindableCenterRaw[0] - 0.1,
    bindableCenterRaw[1] - 0.1,
  ];
  final local = unrotatePoint(point, bindableCenter, bindable.angle);
  final bindingGap = arrow == null
      ? 0.0
      : getBindingGap(bindable, arrow.elbowed);
  final verticalThreshold = clamp(tolerance * bindable.height, 5, 80);
  final horizontalThreshold = clamp(tolerance * bindable.width, 5, 80);

  if (distance(bindableCenter, local) < bindingGap) {
    return null;
  }

  if (local[0] <= bindable.x + bindable.width / 2 &&
      local[1] > bindableCenter[1] - verticalThreshold &&
      local[1] < bindableCenter[1] + verticalThreshold) {
    return rotatePoint(
      <double>[bindable.x - bindingGap, bindableCenter[1]],
      bindableCenter,
      bindable.angle,
    );
  }

  if (local[1] <= bindable.y + bindable.height / 2 &&
      local[0] > bindableCenter[0] - horizontalThreshold &&
      local[0] < bindableCenter[0] + horizontalThreshold) {
    return rotatePoint(
      <double>[bindableCenter[0], bindable.y - bindingGap],
      bindableCenter,
      bindable.angle,
    );
  }

  if (local[0] >= bindable.x + bindable.width / 2 &&
      local[1] > bindableCenter[1] - verticalThreshold &&
      local[1] < bindableCenter[1] + verticalThreshold) {
    return rotatePoint(
      <double>[bindable.x + bindable.width + bindingGap, bindableCenter[1]],
      bindableCenter,
      bindable.angle,
    );
  }

  if (local[1] >= bindable.y + bindable.height / 2 &&
      local[0] > bindableCenter[0] - horizontalThreshold &&
      local[0] < bindableCenter[0] + horizontalThreshold) {
    return rotatePoint(
      <double>[bindableCenter[0], bindable.y + bindable.height + bindingGap],
      bindableCenter,
      bindable.angle,
    );
  }

  if (shape == 'diamond') {
    final offsetThreshold = math.max(horizontalThreshold, verticalThreshold);
    final qx = bindable.width / 4;
    final qy = bindable.height / 4;
    final corners = <Point>[
      <double>[bindable.x + qx - bindingGap, bindable.y + qy - bindingGap],
      <double>[bindable.x + 3 * qx + bindingGap, bindable.y + qy - bindingGap],
      <double>[bindable.x + qx - bindingGap, bindable.y + 3 * qy + bindingGap],
      <double>[
        bindable.x + 3 * qx + bindingGap,
        bindable.y + 3 * qy + bindingGap,
      ],
    ];

    for (final corner in corners) {
      if (distance(corner, local) < offsetThreshold) {
        return rotatePoint(corner, bindableCenter, bindable.angle);
      }
    }
  }

  return null;
}

Point? getSnapOutlineMidPoint(Object first, Object second, [double zoom = 1]) {
  late final Point point;
  late final BindableState bindable;
  if (first is Point && second is BindableState) {
    point = first;
    bindable = second;
  } else if (first is BindableState && second is Point) {
    bindable = first;
    point = second;
  } else {
    return null;
  }

  final threshold = maxBindingDistance(zoom) + bindable.strokeWidth / 2;
  final candidates = _getSnapOutlineMidPointCandidates(bindable);
  for (final candidate in candidates) {
    if (distance(point, candidate) <= threshold &&
        !isPointInBindable(point, bindable)) {
      return candidate;
    }
  }
  return null;
}

Point? projectFixedPointOntoDiagonal(
  ArrowState arrow,
  Point point,
  BindableState bindable,
  ArrowEndpointEdge startOrEnd,
  List<BindableState> bindables,
  double zoom,
) {
  if (arrow.points.length < 2 || (arrow.width < 3 && arrow.height < 3)) {
    return null;
  }

  final sideMidPoint = getSnapOutlineMidPoint(point, bindable, zoom);
  if (sideMidPoint != null) {
    return sideMidPoint;
  }

  final diagonalSegments = _getDiagonalGuideSegments(bindable);
  final diagonalOne = diagonalSegments[0];
  final diagonalTwo = diagonalSegments[1];
  final bindablesById = <String, BindableState>{
    for (final candidate in bindables) candidate.id: candidate,
  };

  var anchor = getPointAtIndexGlobal(
    arrow,
    startOrEnd == arrowEndpointStart ? 1 : -2,
  );
  if (arrow.points.length == 2) {
    final otherBinding = startOrEnd == arrowEndpointStart
        ? arrow.endBinding
        : arrow.startBinding;
    final otherBindable = otherBinding == null
        ? null
        : bindablesById[otherBinding.elementId];
    if (otherBinding != null && otherBindable != null) {
      anchor = getGlobalFixedPoint(otherBinding, otherBindable);
    }
  }

  final direction = _normalizeVector(anchor, point);
  if (direction == null) {
    return null;
  }

  final extent = math.max(
    distance(diagonalOne[0], diagonalOne[1]),
    distance(diagonalTwo[0], diagonalTwo[1]),
  );
  final rayLength = 2 * distance(anchor, point) + extent;
  final rayPoint = <double>[
    anchor[0] + direction[0] * rayLength,
    anchor[1] + direction[1] * rayLength,
  ];
  final p1 = _lineIntersection(
    diagonalOne[0],
    diagonalOne[1],
    rayPoint,
    anchor,
  );
  final p2 = _lineIntersection(
    diagonalTwo[0],
    diagonalTwo[1],
    rayPoint,
    anchor,
  );

  Point? projection;
  if (p1 != null && p2 != null) {
    projection = distance(anchor, p1) <= distance(anchor, p2) ? p1 : p2;
  } else {
    projection = p1 ?? p2;
  }

  if (projection == null || !isPointInBindable(projection, bindable)) {
    return null;
  }
  return projection;
}

Point bindPointToOutline({
  required ArrowState arrow,
  required BindableState bindable,
  required ArrowEndpointEdge edge,
  List<Point>? customIntersector,
}) {
  final shape = canonicalizeBindableShape(bindable.shape);
  final startOrEnd = normalizeArrowEndpointEdge(edge);
  final point = getPointAtIndexGlobal(
    arrow,
    startOrEnd == arrowEndpointStart ? 0 : -1,
  );
  if (arrow.points.length < 2) {
    return point;
  }

  final edgePoint = shape == 'rectangle' && arrow.elbowed
      ? avoidRectangularCorner(arrow, bindable, point)
      : point;
  final adjacentPoint =
      customIntersector != null &&
          customIntersector.length >= 2 &&
          !arrow.elbowed
      ? customIntersector[1]
      : getPointAtIndexGlobal(arrow, startOrEnd == arrowEndpointStart ? 1 : -2);
  final bindingGap = getBindingGap(bindable, arrow.elbowed);
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );

  Point? intersection;
  if (arrow.elbowed) {
    final heading = _headingForPointFromBindable(
      point,
      bindable,
      _aabbForBindable(bindable),
    );
    final isHorizontal = heading == 'left' || heading == 'right';
    final snapPoint = snapToMid(
      bindable,
      edgePoint,
      tolerance: 0.05,
      arrow: arrow,
    );
    final resolved = snapPoint ?? point;
    final otherPoint = <double>[
      isHorizontal ? bindableCenter[0] : resolved[0],
      !isHorizontal ? bindableCenter[1] : resolved[1],
    ];

    final intersector =
        customIntersector != null && customIntersector.length >= 2
        ? <Point>[customIntersector[0], customIntersector[1]]
        : <Point>[
            otherPoint,
            _pointFromVector(
              otherPoint,
              _normalizeVector(otherPoint, resolved) ?? <double>[0, 0],
              math.max(bindable.width, bindable.height) * 2,
            ),
          ];
    final intersections = _intersectOutline(
      intersector[0],
      intersector[1],
      bindable,
      bindingGap,
    );
    intersection = _pickFirstByTsDistanceSort(intersections);

    if (intersection == null) {
      final anotherPoint = <double>[
        !isHorizontal ? bindableCenter[0] : resolved[0],
        isHorizontal ? bindableCenter[1] : resolved[1],
      ];
      final fallbackIntersections = _intersectOutline(
        anotherPoint,
        _pointFromVector(
          anotherPoint,
          _normalizeVector(anotherPoint, resolved) ?? <double>[0, 0],
          math.max(bindable.width, bindable.height) * 2,
        ),
        bindable,
        baseBindingGapElbow,
      );
      intersection = _pickFirstByTsDistanceSort(fallbackIntersections);
    }
  } else {
    List<Point>? intersector = customIntersector;
    if (intersector == null || intersector.length < 2) {
      final direction = _normalizeVector(edgePoint, adjacentPoint);
      if (direction != null) {
        final halfVector = _pointFromVector(
          <double>[0, 0],
          direction,
          distance(edgePoint, adjacentPoint) +
              math.max(bindable.width, bindable.height) +
              bindingGap * 2,
        );
        intersector = <Point>[
          _pointFromVector(adjacentPoint, halfVector, 1),
          _pointFromVector(adjacentPoint, <double>[
            -halfVector[0],
            -halfVector[1],
          ], 1),
        ];
      }
    }

    if (distance(edgePoint, adjacentPoint) < 1) {
      intersection = edgePoint;
    } else if (intersector != null && intersector.length >= 2) {
      final intersections = _intersectOutline(
        intersector[0],
        intersector[1],
        bindable,
        bindingGap,
      );
      intersection = _pickClosestPointTo(adjacentPoint, intersections);
    }
  }

  if (intersection == null || distanceSq(edgePoint, intersection) < EPSILON) {
    return edgePoint;
  }
  return intersection;
}

Point _calculateFixedPointForBindingRatio(
  BindableState bindable,
  Point globalPoint,
) {
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );
  final local = unrotatePoint(globalPoint, bindableCenter, bindable.angle);
  final fixedX = (local[0] - bindable.x) / math.max(bindable.width, 1e-6);
  final fixedY = (local[1] - bindable.y) / math.max(bindable.height, 1e-6);
  return normalizeFixedPoint(<double>[fixedX, fixedY]);
}

Point _calculateFixedPointForElbowBindingRatio(
  ArrowState arrow,
  BindableState bindable,
  ArrowEndpointEdge edge,
) => _calculateFixedPointForBindingRatio(
  bindable,
  bindPointToOutline(arrow: arrow, bindable: bindable, edge: edge),
);

FixedPointBinding calculateFixedPointForBinding({
  required Point point,
  required BindableState bindable,
  BindMode mode = bindModeOrbit,
}) => FixedPointBinding(
  elementId: bindable.id,
  fixedPoint: _calculateFixedPointForBindingRatio(bindable, point),
  mode: mode,
);

FixedPointBinding calculateFixedPointForElbowBinding({
  required Point point,
  required BindableState bindable,
  BindMode mode = bindModeOrbit,
  ArrowState? arrow,
  ArrowEndpointEdge edge = arrowEndpointStart,
}) => FixedPointBinding(
  elementId: bindable.id,
  fixedPoint: arrow == null
      ? _calculateFixedPointForBindingRatio(bindable, point)
      : _calculateFixedPointForElbowBindingRatio(arrow, bindable, edge),
  mode: mode,
);

Point? _updateBoundPointInternal({
  required ArrowState arrow,
  required ArrowEndpointSelector edge,
  required FixedPointBinding binding,
  required BindableState bindable,
  required Object bindablesById,
  bool dragging = false,
}) {
  final bindableLookup = _normalizeBindableLookup(bindablesById);
  if (binding.elementId != bindable.id && arrow.points.length > 2 ||
      arrow.points.length < 2 ||
      pointsEqual(arrow.points[arrow.points.length - 1], <double>[0, 0])) {
    return null;
  }

  final focusPoint = getGlobalFixedPoint(binding, bindable);
  if (binding.mode == bindModeInside) {
    return toLocalPoint(arrow, focusPoint);
  }

  final normalizedEdge = normalizeArrowEndpointEdge(edge);
  final otherBinding = normalizedEdge == arrowEndpointStart
      ? arrow.endBinding
      : arrow.startBinding;
  final otherPoint = getPointAtIndexGlobal(
    arrow,
    normalizedEdge == arrowEndpointStart ? 1 : -2,
  );
  final otherBindable = otherBinding == null
      ? null
      : bindableLookup[otherBinding.elementId];
  final otherFocus = otherBinding != null && otherBindable != null
      ? getGlobalFixedPoint(otherBinding, otherBindable)
      : null;

  final otherFocusPointOrArrowPoint = arrow.points.length == 2
      ? (otherFocus ?? otherPoint)
      : otherPoint;

  final otherOutline = otherBindable == null
      ? null
      : _pickClosestPointTo(
          focusPoint,
          _intersectOutline(
            focusPoint,
            otherFocusPointOrArrowPoint,
            otherBindable,
            getBindingGap(otherBindable, arrow.elbowed),
          ),
        );
  final outline = _pickClosestPointTo(
    otherFocusPointOrArrowPoint,
    _intersectOutline(
      focusPoint,
      otherFocusPointOrArrowPoint,
      bindable,
      getBindingGap(bindable, arrow.elbowed),
    ),
  );

  final startHasArrowhead = arrow.startArrowhead != null;
  final endHasArrowhead = arrow.endArrowhead != null;
  final currentHasArrowhead = normalizedEdge == arrowEndpointStart
      ? startHasArrowhead
      : endHasArrowhead;
  final resolvedTarget =
      (!startHasArrowhead && !endHasArrowhead) || currentHasArrowhead
      ? focusPoint
      : (outline ?? focusPoint);

  if (otherBindable != null &&
      outline != null &&
      !dragging &&
      otherBindable.width * otherBindable.height <
          bindable.width * bindable.height * 2 &&
      (isPointInBindable(outline, otherBindable) ||
          distanceToBindableOutline(outline, otherBindable) <=
              getBindingGap(otherBindable, arrow.elbowed))) {
    return toLocalPoint(arrow, resolvedTarget);
  }

  final otherTargetPoint = otherBindable == null
      ? otherPoint
      : (otherOutline ?? otherFocus ?? otherPoint);
  final tooShort =
      distance(otherTargetPoint, outline ?? focusPoint) <= baseArrowMinLength;

  if (otherBindable == null) {
    return toLocalPoint(arrow, tooShort ? focusPoint : (outline ?? focusPoint));
  }
  if (tooShort) {
    return toLocalPoint(arrow, resolvedTarget);
  }
  return toLocalPoint(arrow, outline ?? focusPoint);
}

Point? updateBoundPoint({
  required ArrowState arrow,
  ArrowEndpointSelector edge = arrowEndpointStart,
  required FixedPointBinding binding,
  required BindableState bindable,
  required BindableLookupInput bindablesById,
  bool dragging = false,
}) {
  return _updateBoundPointInternal(
    arrow: arrow,
    edge: edge,
    binding: binding,
    bindable: bindable,
    bindablesById: bindablesById,
    dragging: dragging,
  );
}

FixedPointBinding _toBinding(
  ArrowState arrow,
  ArrowEndpointEdge edge,
  BindableState element,
  BindMode mode,
  Point focusPoint,
) => FixedPointBinding(
  elementId: element.id,
  mode: arrow.elbowed ? bindModeOrbit : mode,
  fixedPoint: arrow.elbowed
      ? _calculateFixedPointForElbowBindingRatio(arrow, element, edge)
      : _calculateFixedPointForBindingRatio(element, focusPoint),
);

EndpointBindingStrategies _pickDragEdgeStrategies(
  bool startDragged,
  EndpointBindingStrategy? strategy, [
  EndpointBindingStrategy? other,
]) => startDragged
    ? (start: strategy, end: other)
    : (start: other, end: strategy);

EndpointBindingStrategies _strategyForElbowEndpoint({
  required Map<String, dynamic> inputMap,
  required ArrowState arrow,
  required List<BindableState> bindables,
  required EngineContext context,
  required Map<int, Point> draggedPoints,
}) {
  if (draggedPoints.isEmpty) {
    return (start: null, end: null);
  }

  final firstDrag = draggedPoints.entries.first;
  final draggedIndex = firstDrag.key;
  final draggedPoint = firstDrag.value;
  final globalPoint = toGlobalPoint(arrow, draggedPoint);
  final hit = getHoveredBindable(
    globalPoint,
    bindables,
    maxBindingDistance(context.zoom),
  );
  final focusPoint = getPointAtIndexGlobal(arrow, draggedIndex);
  final strategy = hit == null
      ? const EndpointBindingStrategy(mode: null)
      : EndpointBindingStrategy(
          mode: bindModeOrbit,
          bindableId: hit.id,
          element: hit,
          focusPoint: focusPoint,
        );

  if (draggedIndex == 0) {
    return (start: strategy, end: null);
  }
  return (start: null, end: strategy);
}

List<Point> _sampleOutlinePoints(BindableState bindable, double offset) {
  final shape = canonicalizeBindableShape(bindable.shape);
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );
  if (shape == 'ellipse') {
    final cx = bindable.x + bindable.width / 2;
    final cy = bindable.y + bindable.height / 2;
    final rx = bindable.width / 2 + offset;
    final ry = bindable.height / 2 + offset;
    return <Point>[
      rotatePoint(<double>[cx, cy - ry], bindableCenter, bindable.angle),
      rotatePoint(<double>[cx + rx, cy], bindableCenter, bindable.angle),
      rotatePoint(<double>[cx, cy + ry], bindableCenter, bindable.angle),
      rotatePoint(<double>[cx - rx, cy], bindableCenter, bindable.angle),
    ];
  }
  if (shape == 'diamond') {
    final cx = bindable.x + bindable.width / 2;
    final cy = bindable.y + bindable.height / 2;
    return <Point>[
      rotatePoint(
        <double>[cx, bindable.y - offset],
        bindableCenter,
        bindable.angle,
      ),
      rotatePoint(
        <double>[bindable.x + bindable.width + offset, cy],
        bindableCenter,
        bindable.angle,
      ),
      rotatePoint(
        <double>[cx, bindable.y + bindable.height + offset],
        bindableCenter,
        bindable.angle,
      ),
      rotatePoint(
        <double>[bindable.x - offset, cy],
        bindableCenter,
        bindable.angle,
      ),
    ];
  }
  return <Point>[
    rotatePoint(
      <double>[bindable.x - offset, bindable.y - offset],
      bindableCenter,
      bindable.angle,
    ),
    rotatePoint(
      <double>[bindable.x + bindable.width + offset, bindable.y - offset],
      bindableCenter,
      bindable.angle,
    ),
    rotatePoint(
      <double>[
        bindable.x + bindable.width + offset,
        bindable.y + bindable.height + offset,
      ],
      bindableCenter,
      bindable.angle,
    ),
    rotatePoint(
      <double>[bindable.x - offset, bindable.y + bindable.height + offset],
      bindableCenter,
      bindable.angle,
    ),
  ];
}

bool _isBindableInsideOther(BindableState inner, BindableState outer) {
  final offset = -math.max(inner.width, inner.height) * 0.05;
  final samples = _sampleOutlinePoints(inner, offset);
  return samples.every(
    (sample) =>
        isPointInBindable(sample, outer) ||
        distanceToBindableOutline(sample, outer) <= outer.strokeWidth / 2,
  );
}

EndpointBindingStrategies getEndpointBindingStrategy(
  ComputeEndpointDragInput input,
) {
  final inputMap = _asMap(input) ?? const <String, dynamic>{};
  final arrow = _readArrow(inputMap['arrow']);
  if (arrow == null) {
    return (start: null, end: null);
  }

  final bindables = _readBindables(inputMap['bindables']);
  final context = _readContext(inputMap['context']);
  final options = _asMap(inputMap['options']);
  final complexBindings = _isTrue(options, 'complexBindings');
  final draggedPoints = _normalizePointUpdates(inputMap['draggedPoints']);
  final startIndex = 0;
  final endIndex = arrow.points.length - 1;
  final startDragged = draggedPoints.containsKey(startIndex);
  final endDragged = draggedPoints.containsKey(endIndex);
  final bindablesById = <String, BindableState>{
    for (final bindable in bindables) bindable.id: bindable,
  };

  if (!startDragged && !endDragged) {
    return (start: null, end: null);
  }

  if (startDragged && endDragged) {
    const remove = EndpointBindingStrategy(mode: null);
    return (start: remove, end: remove);
  }

  if (!context.isBindingEnabled) {
    const remove = EndpointBindingStrategy(mode: null);
    return (
      start: startDragged ? remove : null,
      end: endDragged ? remove : null,
    );
  }

  if (arrow.elbowed) {
    return _strategyForElbowEndpoint(
      inputMap: inputMap,
      arrow: arrow,
      bindables: bindables,
      context: context,
      draggedPoints: draggedPoints,
    );
  }

  final draggedPoint = draggedPoints[startDragged ? startIndex : endIndex];
  if (draggedPoint == null) {
    return (start: null, end: null);
  }

  final globalPoint = toGlobalPoint(arrow, draggedPoint);
  final hit = getHoveredBindable(
    globalPoint,
    bindables,
    maxBindingDistance(context.zoom),
  );
  final otherBinding = startDragged ? arrow.endBinding : arrow.startBinding;
  final overlapping = getBindablesOverPoint(
    globalPoint,
    bindables,
    maxBindingDistance(context.zoom),
  );
  final otherBindable = otherBinding == null
      ? null
      : bindablesById[otherBinding.elementId];
  final isOverlappingOther =
      otherBindable != null &&
      overlapping.any((bindable) => bindable.id == otherBindable.id);
  final isNested =
      hit != null &&
      otherBindable != null &&
      hit.id != otherBindable.id &&
      _isBindableInsideOther(otherBindable, hit);
  final bindModeForcesInside =
      context.bindMode == bindModeInside || context.bindMode == bindModeSkip;
  final altForcesInside = _isTrue(options, 'altKey');
  final pointInHit = hit != null
      ? isPointInBindable(
          _isTrue(options, 'angleLocked')
              ? _readPointOrZero(inputMap['pointer'])
              : globalPoint,
          hit,
        )
      : false;
  final otherFocusPoint = otherBinding != null && otherBindable != null
      ? getGlobalFixedPoint(otherBinding, otherBindable)
      : null;
  final otherFocusPointIsInElement =
      otherBindable != null &&
      otherFocusPoint != null &&
      (isPointInBindable(otherFocusPoint, otherBindable) ||
          distanceToBindableOutline(otherFocusPoint, otherBindable) <= EPSILON);
  final pointIsCloseToOtherElement =
      otherBindable != null &&
      (isPointInBindable(globalPoint, otherBindable) ||
          distanceToBindableOutline(globalPoint, otherBindable) <=
              maxBindingDistance(context.zoom));
  final otherNeverOverride = _isTrue(options, 'newArrow')
      ? _isTrue(options, 'preserveOppositeInsideBinding')
      : otherBinding?.mode == bindModeInside;
  final oppositeIndex = startDragged ? endIndex : startIndex;
  final oppositePoint = getPointAtIndexGlobal(arrow, oppositeIndex);

  EndpointBindingStrategy? angleLockedOtherStrategy;
  if (!otherNeverOverride &&
      otherBindable != null &&
      _isTrue(options, 'angleLocked')) {
    final projected =
        projectFixedPointOntoDiagonal(
          arrow,
          oppositePoint,
          otherBindable,
          startDragged ? arrowEndpointEnd : arrowEndpointStart,
          bindables,
          context.zoom,
        ) ??
        oppositePoint;
    angleLockedOtherStrategy = EndpointBindingStrategy(
      mode: bindModeOrbit,
      bindableId: otherBindable.id,
      element: otherBindable,
      focusPoint: projected,
    );
  }

  final oppositeOrbitFocusPoint = _readPoint(
    options?['oppositeOrbitFocusPoint'],
  );
  final otherStrategy =
      otherBindable != null &&
          oppositeOrbitFocusPoint != null &&
          !otherNeverOverride &&
          !otherFocusPointIsInElement &&
          !pointIsCloseToOtherElement
      ? EndpointBindingStrategy(
          mode: bindModeOrbit,
          bindableId: otherBindable.id,
          element: otherBindable,
          focusPoint: oppositeOrbitFocusPoint,
        )
      : angleLockedOtherStrategy;

  if (_isTrue(options, 'initialBinding') &&
      _isTrue(options, 'newArrow') &&
      startDragged) {
    final initial = hit == null
        ? const EndpointBindingStrategy(mode: null)
        : EndpointBindingStrategy(
            mode: bindModeInside,
            bindableId: hit.id,
            element: hit,
            focusPoint: globalPoint,
          );
    return _pickDragEdgeStrategies(startDragged, initial);
  }

  if (bindModeForcesInside) {
    final bindTarget =
        hit != null &&
            isOverlappingOther &&
            otherBindable != null &&
            isBindableBackgroundOpaque(otherBindable)
        ? otherBindable
        : hit;
    final forced = bindTarget == null
        ? const EndpointBindingStrategy(mode: null)
        : EndpointBindingStrategy(
            mode: bindModeInside,
            bindableId: bindTarget.id,
            element: bindTarget,
            focusPoint: globalPoint,
          );
    final shouldBreakOppositeBinding =
        _isTrue(options, 'finalize') &&
        hit != null &&
        otherBinding != null &&
        otherBinding.elementId == hit.id &&
        arrow.points.length == 2;
    final other = shouldBreakOppositeBinding
        ? const EndpointBindingStrategy(mode: null)
        : null;
    return _pickDragEdgeStrategies(startDragged, forced, other);
  }

  if (altForcesInside) {
    final forced = hit == null
        ? const EndpointBindingStrategy(mode: null)
        : EndpointBindingStrategy(
            mode: bindModeInside,
            bindableId: hit.id,
            element: hit,
            focusPoint: globalPoint,
          );
    return _pickDragEdgeStrategies(startDragged, forced, null);
  }

  if (otherBinding != null && hit != null && otherBinding.elementId == hit.id) {
    if (!complexBindings) {
      final current = EndpointBindingStrategy(
        mode: bindModeInside,
        bindableId: hit.id,
        element: hit,
        focusPoint: globalPoint,
      );
      final oppositeEdgePoint = getPointAtIndexGlobal(arrow, oppositeIndex);
      final other = EndpointBindingStrategy(
        mode: bindModeInside,
        bindableId: hit.id,
        element: hit,
        focusPoint: oppositeEdgePoint,
      );
      return _pickDragEdgeStrategies(startDragged, current, other);
    }

    if (otherBinding.mode == bindModeOrbit) {
      final projectedFocusPoint =
          projectFixedPointOntoDiagonal(
            arrow,
            globalPoint,
            hit,
            startDragged ? arrowEndpointStart : arrowEndpointEnd,
            bindables,
            context.zoom,
          ) ??
          globalPoint;
      final current = EndpointBindingStrategy(
        mode: bindModeOrbit,
        bindableId: hit.id,
        element: hit,
        focusPoint: projectedFocusPoint,
      );
      final other = _isTrue(options, 'finalize')
          ? (arrow.points.length > 2
                ? null
                : const EndpointBindingStrategy(mode: null))
          : null;
      return _pickDragEdgeStrategies(startDragged, current, other);
    }

    final current = EndpointBindingStrategy(
      mode: bindModeInside,
      bindableId: hit.id,
      element: hit,
      focusPoint: globalPoint,
    );
    return _pickDragEdgeStrategies(startDragged, current);
  }

  if (hit == null) {
    return _pickDragEdgeStrategies(
      startDragged,
      const EndpointBindingStrategy(mode: null),
      otherStrategy,
    );
  }

  if (otherBindable != null &&
      isOverlappingOther &&
      isBindableBackgroundOpaque(otherBindable)) {
    final current = EndpointBindingStrategy(
      mode: bindModeInside,
      bindableId: otherBindable.id,
      element: otherBindable,
      focusPoint: globalPoint,
    );
    return _pickDragEdgeStrategies(startDragged, current);
  }

  final BindMode mode;
  if (_isTrue(options, 'newArrow') && startDragged) {
    mode = bindModeInside;
  } else if (_isTrue(options, 'newArrow') && otherBinding == null) {
    mode = bindModeOrbit;
  } else if (_isTrue(options, 'newArrow') && otherBinding != null) {
    mode = bindModeForcesInside ? bindModeInside : bindModeOrbit;
  } else if (complexBindings) {
    mode = bindModeOrbit;
  } else if (pointInHit && !isNested) {
    mode = bindModeInside;
  } else {
    mode = bindModeOrbit;
  }

  final projectedFocusPoint = mode == bindModeOrbit
      ? (projectFixedPointOntoDiagonal(
              arrow,
              globalPoint,
              hit,
              startDragged ? arrowEndpointStart : arrowEndpointEnd,
              bindables,
              context.zoom,
            ) ??
            globalPoint)
      : globalPoint;

  final current = EndpointBindingStrategy(
    mode: mode,
    bindableId: hit.id,
    element: hit,
    focusPoint: projectedFocusPoint,
  );
  return _pickDragEdgeStrategies(startDragged, current, otherStrategy);
}

EngineResult computeSimpleBindingPatch(ComputeEndpointDragInput input) {
  final arrow = _readArrow(input['arrow']);
  if (arrow == null) {
    return _emptyEngineResult();
  }
  final bindables = _readBindables(input['bindables']);
  final context = _readContext(input['context']);

  final draggedPoints = _normalizePointUpdates(input['draggedPoints']);
  if (draggedPoints.isEmpty) {
    return _emptyEngineResult();
  }

  final startIndex = 0;
  final endIndex = arrow.points.length - 1;
  final startDragged = draggedPoints.containsKey(startIndex);
  final endDragged = draggedPoints.containsKey(endIndex);
  final strategies = getEndpointBindingStrategy(input);
  final bindablesById = {
    for (final bindable in bindables) bindable.id: bindable,
  };

  final bindablePatches = <BindablePatch>[];
  final events = <ArrowEngineEvent>[];
  final reorderTargetIds = <String>{};

  final nextStartBindingPatch = _addOrRemoveBindingPatch(
    arrow: arrow,
    edge: arrowEndpointStart,
    strategy: strategies.start,
    previousBinding: arrow.startBinding,
    bindablePatches: bindablePatches,
    events: events,
    reorderTargetIds: reorderTargetIds,
    arrowId: arrow.id,
  );
  final nextEndBindingPatch = _addOrRemoveBindingPatch(
    arrow: arrow,
    edge: arrowEndpointEnd,
    strategy: strategies.end,
    previousBinding: arrow.endBinding,
    bindablePatches: bindablePatches,
    events: events,
    reorderTargetIds: reorderTargetIds,
    arrowId: arrow.id,
  );

  var effectiveStartBinding = nextStartBindingPatch.changed
      ? nextStartBindingPatch.binding
      : arrow.startBinding;
  var effectiveEndBinding = nextEndBindingPatch.changed
      ? nextEndBindingPatch.binding
      : arrow.endBinding;

  final nextPoints = arrow.points
      .map((point) => <double>[point[0], point[1]])
      .toList(growable: true);
  draggedPoints.forEach((index, point) {
    if (index < 0 || index >= nextPoints.length) {
      return;
    }
    nextPoints[index] = <double>[point[0], point[1]];
  });

  final simulatedArrow = arrow.copyWith(
    points: nextPoints,
    startBinding: effectiveStartBinding,
    setStartBinding: true,
    endBinding: effectiveEndBinding,
    setEndBinding: true,
  );

  final startBindable = effectiveStartBinding == null
      ? null
      : bindablesById[effectiveStartBinding!.elementId];
  final endBindable = effectiveEndBinding == null
      ? null
      : bindablesById[effectiveEndBinding!.elementId];

  SuggestedBinding? suggestedBinding;
  if (strategies.start?.element != null &&
      strategies.start?.focusPoint != null) {
    final focusPoint = startDragged && draggedPoints[startIndex] != null
        ? toGlobalPoint(arrow, draggedPoints[startIndex]!)
        : strategies.start!.focusPoint!;
    suggestedBinding = SuggestedBinding(
      bindableId: strategies.start!.bindableId ?? strategies.start!.element!.id,
      element: strategies.start!.element!,
      midPoint: getSnapOutlineMidPoint(
        focusPoint,
        strategies.start!.element!,
        context.zoom,
      ),
    );
  } else if (strategies.end?.element != null &&
      strategies.end?.focusPoint != null) {
    final focusPoint = endDragged && draggedPoints[endIndex] != null
        ? toGlobalPoint(arrow, draggedPoints[endIndex]!)
        : strategies.end!.focusPoint!;
    suggestedBinding = SuggestedBinding(
      bindableId: strategies.end!.bindableId ?? strategies.end!.element!.id,
      element: strategies.end!.element!,
      midPoint: getSnapOutlineMidPoint(
        focusPoint,
        strategies.end!.element!,
        context.zoom,
      ),
    );
  }

  final complexBindings = _isTrue(_asMap(input['options']), 'complexBindings');
  final startIsDraggingOverEndElement =
      arrow.endBinding != null &&
      effectiveStartBinding != null &&
      startDragged &&
      effectiveStartBinding.elementId == arrow.endBinding!.elementId;
  final endIsDraggingOverStartElement =
      arrow.startBinding != null &&
      effectiveEndBinding != null &&
      endDragged &&
      arrow.startBinding!.elementId == effectiveEndBinding.elementId;

  if (endBindable != null && effectiveEndBinding != null) {
    Point? updatedEnd;
    if (startIsDraggingOverEndElement) {
      updatedEnd = nextPoints[nextPoints.length - 1];
    } else if (endIsDraggingOverStartElement &&
        context.bindMode != bindModeInside &&
        complexBindings) {
      updatedEnd = nextPoints[0];
    } else {
      updatedEnd = updateBoundPoint(
        arrow: simulatedArrow,
        edge: 'endBinding',
        binding: effectiveEndBinding,
        bindable: endBindable,
        bindablesById: bindablesById,
        dragging: endDragged,
      );
    }

    if (updatedEnd != null) {
      nextPoints[nextPoints.length - 1] = updatedEnd;
      final updatedEndGlobal = toGlobalPoint(simulatedArrow, updatedEnd);
      effectiveEndBinding = effectiveEndBinding.copyWith(
        fixedPoint: _calculateFixedPointForBindingRatio(
          endBindable,
          updatedEndGlobal,
        ),
      );
    }
  }

  final simulatedWithEnd = simulatedArrow.copyWith(
    points: nextPoints,
    endBinding: effectiveEndBinding,
    setEndBinding: true,
  );

  if (startBindable != null && effectiveStartBinding != null) {
    Point? updatedStart;
    if (endIsDraggingOverStartElement && complexBindings) {
      updatedStart = nextPoints[0];
    } else if (startIsDraggingOverEndElement &&
        context.bindMode != bindModeInside &&
        complexBindings) {
      updatedStart = nextPoints[nextPoints.length - 1];
    } else {
      updatedStart = updateBoundPoint(
        arrow: simulatedWithEnd,
        edge: 'startBinding',
        binding: effectiveStartBinding,
        bindable: startBindable,
        bindablesById: bindablesById,
        dragging: startDragged,
      );
    }

    if (updatedStart != null) {
      nextPoints[0] = updatedStart;
      final updatedStartGlobal = toGlobalPoint(simulatedWithEnd, updatedStart);
      effectiveStartBinding = effectiveStartBinding.copyWith(
        fixedPoint: _calculateFixedPointForBindingRatio(
          startBindable,
          updatedStartGlobal,
        ),
      );
    }
  }

  final origin = nextPoints.isNotEmpty ? nextPoints[0] : <double>[0, 0];
  final normalizedPoints = nextPoints
      .map((point) => <double>[point[0] - origin[0], point[1] - origin[1]])
      .toList(growable: false);

  final bounds = computeBoundsFromPoints(normalizedPoints);
  final patch = <String, dynamic>{
    'x': arrow.x + origin[0],
    'y': arrow.y + origin[1],
    'points': normalizedPoints,
    'width': bounds.width,
    'height': bounds.height,
    'startBinding': effectiveStartBinding,
    'endBinding': effectiveEndBinding,
  };

  return EngineResult(
    arrowPatch: patch,
    bindablePatches: bindablePatches,
    suggestedBinding: suggestedBinding,
    events: events,
  );
}

EngineResult recomputeBindingsAfterBindableChange(
  ArrowState arrow,
  List<BindableState> bindables,
  EngineContext context, [
  List<String>? changedBindableIds,
  Map<String, dynamic>? options,
]) {
  final bindablesById = {
    for (final bindable in bindables) bindable.id: bindable,
  };
  var startBinding = arrow.startBinding;
  var endBinding = arrow.endBinding;

  final bindablePatches = <BindablePatch>[];
  final events = <ArrowEngineEvent>[];

  if (startBinding != null &&
      !bindablesById.containsKey(startBinding.elementId)) {
    bindablePatches.add(
      BindablePatch(id: startBinding.elementId, removeBoundArrowId: arrow.id),
    );
    events.add(BindingBrokenEvent(arrowId: arrow.id, edge: arrowEndpointStart));
    startBinding = null;
  }

  if (endBinding != null && !bindablesById.containsKey(endBinding.elementId)) {
    bindablePatches.add(
      BindablePatch(id: endBinding.elementId, removeBoundArrowId: arrow.id),
    );
    events.add(BindingBrokenEvent(arrowId: arrow.id, edge: arrowEndpointEnd));
    endBinding = null;
  }

  final nextPoints = arrow.points
      .map((point) => <double>[point[0], point[1]])
      .toList(growable: true);
  final simulatedArrow = arrow.copyWith(
    startBinding: startBinding,
    setStartBinding: true,
    endBinding: endBinding,
    setEndBinding: true,
    points: nextPoints,
  );

  final shouldUpdateStart =
      startBinding != null &&
      (changedBindableIds == null ||
          changedBindableIds.isEmpty ||
          changedBindableIds.contains(startBinding.elementId));
  final shouldUpdateEnd =
      endBinding != null &&
      (changedBindableIds == null ||
          changedBindableIds.isEmpty ||
          changedBindableIds.contains(endBinding.elementId));

  if (shouldUpdateStart && startBinding != null) {
    final bindable = bindablesById[startBinding.elementId]!;
    final updated = updateBoundPoint(
      arrow: simulatedArrow,
      edge: 'startBinding',
      binding: startBinding,
      bindable: bindable,
      bindablesById: bindablesById,
    );
    if (updated != null) {
      nextPoints[0] = updated;
    }
  }

  final simulatedWithStart = simulatedArrow.copyWith(points: nextPoints);

  if (shouldUpdateEnd && endBinding != null) {
    final bindable = bindablesById[endBinding.elementId]!;
    final updated = updateBoundPoint(
      arrow: simulatedWithStart,
      edge: 'endBinding',
      binding: endBinding,
      bindable: bindable,
      bindablesById: bindablesById,
    );
    if (updated != null) {
      nextPoints[nextPoints.length - 1] = updated;
    }
  }

  final origin = nextPoints.isNotEmpty ? nextPoints[0] : <double>[0, 0];
  final moveMidPointsWithElement =
      options != null && options['moveMidPointsWithElement'] == true;
  final lastIndex = nextPoints.length - 1;
  final normalizedPoints = nextPoints.indexed
      .map((entry) {
        final index = entry.$1;
        final point = entry.$2;
        if (moveMidPointsWithElement && index != 0 && index != lastIndex) {
          return point;
        }
        return <double>[point[0] - origin[0], point[1] - origin[1]];
      })
      .toList(growable: false);
  final bounds = computeBoundsFromPoints(normalizedPoints);

  return EngineResult(
    arrowPatch: <String, dynamic>{
      'x': arrow.x + origin[0],
      'y': arrow.y + origin[1],
      'points': normalizedPoints,
      'width': bounds.width,
      'height': bounds.height,
      'startBinding': startBinding,
      'endBinding': endBinding,
    },
    bindablePatches: bindablePatches,
    suggestedBinding: null,
    events: events,
  );
}

String getHeadingForElbowSnap({
  required Point point,
  required Point otherPoint,
  BindableState? bindable,
  Bounds? aabb,
  Point? originPoint,
  double? zoom,
}) {
  final otherPointHeading = vectorToHeading(point, otherPoint);
  if (bindable == null || aabb == null) {
    return otherPointHeading;
  }

  final distance = distanceToBindableOutline(originPoint ?? point, bindable);
  final bindDistance = maxBindingDistance(zoom ?? 1);
  final resolvedDistance = distance > bindDistance ? null : distance;

  // Keep legacy semantics: distance `0` is treated as null here.
  if (resolvedDistance == null || resolvedDistance == 0) {
    final bindableCenter = center(
      bindable.x,
      bindable.y,
      bindable.width,
      bindable.height,
    );
    return vectorToHeading(bindableCenter, point);
  }

  return _headingForPointFromBindable(point, bindable, aabb);
}

BindableState? pickHoveredBindable(
  Point point,
  List<BindableState> bindables,
  Object toleranceOrContext,
) {
  if (toleranceOrContext is EngineContext) {
    return getHoveredBindable(
      point,
      bindables,
      maxBindingDistance(toleranceOrContext.zoom),
    );
  }
  if (toleranceOrContext is num) {
    return getHoveredBindable(point, bindables, toleranceOrContext.toDouble());
  }
  return getHoveredBindable(point, bindables, 0);
}

List<BindableState> pickOverlappingBindables(
  Point point,
  List<BindableState> bindables,
  Object toleranceOrContext,
) {
  if (toleranceOrContext is EngineContext) {
    return getBindablesOverPoint(
      point,
      bindables,
      maxBindingDistance(toleranceOrContext.zoom),
    );
  }
  if (toleranceOrContext is num) {
    return getBindablesOverPoint(
      point,
      bindables,
      toleranceOrContext.toDouble(),
    );
  }
  return getBindablesOverPoint(point, bindables, 0);
}

List<BindableState> listHoveredBindables(
  Point point,
  List<BindableState> bindables,
  double tolerance, {
  bool stopAtOpaque = false,
}) {
  final zOrderedBindables = sortBindablesByZIndex(bindables);
  final hovered = <BindableState>[];

  for (var index = zOrderedBindables.length - 1; index >= 0; index -= 1) {
    final bindable = zOrderedBindables[index];
    final hit = isPointNearBindableForBindingHit(point, bindable, tolerance);
    if (!hit) {
      continue;
    }
    hovered.add(bindable);
    if (stopAtOpaque && isBindableBackgroundOpaque(bindable)) {
      break;
    }
  }

  return hovered;
}

BindableState? pickHoveredBindableForFocus(
  Point point,
  ArrowState arrow,
  List<BindableState> bindables, {
  double tolerance = 0,
}) {
  final candidates = listHoveredBindables(point, bindables, tolerance);
  if (candidates.isEmpty) {
    return null;
  }
  if (candidates.length == 1) {
    return candidates[0];
  }

  for (final bindable in candidates) {
    if (distanceToBindableOutline(point, bindable) <=
            getBindingGap(bindable, arrow.elbowed) ||
        isPointInBindable(point, bindable)) {
      return bindable;
    }
  }
  return null;
}

List<Point?> getGlobalFixedPoints(
  ArrowState arrow,
  List<BindableState> bindables,
) {
  final byId = {for (final bindable in bindables) bindable.id: bindable};
  final start = arrow.startBinding == null
      ? getPointAtIndexGlobal(arrow, 0)
      : byId[arrow.startBinding!.elementId] == null
      ? getPointAtIndexGlobal(arrow, 0)
      : getGlobalFixedPoint(
          arrow.startBinding!,
          byId[arrow.startBinding!.elementId]!,
        );
  final end = arrow.endBinding == null
      ? getPointAtIndexGlobal(arrow, -1)
      : byId[arrow.endBinding!.elementId] == null
      ? getPointAtIndexGlobal(arrow, -1)
      : getGlobalFixedPoint(
          arrow.endBinding!,
          byId[arrow.endBinding!.elementId]!,
        );
  return <Point?>[start, end];
}

List<Point?> getArrowLocalFixedPoints(
  ArrowState arrow,
  List<BindableState> bindables,
) {
  final global = getGlobalFixedPoints(arrow, bindables);
  final start = global[0] == null ? null : toLocalPoint(arrow, global[0]!);
  final end = global[1] == null ? null : toLocalPoint(arrow, global[1]!);
  return <Point?>[start, end];
}

double maxBindingDistanceSimple(double zoom) => maxBindingDistance(zoom);

Point bindPointToSnapToElementOutline({
  required ArrowState arrow,
  required BindableState bindable,
  required ArrowEndpointEdge edge,
  List<Point>? customIntersector,
}) => bindPointToOutline(
  arrow: arrow,
  bindable: bindable,
  edge: edge,
  customIntersector: customIntersector,
);

FixedPointBinding calculateFixedPointForElbowArrowBinding({
  required Point point,
  required BindableState bindable,
  BindMode mode = bindModeOrbit,
  ArrowState? arrow,
  ArrowEndpointEdge edge = arrowEndpointStart,
}) => calculateFixedPointForElbowBinding(
  point: point,
  bindable: bindable,
  mode: mode,
  arrow: arrow,
  edge: edge,
);

FixedPointBinding calculateFixedPointForNonElbowArrowBinding({
  required Point point,
  required BindableState bindable,
  BindMode mode = bindModeOrbit,
}) =>
    calculateFixedPointForBinding(point: point, bindable: bindable, mode: mode);

String getHeadingForElbowArrowSnap({
  required Point point,
  required Point otherPoint,
  BindableState? bindable,
  Bounds? aabb,
  Point? originPoint,
  double? zoom,
}) => getHeadingForElbowSnap(
  point: point,
  otherPoint: otherPoint,
  bindable: bindable,
  aabb: aabb,
  originPoint: originPoint,
  zoom: zoom,
);

Point getGlobalFixedPointForBindableElement(
  FixedPointBinding binding,
  BindableState bindable,
) => getGlobalFixedPoint(binding, bindable);
