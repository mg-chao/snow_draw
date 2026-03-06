import 'dart:math' as math;

import 'arrow_types.dart';

typedef Heading = String;

typedef BoundsSize = ({double width, double height});

typedef NormalizedArrowFromGlobalPoints = ({
  double x,
  double y,
  List<Point> points,
  double width,
  double height,
});

const double EPSILON = 1e-4;

double clamp(double value, double min, double max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

Point add(Point a, Point b) => [a[0] + b[0], a[1] + b[1]];

Point sub(Point a, Point b) => [a[0] - b[0], a[1] - b[1]];

Point scale(Point p, double factor) => [p[0] * factor, p[1] * factor];

Point center(double x, double y, double width, double height) => [
  x + width / 2,
  y + height / 2,
];

Point rotatePoint(Point point, Point around, double angle) {
  if (angle == 0) {
    return point;
  }
  final dx = point[0] - around[0];
  final dy = point[1] - around[1];
  final cosValue = math.cos(angle);
  final sinValue = math.sin(angle);
  return [
    around[0] + dx * cosValue - dy * sinValue,
    around[1] + dx * sinValue + dy * cosValue,
  ];
}

Point unrotatePoint(Point point, Point around, double angle) =>
    rotatePoint(point, around, -angle);

double distanceSq(Point a, Point b) {
  final dx = a[0] - b[0];
  final dy = a[1] - b[1];
  return dx * dx + dy * dy;
}

double distance(Point a, Point b) => math.sqrt(distanceSq(a, b));

double manhattan(Point a, Point b) => (a[0] - b[0]).abs() + (a[1] - b[1]).abs();

Point toGlobalPoint(ArrowState arrow, Point localPoint) => [
  arrow.x + localPoint[0],
  arrow.y + localPoint[1],
];

Point toLocalPoint(ArrowState arrow, Point globalPoint) => [
  globalPoint[0] - arrow.x,
  globalPoint[1] - arrow.y,
];

Point getPointAtIndex(ArrowState arrow, int indexMaybeFromEnd) {
  final index = indexMaybeFromEnd < 0
      ? arrow.points.length + indexMaybeFromEnd
      : indexMaybeFromEnd;
  if (index < 0 || index >= arrow.points.length) {
    return [0, 0];
  }
  return arrow.points[index];
}

Point getPointAtIndexGlobal(ArrowState arrow, int indexMaybeFromEnd) =>
    toGlobalPoint(arrow, getPointAtIndex(arrow, indexMaybeFromEnd));

Point normalizeFixedPoint(Point ratio) {
  final x = ratio[0].isFinite ? ratio[0] : 0.5001;
  final y = ratio[1].isFinite ? ratio[1] : 0.5001;
  final adjustedX = (x - 0.5).abs() < EPSILON ? 0.5001 : x;
  final adjustedY = (y - 0.5).abs() < EPSILON ? 0.5001 : y;
  return [adjustedX, adjustedY];
}

bool isFixedPoint(Object? value) {
  if (value is! List || value.length != 2) {
    return false;
  }
  final x = value[0];
  final y = value[1];
  return x is num && x.isFinite && y is num && y.isFinite;
}

Point getGlobalFixedPoint(FixedPointBinding binding, BindableState bindable) {
  final fixedPoint = normalizeFixedPoint(binding.fixedPoint);
  final fx = fixedPoint[0];
  final fy = fixedPoint[1];
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );
  final point = [
    bindable.x + bindable.width * fx,
    bindable.y + bindable.height * fy,
  ];
  return rotatePoint(point, bindableCenter, bindable.angle);
}

BoundsSize computeBoundsFromPoints(List<Point> points) {
  if (points.isEmpty) {
    return (width: 0, height: 0);
  }
  var minX = points[0][0];
  var minY = points[0][1];
  var maxX = points[0][0];
  var maxY = points[0][1];
  for (final point in points) {
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
  return (width: maxX - minX, height: maxY - minY);
}

NormalizedArrowFromGlobalPoints normalizeArrowFromGlobalPoints(
  List<Point> globalPoints,
  double maxCoordinate,
) {
  if (globalPoints.isEmpty) {
    return (x: 0, y: 0, points: <Point>[], width: 0, height: 0);
  }
  final origin = globalPoints[0];
  final points = globalPoints
      .map(
        (point) => [
          clamp(point[0] - origin[0], -maxCoordinate, maxCoordinate),
          clamp(point[1] - origin[1], -maxCoordinate, maxCoordinate),
        ],
      )
      .toList();
  final bounds = computeBoundsFromPoints(points);
  return (
    x: clamp(origin[0], -maxCoordinate, maxCoordinate),
    y: clamp(origin[1], -maxCoordinate, maxCoordinate),
    points: points,
    width: bounds.width,
    height: bounds.height,
  );
}

Heading vectorToHeading(Point from, Point to) {
  final x = to[0] - from[0];
  final y = to[1] - from[1];
  final absX = x.abs();
  final absY = y.abs();
  if (x > absY) {
    return 'right';
  }
  if (x <= -absY) {
    return 'left';
  }
  if (y > absX) {
    return 'down';
  }
  return 'up';
}

bool isHorizontalHeading(Heading heading) =>
    heading == 'left' || heading == 'right';

Point headingToDelta(Heading heading) {
  switch (heading) {
    case 'up':
      return [0, -1];
    case 'right':
      return [1, 0];
    case 'down':
      return [0, 1];
    case 'left':
      return [-1, 0];
  }
  return [0, 0];
}

Heading reverseHeading(Heading heading) {
  switch (heading) {
    case 'up':
      return 'down';
    case 'right':
      return 'left';
    case 'down':
      return 'up';
    case 'left':
      return 'right';
  }
  return heading;
}

Heading headingFromBindable(Point point, BindableState bindable) {
  final shape = canonicalizeBindableShape(bindable.shape);
  final isDiamondShape = shape == 'diamond';
  const searchConeMultiplier = 2.0;
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );

  Point scaleFromOrigin(Point inputPoint, Point origin, double factor) => [
    origin[0] + (inputPoint[0] - origin[0]) * factor,
    origin[1] + (inputPoint[1] - origin[1]) * factor,
  ];
  Point vectorFromPoint(Point inputPoint, Point origin) => [
    inputPoint[0] - origin[0],
    inputPoint[1] - origin[1],
  ];
  double cross(Point left, Point right) =>
      left[0] * right[1] - left[1] * right[0];

  final aabb = () {
    final cornerPoints = <Point>[
      [bindable.x, bindable.y],
      [bindable.x + bindable.width, bindable.y],
      [bindable.x + bindable.width, bindable.y + bindable.height],
      [bindable.x, bindable.y + bindable.height],
    ];
    final corners = cornerPoints
        .map((corner) => rotatePoint(corner, bindableCenter, bindable.angle))
        .toList();

    var minX = corners[0][0];
    var minY = corners[0][1];
    var maxX = corners[0][0];
    var maxY = corners[0][1];
    for (final corner in corners) {
      minX = math.min(minX, corner[0]);
      minY = math.min(minY, corner[1]);
      maxX = math.max(maxX, corner[0]);
      maxY = math.max(maxY, corner[1]);
    }
    return [minX, minY, maxX, maxY];
  }();

  Heading headingForPoint(Point from, Point to) => vectorToHeading(from, to);

  final midPoint = [(aabb[0] + aabb[2]) / 2, (aabb[1] + aabb[3]) / 2];

  if (isDiamondShape) {
    const shrink = 0.95;
    final top = scaleFromOrigin(
      rotatePoint(
        [bindable.x + bindable.width / 2, bindable.y],
        bindableCenter,
        bindable.angle,
      ),
      midPoint,
      shrink,
    );
    final right = scaleFromOrigin(
      rotatePoint(
        [bindable.x + bindable.width, bindable.y + bindable.height / 2],
        bindableCenter,
        bindable.angle,
      ),
      midPoint,
      shrink,
    );
    final bottom = scaleFromOrigin(
      rotatePoint(
        [bindable.x + bindable.width / 2, bindable.y + bindable.height],
        bindableCenter,
        bindable.angle,
      ),
      midPoint,
      shrink,
    );
    final left = scaleFromOrigin(
      rotatePoint(
        [bindable.x, bindable.y + bindable.height / 2],
        bindableCenter,
        bindable.angle,
      ),
      midPoint,
      shrink,
    );

    if (cross(vectorFromPoint(point, top), vectorFromPoint(top, right)) <= 0 &&
        cross(vectorFromPoint(point, top), vectorFromPoint(top, left)) > 0) {
      return headingForPoint(top, midPoint);
    }
    if (cross(vectorFromPoint(point, right), vectorFromPoint(right, bottom)) <=
            0 &&
        cross(vectorFromPoint(point, right), vectorFromPoint(right, top)) > 0) {
      return headingForPoint(right, midPoint);
    }
    if (cross(vectorFromPoint(point, bottom), vectorFromPoint(bottom, left)) <=
            0 &&
        cross(vectorFromPoint(point, bottom), vectorFromPoint(bottom, right)) >
            0) {
      return headingForPoint(bottom, midPoint);
    }
    if (cross(vectorFromPoint(point, left), vectorFromPoint(left, top)) <= 0 &&
        cross(vectorFromPoint(point, left), vectorFromPoint(left, bottom)) >
            0) {
      return headingForPoint(left, midPoint);
    }

    if (cross(
              vectorFromPoint(point, midPoint),
              vectorFromPoint(top, midPoint),
            ) <=
            0 &&
        cross(
              vectorFromPoint(point, midPoint),
              vectorFromPoint(right, midPoint),
            ) >
            0) {
      final reference = bindable.width > bindable.height ? top : right;
      return headingForPoint(reference, midPoint);
    }
    if (cross(
              vectorFromPoint(point, midPoint),
              vectorFromPoint(right, midPoint),
            ) <=
            0 &&
        cross(
              vectorFromPoint(point, midPoint),
              vectorFromPoint(bottom, midPoint),
            ) >
            0) {
      final reference = bindable.width > bindable.height ? bottom : right;
      return headingForPoint(reference, midPoint);
    }
    if (cross(
              vectorFromPoint(point, midPoint),
              vectorFromPoint(bottom, midPoint),
            ) <=
            0 &&
        cross(
              vectorFromPoint(point, midPoint),
              vectorFromPoint(left, midPoint),
            ) >
            0) {
      final reference = bindable.width > bindable.height ? bottom : left;
      return headingForPoint(reference, midPoint);
    }

    final reference = bindable.width > bindable.height ? top : left;
    return headingForPoint(reference, midPoint);
  }

  final topLeft = scaleFromOrigin(
    [aabb[0], aabb[1]],
    midPoint,
    searchConeMultiplier,
  );
  final topRight = scaleFromOrigin(
    [aabb[2], aabb[1]],
    midPoint,
    searchConeMultiplier,
  );
  final bottomLeft = scaleFromOrigin(
    [aabb[0], aabb[3]],
    midPoint,
    searchConeMultiplier,
  );
  final bottomRight = scaleFromOrigin(
    [aabb[2], aabb[3]],
    midPoint,
    searchConeMultiplier,
  );

  double sign(Point a, Point b, Point c) =>
      (a[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (a[1] - c[1]);
  bool pointInTriangle(Point p, Point a, Point b, Point c) {
    final d1 = sign(p, a, b);
    final d2 = sign(p, b, c);
    final d3 = sign(p, c, a);
    final hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
    final hasPos = d1 > 0 || d2 > 0 || d3 > 0;
    return !(hasNeg && hasPos);
  }

  if (pointInTriangle(point, topLeft, topRight, midPoint)) {
    return 'up';
  }
  if (pointInTriangle(point, topRight, bottomRight, midPoint)) {
    return 'right';
  }
  if (pointInTriangle(point, bottomRight, bottomLeft, midPoint)) {
    return 'down';
  }
  return 'left';
}

bool pointsEqual(Point a, Point b, [double tolerance = EPSILON]) =>
    (a[0] - b[0]).abs() <= tolerance && (a[1] - b[1]).abs() <= tolerance;

bool isOrthogonalPath(List<Point> points, [double tolerance = 1]) {
  for (var i = 1; i < points.length; i += 1) {
    final prev = points[i - 1];
    final current = points[i];
    if ((current[0] - prev[0]).abs() > tolerance &&
        (current[1] - prev[1]).abs() > tolerance) {
      return false;
    }
  }
  return true;
}

List<Point> dedupeCollinearPoints(List<Point> points) {
  if (points.length <= 2) {
    return List<Point>.from(points);
  }
  final result = <Point>[points[0]];
  for (var i = 1; i < points.length - 1; i += 1) {
    final prev = result[result.length - 1];
    final current = points[i];
    final next = points[i + 1];
    final horizontalPrev = (prev[1] - current[1]).abs() <= 1e-6;
    final horizontalNext = (current[1] - next[1]).abs() <= 1e-6;
    final verticalPrev = (prev[0] - current[0]).abs() <= 1e-6;
    final verticalNext = (current[0] - next[0]).abs() <= 1e-6;
    if ((horizontalPrev && horizontalNext) || (verticalPrev && verticalNext)) {
      continue;
    }
    result.add(current);
  }
  result.add(points[points.length - 1]);
  return result;
}
