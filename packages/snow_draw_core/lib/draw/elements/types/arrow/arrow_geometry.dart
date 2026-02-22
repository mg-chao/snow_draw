import 'dart:math' as math;

import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import 'arrow_like_data.dart';

class _CubicSegment {
  const _CubicSegment({
    required this.start,
    required this.control1,
    required this.control2,
    required this.end,
  });

  final DrawPoint start;
  final DrawPoint control1;
  final DrawPoint control2;
  final DrawPoint end;
}

class ArrowGeometry {
  const ArrowGeometry._();

  static const _defaultPoints = <DrawPoint>[
    DrawPoint.zero,
    DrawPoint(x: 1, y: 1),
  ];

  static List<DrawPoint> resolveLocalPoints({
    required DrawRect rect,
    required List<DrawPoint> normalizedPoints,
  }) {
    final points = _ensureMinPoints(normalizedPoints);
    final width = rect.width;
    final height = rect.height;
    return points
        .map((point) => DrawPoint(x: point.x * width, y: point.y * height))
        .toList(growable: false);
  }

  static List<DrawPoint> resolveWorldPoints({
    required DrawRect rect,
    required List<DrawPoint> normalizedPoints,
  }) {
    final points = _ensureMinPoints(normalizedPoints);
    final width = rect.width;
    final height = rect.height;
    return points
        .map(
          (point) => DrawPoint(
            x: rect.minX + point.x * width,
            y: rect.minY + point.y * height,
          ),
        )
        .toList(growable: false);
  }

  static List<DrawPoint> normalizePoints({
    required List<DrawPoint> worldPoints,
    required DrawRect rect,
  }) {
    final points = _ensureMinPoints(worldPoints);
    final width = rect.width;
    final height = rect.height;
    return List<DrawPoint>.unmodifiable(
      points.map((point) {
        final x = width == 0 ? 0.0 : (point.x - rect.minX) / width;
        final y = height == 0 ? 0.0 : (point.y - rect.minY) / height;
        return DrawPoint(
          x: _clamp01(x),
          y: _clamp01(y),
          pressure: point.pressure,
        );
      }),
    );
  }

  static double calculateShaftLength({
    required List<DrawPoint> points,
    required ArrowType arrowType,
  }) {
    if (points.length < 2) {
      return 0;
    }
    if (arrowType == ArrowType.curved && points.length > 2) {
      return _approximateCurvedLength(points);
    }
    return _calculatePolylineLength(points);
  }

  static DrawPoint? resolveStartDirection(
    List<DrawPoint> points,
    ArrowType arrowType, {
    double startInset = 0,
    double endInset = 0,
    double directionOffset = 0,
  }) {
    if (points.length < 2) {
      return null;
    }

    final hasInsets = startInset > 0 || endInset > 0;
    final workingPoints = hasInsets
        ? _applyInsets(
            points: points,
            startInset: startInset,
            endInset: endInset,
          )
        : points;
    if (workingPoints.length < 2) {
      return null;
    }

    if (arrowType == ArrowType.curved && workingPoints.length > 2) {
      final effectiveOffset = math.max(0, directionOffset - startInset);
      final direction = _CurvedPathAnalysis(
        workingPoints,
      ).directionFromStart(effectiveOffset.toDouble());
      if (direction != null) {
        return DrawPoint(x: -direction.x, y: -direction.y);
      }
    }

    final vector = workingPoints.first - workingPoints[1];
    return _normalize(vector);
  }

  static DrawPoint? resolveEndDirection(
    List<DrawPoint> points,
    ArrowType arrowType, {
    double startInset = 0,
    double endInset = 0,
    double directionOffset = 0,
  }) {
    if (points.length < 2) {
      return null;
    }

    final hasInsets = startInset > 0 || endInset > 0;
    final workingPoints = hasInsets
        ? _applyInsets(
            points: points,
            startInset: startInset,
            endInset: endInset,
          )
        : points;
    if (workingPoints.length < 2) {
      return null;
    }

    if (arrowType == ArrowType.curved && workingPoints.length > 2) {
      final effectiveOffset = math.max(0, directionOffset - endInset);
      final direction = _CurvedPathAnalysis(
        workingPoints,
      ).directionFromEnd(effectiveOffset.toDouble());
      if (direction != null) {
        return direction;
      }
    }

    final vector = workingPoints.last - workingPoints[workingPoints.length - 2];
    return _normalize(vector);
  }

  /// Calculates a point on the curved path using [DrawPoint] inputs.
  static DrawPoint? calculateCurveDrawPoint({
    required List<DrawPoint> points,
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
      return DrawPoint(
        x: p1.x + (p2.x - p1.x) * t,
        y: p1.y + (p2.y - p1.y) * t,
      );
    }

    return _evaluateCubic(_buildCubicSegment(points, segmentIndex), t);
  }

  static double calculateArrowheadInset({
    required ArrowheadStyle style,
    required double strokeWidth,
  }) {
    if (strokeWidth <= 0) {
      return 0;
    }

    final length = _resolveArrowheadLength(strokeWidth);

    return switch (style) {
      ArrowheadStyle.circle => length * 0.6,
      ArrowheadStyle.square => length * 0.6,
      ArrowheadStyle.triangle => length,
      ArrowheadStyle.diamond => length,
      ArrowheadStyle.invertedTriangle => 0,
      ArrowheadStyle.standard => 0,
      ArrowheadStyle.verticalLine => 0,
      ArrowheadStyle.none => 0,
    };
  }

  static double calculateArrowheadDirectionOffset({
    required ArrowheadStyle style,
    required double strokeWidth,
  }) {
    if (strokeWidth <= 0) {
      return 0;
    }

    final length = _resolveArrowheadLength(strokeWidth);

    return switch (style) {
      ArrowheadStyle.circle => length * 0.6,
      ArrowheadStyle.square => length * 0.6,
      ArrowheadStyle.standard => length,
      ArrowheadStyle.triangle => length,
      ArrowheadStyle.diamond => length,
      ArrowheadStyle.invertedTriangle => length,
      ArrowheadStyle.verticalLine => length * 0.6,
      ArrowheadStyle.none => 0,
    };
  }

  static double _resolveArrowheadLength(double strokeWidth) =>
      strokeWidth * 4 + 12.0;

  static DrawRect calculatePathBounds({
    required List<DrawPoint> worldPoints,
    required ArrowType arrowType,
  }) {
    if (worldPoints.isEmpty) {
      return const DrawRect();
    }

    if (arrowType != ArrowType.curved || worldPoints.length < 3) {
      return _boundsFromPoints(worldPoints);
    }

    var minX = worldPoints.first.x;
    var maxX = worldPoints.first.x;
    var minY = worldPoints.first.y;
    var maxY = worldPoints.first.y;

    for (var i = 0; i < worldPoints.length - 1; i++) {
      final segment = _buildCubicSegment(worldPoints, i);
      _expandBoundsForCubic(
        segment: segment,
        minX: (value) => minX = math.min(minX, value),
        maxX: (value) => maxX = math.max(maxX, value),
        minY: (value) => minY = math.min(minY, value),
        maxY: (value) => maxY = math.max(maxY, value),
      );
    }

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  static DrawRect _boundsFromPoints(List<DrawPoint> points) {
    if (points.isEmpty) {
      return const DrawRect();
    }

    var minX = points.first.x;
    var maxX = points.first.x;
    var minY = points.first.y;
    var maxY = points.first.y;

    for (final point in points.skip(1)) {
      if (point.x < minX) {
        minX = point.x;
      }
      if (point.x > maxX) {
        maxX = point.x;
      }
      if (point.y < minY) {
        minY = point.y;
      }
      if (point.y > maxY) {
        maxY = point.y;
      }
    }

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  static double _clamp01(double value) {
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

  static DrawPoint? _normalize(DrawPoint value) {
    final length = value.distance(DrawPoint.zero);
    if (length == 0) {
      return null;
    }
    return DrawPoint(x: value.x / length, y: value.y / length);
  }

  static double _approximateCurvedLength(List<DrawPoint> points) {
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

  static double _calculatePolylineLength(List<DrawPoint> points) {
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += (points[i] - points[i - 1]).distance(DrawPoint.zero);
    }
    return length;
  }

  static _CubicSegment _buildCubicSegment(List<DrawPoint> points, int index) {
    final p0 = index == 0 ? points[index] : points[index - 1];
    final p1 = points[index];
    final p2 = points[index + 1];
    final p3 = index + 2 < points.length
        ? points[index + 2]
        : points[index + 1];

    const tension = 1.0;
    final control1 = p1 + (p2 - p0) * (tension / 6);
    final control2 = p2 - (p3 - p1) * (tension / 6);
    return _CubicSegment(
      start: p1,
      control1: control1,
      control2: control2,
      end: p2,
    );
  }

  static double _approximateCubicLength(_CubicSegment segment) {
    const steps = 8;
    var length = 0.0;
    var previous = segment.start;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final point = _evaluateCubic(segment, t);
      length += (point - previous).distance(DrawPoint.zero);
      previous = point;
    }
    return length;
  }

  static DrawPoint _evaluateCubic(_CubicSegment segment, double t) {
    final mt = 1 - t;
    final mt2 = mt * mt;
    final t2 = t * t;
    final a = mt2 * mt;
    final b = 3 * mt2 * t;
    final c = 3 * mt * t2;
    final d = t2 * t;
    return segment.start * a +
        segment.control1 * b +
        segment.control2 * c +
        segment.end * d;
  }

  static DrawPoint _cubicTangent(_CubicSegment segment, double t) {
    final mt = 1 - t;
    final a = (segment.control1 - segment.start) * (3 * mt * mt);
    final b = (segment.control2 - segment.control1) * (6 * mt * t);
    final c = (segment.end - segment.control2) * (3 * t * t);
    return a + b + c;
  }

  static void _expandBoundsForCubic({
    required _CubicSegment segment,
    required void Function(double) minX,
    required void Function(double) maxX,
    required void Function(double) minY,
    required void Function(double) maxY,
  }) {
    final tValues = <double>{0.0, 1.0}
      ..addAll(
        _cubicDerivativeRoots(
          segment.start.x,
          segment.control1.x,
          segment.control2.x,
          segment.end.x,
        ),
      )
      ..addAll(
        _cubicDerivativeRoots(
          segment.start.y,
          segment.control1.y,
          segment.control2.y,
          segment.end.y,
        ),
      );

    for (final t in tValues) {
      final point = _evaluateCubic(segment, t);
      minX(point.x);
      maxX(point.x);
      minY(point.y);
      maxY(point.y);
    }
  }

  static List<double> _cubicDerivativeRoots(
    double p0,
    double p1,
    double p2,
    double p3,
  ) {
    const epsilon = 1e-9;
    final a = -p0 + 3 * p1 - 3 * p2 + p3;
    final b = 3 * p0 - 6 * p1 + 3 * p2;
    final c = -3 * p0 + 3 * p1;

    if (a.abs() < epsilon) {
      if (b.abs() < epsilon) {
        return const [];
      }
      final t = -c / (2 * b);
      if (t > 0 && t < 1) {
        return [t];
      }
      return const [];
    }

    final A = 3 * a;
    final B = 2 * b;
    final C = c;
    final discriminant = B * B - 4 * A * C;
    if (discriminant < 0) {
      return const [];
    }
    final sqrtDisc = math.sqrt(discriminant);
    final denom = 2 * A;
    if (denom.abs() < epsilon) {
      return const [];
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

  static List<DrawPoint> _ensureMinPoints(List<DrawPoint> points) {
    if (points.length >= 2) {
      return points;
    }
    if (points.isEmpty) {
      return _defaultPoints;
    }
    return [points.first, points.first];
  }

  static List<DrawPoint> _applyInsets({
    required List<DrawPoint> points,
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

  static List<DrawPoint> _insetFromStart(List<DrawPoint> points, double inset) {
    if (points.length < 2 || inset <= 0) {
      return points;
    }

    var remainingInset = inset;
    for (var i = 0; i < points.length - 1; i++) {
      final segmentVector = points[i + 1] - points[i];
      final segmentLength = segmentVector.distance(DrawPoint.zero);

      if (segmentLength <= 0) {
        continue;
      }

      if (remainingInset < segmentLength) {
        final direction = segmentVector / segmentLength;
        final newStart = points[i] + direction * remainingInset;
        return [newStart, ...points.sublist(i + 1)];
      }

      remainingInset -= segmentLength;
    }

    return [points.last];
  }

  static List<DrawPoint> _insetFromEnd(List<DrawPoint> points, double inset) {
    if (points.length < 2 || inset <= 0) {
      return points;
    }

    var remainingInset = inset;
    for (var i = points.length - 1; i > 0; i--) {
      final segmentVector = points[i - 1] - points[i];
      final segmentLength = segmentVector.distance(DrawPoint.zero);

      if (segmentLength <= 0) {
        continue;
      }

      if (remainingInset < segmentLength) {
        final direction = segmentVector / segmentLength;
        final newEnd = points[i] + direction * remainingInset;
        return [...points.sublist(0, i), newEnd];
      }

      remainingInset -= segmentLength;
    }

    return [points.first];
  }
}

class ArrowGeometryDescriptor {
  ArrowGeometryDescriptor({required this.data, required this.rect});

  final ArrowLikeData data;
  final DrawRect rect;

  List<DrawPoint>? _localDrawPoints;
  List<DrawPoint>? _insetDrawPoints;
  DrawPoint? _startDirectionPoint;
  DrawPoint? _endDirectionPoint;
  double? _startInset;
  double? _endInset;
  double? _startDirectionOffset;
  double? _endDirectionOffset;
  _CurvedPathAnalysis? _insetCurvedAnalysis;

  List<DrawPoint> get localDrawPoints =>
      _localDrawPoints ??= ArrowGeometry.resolveLocalPoints(
        rect: rect,
        normalizedPoints: data.points,
      );

  double get startInset =>
      _startInset ??= ArrowGeometry.calculateArrowheadInset(
        style: data.startArrowhead,
        strokeWidth: data.strokeWidth,
      );

  double get endInset => _endInset ??= ArrowGeometry.calculateArrowheadInset(
    style: data.endArrowhead,
    strokeWidth: data.strokeWidth,
  );

  double get startDirectionOffset =>
      _startDirectionOffset ??= ArrowGeometry.calculateArrowheadDirectionOffset(
        style: data.startArrowhead,
        strokeWidth: data.strokeWidth,
      );

  double get endDirectionOffset =>
      _endDirectionOffset ??= ArrowGeometry.calculateArrowheadDirectionOffset(
        style: data.endArrowhead,
        strokeWidth: data.strokeWidth,
      );

  List<DrawPoint> get insetDrawPoints {
    final cached = _insetDrawPoints;
    if (cached != null) {
      return cached;
    }
    final applied = (startInset <= 0 && endInset <= 0)
        ? localDrawPoints
        : ArrowGeometry._applyInsets(
            points: localDrawPoints,
            startInset: startInset,
            endInset: endInset,
          );
    _insetDrawPoints = applied;
    return applied;
  }

  DrawPoint? get startDirectionPoint =>
      _startDirectionPoint ??= _resolveDirection(fromStart: true);

  DrawPoint? get endDirectionPoint =>
      _endDirectionPoint ??= _resolveDirection(fromStart: false);

  DrawPoint? _resolveDirection({required bool fromStart}) {
    final points = insetDrawPoints;
    if (points.length < 2) {
      return null;
    }

    if (data.arrowType == ArrowType.curved && points.length > 2) {
      final directionOffset = fromStart
          ? (startDirectionOffset - startInset)
          : (endDirectionOffset - endInset);
      final effectiveOffset = math.max(0, directionOffset).toDouble();
      final analysis = _resolveInsetCurvedAnalysis(points);
      final direction = fromStart
          ? analysis.directionFromStart(effectiveOffset)
          : analysis.directionFromEnd(effectiveOffset);
      if (direction == null) {
        return null;
      }
      return fromStart
          ? DrawPoint(x: -direction.x, y: -direction.y)
          : direction;
    }

    final vector = fromStart
        ? points.first - points[1]
        : points.last - points[points.length - 2];
    return ArrowGeometry._normalize(vector);
  }

  _CurvedPathAnalysis _resolveInsetCurvedAnalysis(List<DrawPoint> points) =>
      _insetCurvedAnalysis ??= _CurvedPathAnalysis(points);
}

class _CurvedPathAnalysis {
  _CurvedPathAnalysis(List<DrawPoint> points)
    : segments = List<_CubicSegment>.generate(
        points.length - 1,
        (index) => ArrowGeometry._buildCubicSegment(points, index),
      ),
      lengths = List<double>.filled(points.length - 1, 0) {
    var total = 0.0;
    for (var i = 0; i < segments.length; i++) {
      final length = ArrowGeometry._approximateCubicLength(segments[i]);
      lengths[i] = length;
      total += length;
    }
    totalLength = total;
  }

  final List<_CubicSegment> segments;
  final List<double> lengths;
  late final double totalLength;

  DrawPoint? directionFromStart(double offset) {
    if (segments.isEmpty) {
      return null;
    }
    var remaining = offset.isFinite ? offset : 0.0;
    if (remaining < 0) {
      remaining = 0;
    }
    for (var i = 0; i < segments.length; i++) {
      final length = lengths[i];
      if (length <= 0) {
        continue;
      }
      if (remaining <= length || i == segments.length - 1) {
        final t = (remaining / length).clamp(0.0, 1.0);
        final tangent = ArrowGeometry._cubicTangent(segments[i], t);
        return ArrowGeometry._normalize(tangent);
      }
      remaining -= length;
    }
    return null;
  }

  DrawPoint? directionFromEnd(double offset) {
    if (segments.isEmpty) {
      return null;
    }
    var remaining = offset.isFinite ? offset : 0.0;
    if (remaining < 0) {
      remaining = 0;
    }
    for (var i = segments.length - 1; i >= 0; i--) {
      final length = lengths[i];
      if (length <= 0) {
        continue;
      }
      if (remaining <= length || i == 0) {
        final t = (1.0 - (remaining / length)).clamp(0.0, 1.0);
        final tangent = ArrowGeometry._cubicTangent(segments[i], t);
        return ArrowGeometry._normalize(tangent);
      }
      remaining -= length;
    }
    return null;
  }
}
