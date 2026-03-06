import 'dart:math' as math;

import 'arrow_geom.dart';
import 'arrow_render_core.dart';
import 'arrow_types.dart';

class _CubicSegment {
  const _CubicSegment({
    required this.start,
    required this.control1,
    required this.control2,
    required this.end,
  });

  final Point start;
  final Point control1;
  final Point control2;
  final Point end;
}

typedef RectNormalizedPoints = ({Bounds rect, List<Point> normalizedPoints});
typedef RectAndLocalPoints = ({Bounds rect, List<Point> localPoints});

/// Resolves the canonical arrowhead length from [strokeWidth].
///
/// Keep this formula stable so host rendering, hit-testing, and geometry
/// updates remain aligned across integrations.
double resolveArrowheadLength(double strokeWidth) => strokeWidth * 4 + 12.0;

const _defaultArrowPoints = <Point>[
  <double>[0, 0],
  <double>[1, 1],
];

List<Point> ensureMinimumArrowPoints(List<Point> points) {
  if (points.length >= 2) {
    return points;
  }
  if (points.isEmpty) {
    return _defaultArrowPoints;
  }
  final first = points.first;
  return <Point>[
    <double>[first[0], first[1]],
    <double>[first[0], first[1]],
  ];
}

List<Point> denormalizeRectPoints({
  required Bounds rect,
  required List<Point> normalizedPoints,
}) {
  final points = ensureMinimumArrowPoints(normalizedPoints);
  final width = rect[2] - rect[0];
  final height = rect[3] - rect[1];
  return points
      .map(
        (point) => <double>[
          rect[0] + point[0] * width,
          rect[1] + point[1] * height,
        ],
      )
      .toList(growable: false);
}

List<Point> normalizeRectPoints({
  required Bounds rect,
  required List<Point> worldPoints,
  bool clamp = true,
}) {
  final points = ensureMinimumArrowPoints(worldPoints);
  final width = rect[2] - rect[0];
  final height = rect[3] - rect[1];
  return points
      .map((point) {
        final x = width == 0 ? 0.0 : (point[0] - rect[0]) / width;
        final y = height == 0 ? 0.0 : (point[1] - rect[1]) / height;
        if (!clamp) {
          return <double>[x, y];
        }
        return <double>[_clamp01(x), _clamp01(y)];
      })
      .toList(growable: false);
}

RectNormalizedPoints computeRectNormalizedPoints({
  required List<Point> worldPoints,
  required bool curved,
}) {
  final points = ensureMinimumArrowPoints(worldPoints);
  final rect = calculateArrowPathBounds(points: points, curved: curved);
  final normalizedPoints = normalizeRectPoints(rect: rect, worldPoints: points);
  return (rect: rect, normalizedPoints: normalizedPoints);
}

RectNormalizedPoints computeTwoPointRectNormalizedPoints({
  required Point first,
  required Point second,
}) {
  final rect = <double>[
    math.min(first[0], second[0]),
    math.min(first[1], second[1]),
    math.max(first[0], second[0]),
    math.max(first[1], second[1]),
  ];
  final normalizedPoints = normalizeRectPoints(
    rect: rect,
    worldPoints: <Point>[first, second],
  );
  return (rect: rect, normalizedPoints: normalizedPoints);
}

RectAndLocalPoints computeRotatedRectAndLocalPoints({
  required List<Point> localPoints,
  required Bounds oldRect,
  required double rotation,
  required bool curved,
}) {
  final points = ensureMinimumArrowPoints(localPoints);
  if (rotation == 0) {
    return (
      rect: calculateArrowPathBounds(points: points, curved: curved),
      localPoints: points,
    );
  }

  final oldCenter = <double>[
    (oldRect[0] + oldRect[2]) / 2,
    (oldRect[1] + oldRect[3]) / 2,
  ];
  final worldPoints = points
      .map((point) => rotatePoint(point, oldCenter, rotation))
      .toList(growable: false);

  final cosTheta = math.cos(rotation);
  final sinTheta = math.sin(rotation);
  final rotatedWorldPoints = worldPoints
      .map(
        (point) => <double>[
          point[0] * cosTheta + point[1] * sinTheta,
          -point[0] * sinTheta + point[1] * cosTheta,
        ],
      )
      .toList(growable: false);
  final rotatedBounds = calculateArrowPathBounds(
    points: rotatedWorldPoints,
    curved: curved,
  );
  final rotatedCenter = <double>[
    (rotatedBounds[0] + rotatedBounds[2]) / 2,
    (rotatedBounds[1] + rotatedBounds[3]) / 2,
  ];

  final newCenter = <double>[
    rotatedCenter[0] * cosTheta - rotatedCenter[1] * sinTheta,
    rotatedCenter[0] * sinTheta + rotatedCenter[1] * cosTheta,
  ];
  final nextLocalPoints = worldPoints
      .map((point) => unrotatePoint(point, newCenter, rotation))
      .toList(growable: false);
  final rect = calculateArrowPathBounds(
    points: nextLocalPoints,
    curved: curved,
  );
  return (rect: rect, localPoints: nextLocalPoints);
}

List<Point> sampleElbowPathForHitTest({
  required List<Point> points,
  required double strokeWidth,
  double radius = 16,
}) {
  if (points.length < 2) {
    return points;
  }

  final safeRadius = (radius.isFinite && radius > 0) ? radius : 0.0;
  final pathData = generateElbowArrowPath(points, safeRadius);
  if (pathData.isEmpty) {
    return points;
  }

  final commands = _parseElbowPathCommands(pathData);
  if (commands == null || commands.isEmpty) {
    return points;
  }

  final flattened = <Point>[];
  Point? current;
  for (final command in commands) {
    switch (command) {
      case _ElbowMoveTo():
        _appendPointIfDistinct(flattened, command.point);
        current = command.point;
      case _ElbowLineTo():
        _appendPointIfDistinct(flattened, command.point);
        current = command.point;
      case _ElbowQuadraticTo():
        final start = current;
        if (start == null) {
          return points;
        }
        final chordLength = distance(command.end, start);
        final roughLength =
            chordLength + distance(command.control, start) * 0.5;
        final stepSize = math.max(1.5, strokeWidth * 0.7);
        final steps = roughLength <= 0 ? 6 : roughLength ~/ stepSize + 1;
        final clampedSteps = steps.clamp(6, 32);
        for (var i = 1; i <= clampedSteps; i++) {
          final t = i / clampedSteps;
          final point = _quadraticPoint(start, command.control, command.end, t);
          _appendPointIfDistinct(flattened, point);
        }
        current = command.end;
    }
  }

  return flattened.length >= 2 ? flattened : points;
}

/// Resolves the shaft inset needed for [arrowhead] at [strokeWidth].
double calculateArrowheadInset({
  required Arrowhead? arrowhead,
  required double strokeWidth,
}) {
  if (arrowhead == null || strokeWidth <= 0) {
    return 0;
  }
  final length = resolveArrowheadLength(strokeWidth);
  return switch (arrowhead) {
    'dot' || 'circle' || 'circle_outline' || 'square' => length * 0.6,
    'triangle' ||
    'triangle_outline' ||
    'diamond' ||
    'diamond_outline' => length,
    _ => 0,
  };
}

/// Resolves the direction-sampling offset for [arrowhead] at [strokeWidth].
double calculateArrowheadDirectionOffset({
  required Arrowhead? arrowhead,
  required double strokeWidth,
}) {
  if (arrowhead == null || strokeWidth <= 0) {
    return 0;
  }
  final length = resolveArrowheadLength(strokeWidth);
  return switch (arrowhead) {
    'dot' || 'circle' || 'circle_outline' || 'square' || 'bar' => length * 0.6,
    'arrow' ||
    'triangle' ||
    'triangle_outline' ||
    'diamond' ||
    'diamond_outline' ||
    'crowfoot_one' ||
    'crowfoot_many' ||
    'crowfoot_one_or_many' ||
    'inverted_triangle' => length,
    _ => 0,
  };
}

/// Calculates the visible shaft length for an arrow polyline.
double calculateArrowShaftLength({
  required List<Point> points,
  required bool curved,
}) {
  if (points.length < 2) {
    return 0;
  }
  if (curved && points.length > 2) {
    return _approximateCurvedLength(points);
  }
  return _calculatePolylineLength(points);
}

/// Calculates the point on a curve/polyline segment at progress [t].
Point? calculateCurvePoint({
  required List<Point> points,
  required int segmentIndex,
  required double t,
}) {
  if (points.length < 2 ||
      segmentIndex < 0 ||
      segmentIndex >= points.length - 1) {
    return null;
  }

  if (points.length < 3) {
    final p1 = points[segmentIndex];
    final p2 = points[segmentIndex + 1];
    return <double>[p1[0] + (p2[0] - p1[0]) * t, p1[1] + (p2[1] - p1[1]) * t];
  }

  return _evaluateCubic(_buildCubicSegment(points, segmentIndex), t);
}

/// Calculates path bounds for [points].
///
/// For curved arrows, cubic Catmull-Rom interpolation bounds are evaluated.
Bounds calculateArrowPathBounds({
  required List<Point> points,
  required bool curved,
}) {
  if (points.isEmpty) {
    return const <double>[0, 0, 0, 0];
  }

  if (!curved || points.length < 3) {
    return _boundsFromPoints(points);
  }

  var minX = points.first[0];
  var maxX = points.first[0];
  var minY = points.first[1];
  var maxY = points.first[1];

  for (var index = 0; index < points.length - 1; index++) {
    final segment = _buildCubicSegment(points, index);
    _expandBoundsForCubic(
      segment: segment,
      minX: (value) => minX = math.min(minX, value),
      maxX: (value) => maxX = math.max(maxX, value),
      minY: (value) => minY = math.min(minY, value),
      maxY: (value) => maxY = math.max(maxY, value),
    );
  }

  return <double>[minX, minY, maxX, maxY];
}

/// Applies endpoint insets to [points].
///
/// Insets trim the polyline from the start/end while preserving segment turns.
List<Point> applyArrowEndpointInsets({
  required List<Point> points,
  required double startInset,
  required double endInset,
}) {
  if (points.length < 2) {
    return points;
  }

  var adjustedPoints = points;
  if (startInset > 0) {
    adjustedPoints = _insetFromStart(adjustedPoints, startInset);
    if (adjustedPoints.length < 2) {
      return adjustedPoints;
    }
  }

  if (endInset > 0) {
    adjustedPoints = _insetFromEnd(adjustedPoints, endInset);
  }

  return adjustedPoints;
}

/// Resolves the normalized start direction vector for [points].
Point? resolveArrowStartDirection({
  required List<Point> points,
  required bool curved,
  double startInset = 0,
  double endInset = 0,
  double directionOffset = 0,
}) {
  if (points.length < 2) {
    return null;
  }

  final hasInsets = startInset > 0 || endInset > 0;
  final workingPoints = hasInsets
      ? applyArrowEndpointInsets(
          points: points,
          startInset: startInset,
          endInset: endInset,
        )
      : points;
  if (workingPoints.length < 2) {
    return null;
  }

  if (curved && workingPoints.length > 2) {
    final effectiveOffset = math
        .max(0, directionOffset - startInset)
        .toDouble();
    final direction = _CurvedPathAnalysis(
      workingPoints,
    ).directionFromStart(effectiveOffset);
    if (direction != null) {
      return <double>[-direction[0], -direction[1]];
    }
  }

  return _normalize(<double>[
    workingPoints.first[0] - workingPoints[1][0],
    workingPoints.first[1] - workingPoints[1][1],
  ]);
}

/// Resolves the normalized end direction vector for [points].
Point? resolveArrowEndDirection({
  required List<Point> points,
  required bool curved,
  double startInset = 0,
  double endInset = 0,
  double directionOffset = 0,
}) {
  if (points.length < 2) {
    return null;
  }

  final hasInsets = startInset > 0 || endInset > 0;
  final workingPoints = hasInsets
      ? applyArrowEndpointInsets(
          points: points,
          startInset: startInset,
          endInset: endInset,
        )
      : points;
  if (workingPoints.length < 2) {
    return null;
  }

  if (curved && workingPoints.length > 2) {
    final effectiveOffset = math.max(0, directionOffset - endInset).toDouble();
    final direction = _CurvedPathAnalysis(
      workingPoints,
    ).directionFromEnd(effectiveOffset);
    if (direction != null) {
      return direction;
    }
  }

  return _normalize(<double>[
    workingPoints.last[0] - workingPoints[workingPoints.length - 2][0],
    workingPoints.last[1] - workingPoints[workingPoints.length - 2][1],
  ]);
}

double _clamp01(double value) {
  if (!value.isFinite) {
    return 0;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}

sealed class _ElbowPathCommand {
  const _ElbowPathCommand();
}

final class _ElbowMoveTo extends _ElbowPathCommand {
  const _ElbowMoveTo(this.point);

  final Point point;
}

final class _ElbowLineTo extends _ElbowPathCommand {
  const _ElbowLineTo(this.point);

  final Point point;
}

final class _ElbowQuadraticTo extends _ElbowPathCommand {
  const _ElbowQuadraticTo({required this.control, required this.end});

  final Point control;
  final Point end;
}

List<_ElbowPathCommand>? _parseElbowPathCommands(String pathData) {
  final normalized = pathData.trim();
  if (normalized.isEmpty) {
    return const <_ElbowPathCommand>[];
  }

  final tokens = normalized
      .replaceAllMapped(RegExp('([MLQ])'), (match) => ' ${match.group(1)} ')
      .trim()
      .split(RegExp(r'[\s,]+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  if (tokens.isEmpty) {
    return const <_ElbowPathCommand>[];
  }

  final commands = <_ElbowPathCommand>[];
  var index = 0;
  while (index < tokens.length) {
    final token = tokens[index++];
    switch (token) {
      case 'M':
      case 'L':
        if (index + 1 >= tokens.length) {
          return null;
        }
        final x = double.tryParse(tokens[index++]);
        final y = double.tryParse(tokens[index++]);
        if (x == null || y == null) {
          return null;
        }
        final point = <double>[x, y];
        if (token == 'M') {
          commands.add(_ElbowMoveTo(point));
        } else {
          commands.add(_ElbowLineTo(point));
        }
      case 'Q':
        if (index + 3 >= tokens.length) {
          return null;
        }
        final cx = double.tryParse(tokens[index++]);
        final cy = double.tryParse(tokens[index++]);
        final ex = double.tryParse(tokens[index++]);
        final ey = double.tryParse(tokens[index++]);
        if (cx == null || cy == null || ex == null || ey == null) {
          return null;
        }
        commands.add(
          _ElbowQuadraticTo(control: <double>[cx, cy], end: <double>[ex, ey]),
        );
      default:
        return null;
    }
  }

  return commands;
}

void _appendPointIfDistinct(List<Point> points, Point point) {
  if (points.isEmpty) {
    points.add(point);
    return;
  }
  final previous = points.last;
  if ((previous[0] - point[0]).abs() <= 1e-6 &&
      (previous[1] - point[1]).abs() <= 1e-6) {
    return;
  }
  points.add(point);
}

Point _quadraticPoint(Point start, Point control, Point end, double t) {
  final oneMinusT = 1 - t;
  final oneMinusTSq = oneMinusT * oneMinusT;
  final tSq = t * t;
  return <double>[
    oneMinusTSq * start[0] + 2 * oneMinusT * t * control[0] + tSq * end[0],
    oneMinusTSq * start[1] + 2 * oneMinusT * t * control[1] + tSq * end[1],
  ];
}

Bounds _boundsFromPoints(List<Point> points) {
  var minX = points.first[0];
  var maxX = points.first[0];
  var minY = points.first[1];
  var maxY = points.first[1];
  for (final point in points) {
    minX = math.min(minX, point[0]);
    maxX = math.max(maxX, point[0]);
    minY = math.min(minY, point[1]);
    maxY = math.max(maxY, point[1]);
  }
  return <double>[minX, minY, maxX, maxY];
}

Point? _normalize(Point point) {
  final length = distance(point, const <double>[0, 0]);
  if (length == 0) {
    return null;
  }
  return <double>[point[0] / length, point[1] / length];
}

double _approximateCurvedLength(List<Point> points) {
  if (points.length < 2) {
    return 0;
  }

  var length = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    final segment = _buildCubicSegment(points, i);
    length += _approximateCubicLength(segment);
  }
  return length;
}

double _calculatePolylineLength(List<Point> points) {
  var length = 0.0;
  for (var index = 1; index < points.length; index++) {
    length += distance(points[index], points[index - 1]);
  }
  return length;
}

_CubicSegment _buildCubicSegment(List<Point> points, int index) {
  final p0 = index == 0 ? points[index] : points[index - 1];
  final p1 = points[index];
  final p2 = points[index + 1];
  final p3 = index + 2 < points.length ? points[index + 2] : points[index + 1];

  const tension = 1.0;
  final control1 = <double>[
    p1[0] + (p2[0] - p0[0]) * (tension / 6),
    p1[1] + (p2[1] - p0[1]) * (tension / 6),
  ];
  final control2 = <double>[
    p2[0] - (p3[0] - p1[0]) * (tension / 6),
    p2[1] - (p3[1] - p1[1]) * (tension / 6),
  ];

  return _CubicSegment(
    start: p1,
    control1: control1,
    control2: control2,
    end: p2,
  );
}

double _approximateCubicLength(_CubicSegment segment) {
  const steps = 8;
  var length = 0.0;
  var previous = segment.start;
  for (var index = 1; index <= steps; index++) {
    final t = index / steps;
    final point = _evaluateCubic(segment, t);
    length += distance(point, previous);
    previous = point;
  }
  return length;
}

Point _evaluateCubic(_CubicSegment segment, double t) {
  final mt = 1 - t;
  final mt2 = mt * mt;
  final t2 = t * t;
  final a = mt2 * mt;
  final b = 3 * mt2 * t;
  final c = 3 * mt * t2;
  final d = t2 * t;
  return <double>[
    segment.start[0] * a +
        segment.control1[0] * b +
        segment.control2[0] * c +
        segment.end[0] * d,
    segment.start[1] * a +
        segment.control1[1] * b +
        segment.control2[1] * c +
        segment.end[1] * d,
  ];
}

Point _cubicTangent(_CubicSegment segment, double t) {
  final mt = 1 - t;
  final a = <double>[
    (segment.control1[0] - segment.start[0]) * (3 * mt * mt),
    (segment.control1[1] - segment.start[1]) * (3 * mt * mt),
  ];
  final b = <double>[
    (segment.control2[0] - segment.control1[0]) * (6 * mt * t),
    (segment.control2[1] - segment.control1[1]) * (6 * mt * t),
  ];
  final c = <double>[
    (segment.end[0] - segment.control2[0]) * (3 * t * t),
    (segment.end[1] - segment.control2[1]) * (3 * t * t),
  ];
  return <double>[a[0] + b[0] + c[0], a[1] + b[1] + c[1]];
}

void _expandBoundsForCubic({
  required _CubicSegment segment,
  required void Function(double) minX,
  required void Function(double) maxX,
  required void Function(double) minY,
  required void Function(double) maxY,
}) {
  final tValues = <double>{0.0, 1.0}
    ..addAll(
      _cubicDerivativeRoots(
        segment.start[0],
        segment.control1[0],
        segment.control2[0],
        segment.end[0],
      ),
    )
    ..addAll(
      _cubicDerivativeRoots(
        segment.start[1],
        segment.control1[1],
        segment.control2[1],
        segment.end[1],
      ),
    );

  for (final t in tValues) {
    final point = _evaluateCubic(segment, t);
    minX(point[0]);
    maxX(point[0]);
    minY(point[1]);
    maxY(point[1]);
  }
}

List<double> _cubicDerivativeRoots(double p0, double p1, double p2, double p3) {
  const epsilon = 1e-9;
  final a = -p0 + 3 * p1 - 3 * p2 + p3;
  final b = 3 * p0 - 6 * p1 + 3 * p2;
  final c = -3 * p0 + 3 * p1;

  if (a.abs() < epsilon) {
    if (b.abs() < epsilon) {
      return const <double>[];
    }
    final t = -c / (2 * b);
    if (t > 0 && t < 1) {
      return <double>[t];
    }
    return const <double>[];
  }

  final A = 3 * a;
  final B = 2 * b;
  final C = c;
  final discriminant = B * B - 4 * A * C;
  if (discriminant < 0) {
    return const <double>[];
  }
  final sqrtDisc = math.sqrt(discriminant);
  final denom = 2 * A;
  if (denom.abs() < epsilon) {
    return const <double>[];
  }

  final t1 = (-B + sqrtDisc) / denom;
  final t2 = (-B - sqrtDisc) / denom;
  final roots = <double>[];
  if (t1 > 0 && t1 < 1) {
    roots.add(t1);
  }
  if (t2 > 0 && t2 < 1) {
    roots.add(t2);
  }
  return roots;
}

List<Point> _insetFromStart(List<Point> points, double inset) {
  if (points.length < 2 || inset <= 0) {
    return points;
  }

  var remainingInset = inset;
  for (var index = 0; index < points.length - 1; index++) {
    final segmentVector = <double>[
      points[index + 1][0] - points[index][0],
      points[index + 1][1] - points[index][1],
    ];
    final segmentLength = distance(segmentVector, const <double>[0, 0]);
    if (segmentLength <= 0) {
      continue;
    }

    if (remainingInset < segmentLength) {
      final direction = <double>[
        segmentVector[0] / segmentLength,
        segmentVector[1] / segmentLength,
      ];
      final newStart = <double>[
        points[index][0] + direction[0] * remainingInset,
        points[index][1] + direction[1] * remainingInset,
      ];
      return <Point>[newStart, ...points.sublist(index + 1)];
    }

    remainingInset -= segmentLength;
  }

  return <Point>[points.last];
}

List<Point> _insetFromEnd(List<Point> points, double inset) {
  if (points.length < 2 || inset <= 0) {
    return points;
  }

  var remainingInset = inset;
  for (var index = points.length - 1; index > 0; index--) {
    final segmentVector = <double>[
      points[index - 1][0] - points[index][0],
      points[index - 1][1] - points[index][1],
    ];
    final segmentLength = distance(segmentVector, const <double>[0, 0]);
    if (segmentLength <= 0) {
      continue;
    }

    if (remainingInset < segmentLength) {
      final direction = <double>[
        segmentVector[0] / segmentLength,
        segmentVector[1] / segmentLength,
      ];
      final newEnd = <double>[
        points[index][0] + direction[0] * remainingInset,
        points[index][1] + direction[1] * remainingInset,
      ];
      return <Point>[...points.sublist(0, index), newEnd];
    }

    remainingInset -= segmentLength;
  }

  return <Point>[points.first];
}

class _CurvedPathAnalysis {
  _CurvedPathAnalysis(List<Point> points)
    : segments = List<_CubicSegment>.generate(
        points.length - 1,
        (index) => _buildCubicSegment(points, index),
      ),
      lengths = List<double>.filled(points.length - 1, 0) {
    var total = 0.0;
    for (var i = 0; i < segments.length; i++) {
      final length = _approximateCubicLength(segments[i]);
      lengths[i] = length;
      total += length;
    }
    totalLength = total;
  }

  final List<_CubicSegment> segments;
  final List<double> lengths;
  late final double totalLength;

  Point? directionFromStart(double offset) {
    if (segments.isEmpty) {
      return null;
    }
    var remaining = offset.isFinite ? offset : 0.0;
    if (remaining < 0) {
      remaining = 0;
    }

    for (var index = 0; index < segments.length; index++) {
      final length = lengths[index];
      if (length <= 0) {
        continue;
      }
      if (remaining <= length || index == segments.length - 1) {
        final t = (remaining / length).clamp(0.0, 1.0);
        return _normalize(_cubicTangent(segments[index], t));
      }
      remaining -= length;
    }
    return null;
  }

  Point? directionFromEnd(double offset) {
    if (segments.isEmpty) {
      return null;
    }
    var remaining = offset.isFinite ? offset : 0.0;
    if (remaining < 0) {
      remaining = 0;
    }

    for (var index = segments.length - 1; index >= 0; index--) {
      final length = lengths[index];
      if (length <= 0) {
        continue;
      }
      if (remaining <= length || index == 0) {
        final t = (1.0 - (remaining / length)).clamp(0.0, 1.0);
        return _normalize(_cubicTangent(segments[index], t));
      }
      remaining -= length;
    }
    return null;
  }
}
