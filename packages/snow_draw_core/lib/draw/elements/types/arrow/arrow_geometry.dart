import 'dart:math' as math;
import 'dart:ui';

import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import 'arrow_data.dart';

enum _ElbowLineAxis { horizontal, vertical }

class _CubicSegment {
  const _CubicSegment({
    required this.start,
    required this.control1,
    required this.control2,
    required this.end,
  });

  final Offset start;
  final Offset control1;
  final Offset control2;
  final Offset end;
}

class ArrowGeometry {
  const ArrowGeometry._();

  static const List<DrawPoint> _defaultPoints = [
    DrawPoint.zero,
    DrawPoint(x: 1, y: 1),
  ];
  static const _elbowLineSnapTolerance = 1.0;

  static List<Offset> resolveLocalPoints({
    required DrawRect rect,
    required List<DrawPoint> normalizedPoints,
  }) {
    final points = _ensureMinPoints(normalizedPoints);
    final width = rect.width;
    final height = rect.height;
    return points
        .map((point) => Offset(point.x * width, point.y * height))
        .toList(growable: false);
  }

  static List<Offset> resolveWorldPoints({
    required DrawRect rect,
    required List<DrawPoint> normalizedPoints,
  }) {
    final points = _ensureMinPoints(normalizedPoints);
    final width = rect.width;
    final height = rect.height;
    return points
        .map(
          (point) =>
              Offset(rect.minX + point.x * width, rect.minY + point.y * height),
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
        return DrawPoint(x: _clamp01(x), y: _clamp01(y));
      }),
    );
  }

  static Path buildShaftPath({
    required List<Offset> points,
    required ArrowType arrowType,
    double startInset = 0,
    double endInset = 0,
  }) {
    if (points.length < 2) {
      return Path();
    }

    // If no insets, use original path
    if (startInset <= 0 && endInset <= 0) {
      return buildShaftPathFromResolvedPoints(
        points: points,
        arrowType: arrowType,
      );
    }

    // Apply insets to shorten the shaft
    final adjustedPoints = _applyInsets(
      points: points,
      arrowType: arrowType,
      startInset: startInset,
      endInset: endInset,
    );

    if (adjustedPoints.length < 2) {
      return Path();
    }

    return buildShaftPathFromResolvedPoints(
      points: adjustedPoints,
      arrowType: arrowType,
    );
  }

  static Path buildShaftPathFromResolvedPoints({
    required List<Offset> points,
    required ArrowType arrowType,
  }) {
    if (points.length < 2) {
      return Path();
    }
    return switch (arrowType) {
      ArrowType.curved => _buildCurvedPath(points),
      ArrowType.elbowLine => _buildElbowLinePath(points),
      ArrowType.straight => _buildStraightPath(points),
    };
  }

  static double calculateShaftLength({
    required List<Offset> points,
    required ArrowType arrowType,
  }) {
    if (points.length < 2) {
      return 0;
    }
    if (arrowType == ArrowType.curved && points.length > 2) {
      return _approximateCurvedLength(points);
    }

    final resolvedPoints = arrowType == ArrowType.elbowLine
        ? expandElbowLinePoints(points)
        : points;
    var length = 0.0;
    for (var i = 1; i < resolvedPoints.length; i++) {
      length += (resolvedPoints[i] - resolvedPoints[i - 1]).distance;
    }
    return length;
  }

  static Offset? resolveStartDirection(
    List<Offset> points,
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
            arrowType: arrowType,
            startInset: startInset,
            endInset: endInset,
          )
        : points;
    if (workingPoints.length < 2) {
      return null;
    }

    if (arrowType == ArrowType.curved && workingPoints.length > 2) {
      final effectiveOffset = math.max(0, directionOffset - startInset);
      final direction = _resolveCurvedDirection(
        workingPoints,
        offset: effectiveOffset.toDouble(),
        fromStart: true,
      );
      if (direction != null) {
        return Offset(-direction.dx, -direction.dy);
      }
    }

    final resolvedPoints = arrowType == ArrowType.elbowLine
        ? expandElbowLinePoints(workingPoints)
        : workingPoints;
    if (resolvedPoints.length < 2) {
      return null;
    }
    final vector = resolvedPoints.first - resolvedPoints[1];
    return _normalize(vector);
  }

  static Offset? resolveEndDirection(
    List<Offset> points,
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
            arrowType: arrowType,
            startInset: startInset,
            endInset: endInset,
          )
        : points;
    if (workingPoints.length < 2) {
      return null;
    }

    if (arrowType == ArrowType.curved && workingPoints.length > 2) {
      final effectiveOffset = math.max(0, directionOffset - endInset);
      final direction = _resolveCurvedDirection(
        workingPoints,
        offset: effectiveOffset.toDouble(),
        fromStart: false,
      );
      if (direction != null) {
        return direction;
      }
    }

    final resolvedPoints = arrowType == ArrowType.elbowLine
        ? expandElbowLinePoints(workingPoints)
        : workingPoints;
    if (resolvedPoints.length < 2) {
      return null;
    }
    final vector =
        resolvedPoints.last - resolvedPoints[resolvedPoints.length - 2];
    return _normalize(vector);
  }

  static List<Offset> expandElbowLinePoints(
    List<Offset> points, {
    bool includeVirtual = true,
  }) {
    if (!includeVirtual || points.length < 2) {
      return List<Offset>.from(points);
    }
    if (points.length == 2) {
      final created = _buildElbowLineCreationPoints(
        start: DrawPoint(x: points.first.dx, y: points.first.dy),
        end: DrawPoint(x: points.last.dx, y: points.last.dy),
      );
      return created
          .map((point) => Offset(point.x, point.y))
          .toList(growable: false);
    }
    return _simplifyElbowLinePoints(points);
  }

  static bool isElbowLineSegmentHorizontal(DrawPoint start, DrawPoint end) =>
      _resolveElbowLineAxis(Offset(start.x, start.y), Offset(end.x, end.y)) ==
      _ElbowLineAxis.horizontal;

  static List<DrawPoint> normalizeElbowLinePoints(List<DrawPoint> points) {
    if (points.length < 2) {
      return List<DrawPoint>.unmodifiable(_ensureMinPoints(points));
    }

    final offsets = points
        .map((point) => Offset(point.x, point.y))
        .toList(growable: false);
    final deduped = _dedupeElbowLinePoints(offsets);
    final simplified = _removeRedundantElbowLinePoints(deduped);
    if (simplified.length < 2) {
      return List<DrawPoint>.unmodifiable(_ensureMinPoints(points));
    }
    return List<DrawPoint>.unmodifiable(
      simplified
          .map((point) => DrawPoint(x: point.dx, y: point.dy))
          .toList(growable: false),
    );
  }

  static List<DrawPoint> ensureElbowLineCreationPoints(List<DrawPoint> points) {
    if (points.length < 2) {
      return List<DrawPoint>.unmodifiable(_ensureMinPoints(points));
    }
    return normalizeElbowLinePoints(points);
  }

  static List<DrawPoint> _buildElbowLineCreationPoints({
    required DrawPoint start,
    required DrawPoint end,
  }) {
    final startOffset = Offset(start.x, start.y);
    final endOffset = Offset(end.x, end.y);
    if (_isSamePoint(startOffset, endOffset) || _isAxisAligned(start, end)) {
      return [start, end];
    }

    final firstAxis = _dominantElbowLineAxis(startOffset, endOffset);
    return _buildElbowLinePoints(
      start: start,
      end: end,
      firstAxis: firstAxis,
    );
  }

  static bool _isAxisAligned(DrawPoint start, DrawPoint end) =>
      start.x == end.x || start.y == end.y;

  static List<DrawPoint> _buildElbowLinePoints({
    required DrawPoint start,
    required DrawPoint end,
    required _ElbowLineAxis firstAxis,
  }) {
    if (firstAxis == _ElbowLineAxis.horizontal) {
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

  static Path buildArrowheadPath({
    required Offset tip,
    required Offset direction,
    required ArrowheadStyle style,
    required double strokeWidth,
  }) {
    if (style == ArrowheadStyle.none || strokeWidth <= 0) {
      return Path();
    }

    final normalizedDirection = _normalize(direction);
    if (normalizedDirection == null) {
      return Path();
    }

    final length = _resolveArrowheadLength(strokeWidth);
    if (length <= 0) {
      return Path();
    }
    final width = length * 0.6;
    final perp = Offset(-normalizedDirection.dy, normalizedDirection.dx);

    return switch (style) {
      ArrowheadStyle.standard => _buildVArrowhead(
        tip,
        normalizedDirection,
        perp,
        length,
        width,
      ),
      ArrowheadStyle.triangle => _buildTriangleArrowhead(
        tip,
        normalizedDirection,
        perp,
        length,
        width,
      ),
      ArrowheadStyle.square => _buildSquareArrowhead(
        tip,
        normalizedDirection,
        perp,
        length,
      ),
      ArrowheadStyle.circle => _buildCircleArrowhead(
        tip,
        normalizedDirection,
        length,
      ),
      ArrowheadStyle.diamond => _buildDiamondArrowhead(
        tip,
        normalizedDirection,
        perp,
        length,
        width,
      ),
      ArrowheadStyle.invertedTriangle => _buildTriangleArrowhead(
        tip,
        -normalizedDirection,
        perp,
        length,
        width,
      ),
      ArrowheadStyle.verticalLine => _buildLineArrowhead(tip, perp, width),
      ArrowheadStyle.none => Path(),
    };
  }

  static Path _buildStraightPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final point = points[i];
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }

  static Path _buildElbowLinePath(List<Offset> points) =>
      _buildStraightPath(expandElbowLinePoints(points));

  static Path _buildCurvedPath(List<Offset> points) {
    if (points.length < 3) {
      return _buildStraightPath(points);
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    const tension = 1.0;
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? points[i] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];

      final cp1 = p1 + (p2 - p0) * (tension / 6);
      final cp2 = p2 - (p3 - p1) * (tension / 6);

      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  /// Calculates a point on the curved path at parameter t (0.0 to 1.0) between
  /// two consecutive control points at segmentIndex and segmentIndex+1.
  /// Uses the same Catmull-Rom spline formula as _buildCurvedPath.
  /// Returns null if the segment is invalid.
  static Offset? calculateCurvePoint({
    required List<Offset> points,
    required int segmentIndex,
    required double t,
  }) {
    if (points.length < 2 ||
        segmentIndex < 0 ||
        segmentIndex >= points.length - 1) {
      return null;
    }

    // For straight segments (less than 3 points), use linear interpolation
    if (points.length < 3) {
      final p1 = points[segmentIndex];
      final p2 = points[segmentIndex + 1];
      return Offset(p1.dx + (p2.dx - p1.dx) * t, p1.dy + (p2.dy - p1.dy) * t);
    }

    // Use Catmull-Rom spline with same tension as _buildCurvedPath
    const tension = 1.0;
    final i = segmentIndex;
    final p0 = i == 0 ? points[i] : points[i - 1];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];

    // Calculate control points for cubic Bezier
    final cp1 = p1 + (p2 - p0) * (tension / 6);
    final cp2 = p2 - (p3 - p1) * (tension / 6);

    // Evaluate cubic Bezier at parameter t
    // B(t) = (1 - t)^3 P0 + 3(1 - t)^2 t P1 + 3(1 - t) t^2 P2 + t^3 P3
    final t2 = t * t;
    final t3 = t2 * t;
    final mt = 1 - t;
    final mt2 = mt * mt;
    final mt3 = mt2 * mt;

    final x =
        mt3 * p1.dx + 3 * mt2 * t * cp1.dx + 3 * mt * t2 * cp2.dx + t3 * p2.dx;
    final y =
        mt3 * p1.dy + 3 * mt2 * t * cp1.dy + 3 * mt * t2 * cp2.dy + t3 * p2.dy;

    return Offset(x, y);
  }

  static Path _buildVArrowhead(
    Offset tip,
    Offset dir,
    Offset perp,
    double length,
    double width,
  ) {
    final base = tip - dir * length;
    final left = base + perp * (width / 2);
    final right = base - perp * (width / 2);
    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy);
  }

  static Path _buildTriangleArrowhead(
    Offset tip,
    Offset dir,
    Offset perp,
    double length,
    double width,
  ) {
    final base = tip - dir * length;
    final left = base + perp * (width / 2);
    final right = base - perp * (width / 2);
    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
  }

  static Path _buildSquareArrowhead(
    Offset tip,
    Offset dir,
    Offset perp,
    double length,
  ) {
    final side = length * 0.6;
    final half = side / 2;
    final center = tip - dir * half;
    final corner1 = center + perp * half + dir * half;
    final corner2 = center - perp * half + dir * half;
    final corner3 = center - perp * half - dir * half;
    final corner4 = center + perp * half - dir * half;
    return Path()
      ..moveTo(corner1.dx, corner1.dy)
      ..lineTo(corner2.dx, corner2.dy)
      ..lineTo(corner3.dx, corner3.dy)
      ..lineTo(corner4.dx, corner4.dy)
      ..close();
  }

  static Path _buildCircleArrowhead(Offset tip, Offset dir, double length) {
    final radius = length * 0.3;
    final center = tip - dir * radius;
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  static Path _buildDiamondArrowhead(
    Offset tip,
    Offset dir,
    Offset perp,
    double length,
    double width,
  ) {
    final base = tip - dir * length;
    final mid = tip - dir * (length / 2);
    final left = mid + perp * (width / 2);
    final right = mid - perp * (width / 2);
    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(base.dx, base.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
  }

  static Path _buildLineArrowhead(Offset tip, Offset perp, double width) {
    final half = width / 2;
    final left = tip + perp * half;
    final right = tip - perp * half;
    return Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy);
  }

  static double _resolveArrowheadLength(double strokeWidth) {
    if (strokeWidth <= 0) {
      return 0;
    }
    return strokeWidth * 4 + 12.0;
  }

  /// Calculates how far back from the tip the shaft should stop to avoid
  /// penetrating into closed arrowheads (circle, square, diamond, triangle).
  /// Returns 0 for open arrowheads (standard, verticalLine, none).
  static double calculateArrowheadInset({
    required ArrowheadStyle style,
    required double strokeWidth,
  }) {
    if (style == ArrowheadStyle.none || strokeWidth <= 0) {
      return 0;
    }

    final length = _resolveArrowheadLength(strokeWidth);
    if (length <= 0) {
      return 0;
    }

    return switch (style) {
      // Circle: radius = length * 0.3, extends 2*radius from tip
      // Stop at back edge: 2 * radius = length * 0.6
      ArrowheadStyle.circle => length * 0.6,
      // Square: side = length * 0.6, extends side distance from tip
      // Stop at back edge: side = length * 0.6
      ArrowheadStyle.square => length * 0.6,
      // Triangle and diamond: extend length distance from tip
      // Stop at base: length
      ArrowheadStyle.triangle => length,
      ArrowheadStyle.diamond => length,
      // Inverted triangle: the point is at the back, stop at the tip
      ArrowheadStyle.invertedTriangle => 0,
      // Open arrowheads: no inset needed
      ArrowheadStyle.standard => 0,
      ArrowheadStyle.verticalLine => 0,
      ArrowheadStyle.none => 0,
    };
  }

  /// Calculates how far from the tip to sample the curve direction.
  /// This helps orient arrowheads to follow the curve near the base.
  static double calculateArrowheadDirectionOffset({
    required ArrowheadStyle style,
    required double strokeWidth,
  }) {
    if (style == ArrowheadStyle.none || strokeWidth <= 0) {
      return 0;
    }

    final length = _resolveArrowheadLength(strokeWidth);
    if (length <= 0) {
      return 0;
    }

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

  static bool _nearZero(double value) => value.abs() <= _elbowLineSnapTolerance;

  static bool _isSamePoint(Offset a, Offset b) =>
      _nearZero(a.dx - b.dx) && _nearZero(a.dy - b.dy);

  static _ElbowLineAxis _resolveElbowLineAxis(Offset start, Offset end) =>
      _alignedElbowLineAxis(start, end) ?? _dominantElbowLineAxis(start, end);

  static _ElbowLineAxis? _alignedElbowLineAxis(Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    if (_nearZero(dx) && _nearZero(dy)) {
      return null;
    }
    if (_nearZero(dx)) {
      return _ElbowLineAxis.vertical;
    }
    if (_nearZero(dy)) {
      return _ElbowLineAxis.horizontal;
    }
    return null;
  }

  static _ElbowLineAxis _dominantElbowLineAxis(Offset start, Offset end) {
    final dx = (end.dx - start.dx).abs();
    final dy = (end.dy - start.dy).abs();
    return dx >= dy ? _ElbowLineAxis.horizontal : _ElbowLineAxis.vertical;
  }

  static Offset _snapToAxis(Offset start, Offset end, _ElbowLineAxis axis) =>
      axis == _ElbowLineAxis.horizontal
      ? Offset(end.dx, start.dy)
      : Offset(start.dx, end.dy);

  static List<Offset> _simplifyElbowLinePoints(List<Offset> points) {
    if (points.length < 2) {
      return points;
    }

    final routed = _routeOrthogonalElbowLine(points);
    if (routed.length < 2) {
      return routed;
    }
    return _removeRedundantElbowLinePoints(routed);
  }

  static List<Offset> _dedupeElbowLinePoints(List<Offset> points) {
    if (points.length < 2) {
      return points;
    }
    final deduped = <Offset>[points.first];
    for (var i = 1; i < points.length; i++) {
      final point = points[i];
      if (_isSamePoint(deduped.last, point)) {
        continue;
      }
      deduped.add(point);
    }
    return deduped;
  }

  static List<Offset> _routeOrthogonalElbowLine(List<Offset> points) {
    final routed = <Offset>[points.first];
    _ElbowLineAxis? previousAxis;

    void appendPoint(Offset point) {
      if (_isSamePoint(routed.last, point)) {
        return;
      }
      routed.add(point);
      if (routed.length >= 2) {
        previousAxis = _resolveElbowLineAxis(
          routed[routed.length - 2],
          routed.last,
        );
      }
    }

    for (var i = 1; i < points.length; i++) {
      final prev = routed.last;
      final current = points[i];

      if (_isSamePoint(prev, current)) {
        continue;
      }

      final alignedAxis = _alignedElbowLineAxis(prev, current);
      if (alignedAxis != null) {
        appendPoint(_snapToAxis(prev, current, alignedAxis));
        continue;
      }

      final next = i + 1 < points.length ? points[i + 1] : null;
      final nextAxis = next == null
          ? null
          : _alignedElbowLineAxis(current, next);
      final routedPoints = _routeDiagonalSegment(
        prev: prev,
        current: current,
        previousAxis: previousAxis,
        nextAxis: nextAxis,
      );
      for (final point in routedPoints) {
        appendPoint(point);
      }
    }

    return routed;
  }

  static List<Offset> _routeDiagonalSegment({
    required Offset prev,
    required Offset current,
    required _ElbowLineAxis? previousAxis,
    required _ElbowLineAxis? nextAxis,
  }) {
    if (previousAxis != null && nextAxis != null && previousAxis == nextAxis) {
      return [_snapToAxis(prev, current, previousAxis)];
    }

    final firstAxis =
        previousAxis ?? nextAxis ?? _dominantElbowLineAxis(prev, current);
    final elbow = firstAxis == _ElbowLineAxis.horizontal
        ? Offset(current.dx, prev.dy)
        : Offset(prev.dx, current.dy);
    return [elbow, current];
  }

  static List<Offset> _removeRedundantElbowLinePoints(List<Offset> points) {
    if (points.length < 3) {
      return points;
    }

    final simplified = <Offset>[points.first];
    for (var i = 1; i < points.length - 1; i++) {
      final prev = simplified.last;
      final current = points[i];
      final next = points[i + 1];

      if (_isSamePoint(prev, current)) {
        continue;
      }

      final prevAxis = _alignedElbowLineAxis(prev, current);
      final nextAxis = _alignedElbowLineAxis(current, next);
      if (prevAxis != null && nextAxis != null && prevAxis == nextAxis) {
        continue;
      }

      simplified.add(current);
    }

    final last = points.last;
    if (simplified.isEmpty || !_isSamePoint(simplified.last, last)) {
      simplified.add(last);
    }
    return simplified;
  }

  static Offset? _normalize(Offset value) {
    final length = value.distance;
    if (length == 0) {
      return null;
    }
    return Offset(value.dx / length, value.dy / length);
  }

  static double _approximateCurvedLength(List<Offset> points) {
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

  static Offset? _resolveCurvedDirection(
    List<Offset> points, {
    required double offset,
    required bool fromStart,
  }) {
    if (points.length < 2) {
      return null;
    }

    final segmentCount = points.length - 1;
    if (segmentCount == 1) {
      return _normalize(points[1] - points[0]);
    }

    var remaining = offset.isFinite ? offset : 0.0;
    if (remaining < 0) {
      remaining = 0;
    }

    if (fromStart) {
      for (var i = 0; i < segmentCount; i++) {
        final segment = _buildCubicSegment(points, i);
        final length = _approximateCubicLength(segment);
        if (length <= 0) {
          continue;
        }
        if (remaining <= length || i == segmentCount - 1) {
          final t = length == 0
              ? 0.0
              : (remaining / length).clamp(0.0, 1.0);
          return _normalize(_cubicTangent(segment, t));
        }
        remaining -= length;
      }
      return null;
    }

    for (var i = segmentCount - 1; i >= 0; i--) {
      final segment = _buildCubicSegment(points, i);
      final length = _approximateCubicLength(segment);
      if (length <= 0) {
        continue;
      }
      if (remaining <= length || i == 0) {
        final t = length == 0
            ? 1.0
            : (1.0 - (remaining / length)).clamp(0.0, 1.0);
        return _normalize(_cubicTangent(segment, t));
      }
      remaining -= length;
    }

    return null;
  }

  static _CubicSegment _buildCubicSegment(List<Offset> points, int index) {
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
    const steps = 5;
    var length = 0.0;
    var previous = segment.start;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final point = _evaluateCubic(segment, t);
      length += (point - previous).distance;
      previous = point;
    }
    return length;
  }

  static Offset _evaluateCubic(_CubicSegment segment, double t) {
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

  static Offset _cubicTangent(_CubicSegment segment, double t) {
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
          segment.start.dx,
          segment.control1.dx,
          segment.control2.dx,
          segment.end.dx,
        ),
      )
      ..addAll(
        _cubicDerivativeRoots(
          segment.start.dy,
          segment.control1.dy,
          segment.control2.dy,
          segment.end.dy,
        ),
      );

    for (final t in tValues) {
      final point = _evaluateCubic(segment, t);
      minX(point.dx);
      maxX(point.dx);
      minY(point.dy);
      maxY(point.dy);
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

  /// Calculates accurate bounding box for arrow paths, accounting for
  /// curve overshoot.
  /// For curved arrows, computes cubic bounds analytically.
  /// For straight/elbow line arrows, uses control points.
  static DrawRect calculatePathBounds({
    required List<DrawPoint> worldPoints,
    required ArrowType arrowType,
  }) {
    if (worldPoints.isEmpty) {
      return const DrawRect();
    }

    // For straight and elbow line arrows, control points define the bounds
    if (arrowType != ArrowType.curved || worldPoints.length < 3) {
      return _boundsFromPoints(worldPoints);
    }

    // For curved arrows, compute cubic bezier bounds analytically.
    final offsetPoints = worldPoints
        .map((p) => Offset(p.x, p.y))
        .toList(growable: false);

    var minX = offsetPoints.first.dx;
    var maxX = offsetPoints.first.dx;
    var minY = offsetPoints.first.dy;
    var maxY = offsetPoints.first.dy;

    for (var i = 0; i < offsetPoints.length - 1; i++) {
      final segment = _buildCubicSegment(offsetPoints, i);
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

  /// Helper to calculate bounds from a list of points
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

  static List<DrawPoint> _ensureMinPoints(List<DrawPoint> points) {
    if (points.length >= 2) {
      return points;
    }
    if (points.isEmpty) {
      return _defaultPoints;
    }
    return [points.first, points.first];
  }

  /// Applies start and end insets to shorten the arrow shaft.
  /// This prevents the shaft from penetrating into closed arrowheads.
  static List<Offset> _applyInsets({
    required List<Offset> points,
    required ArrowType arrowType,
    required double startInset,
    required double endInset,
  }) {
    if (points.length < 2) {
      return points;
    }

    // Expand elbow line points first if needed
    final workingPoints = arrowType == ArrowType.elbowLine
        ? expandElbowLinePoints(points)
        : points;

    if (workingPoints.length < 2) {
      return workingPoints;
    }

    var adjustedPoints = workingPoints;

    // Apply start inset
    if (startInset > 0) {
      adjustedPoints = _insetFromStart(adjustedPoints, startInset);
      if (adjustedPoints.length < 2) {
        return adjustedPoints;
      }
    }

    // Apply end inset
    if (endInset > 0) {
      adjustedPoints = _insetFromEnd(adjustedPoints, endInset);
    }

    return adjustedPoints;
  }

  /// Shortens the path from the start by the given distance.
  static List<Offset> _insetFromStart(List<Offset> points, double inset) {
    if (points.length < 2 || inset <= 0) {
      return points;
    }

    var remainingInset = inset;
    for (var i = 0; i < points.length - 1; i++) {
      final segmentVector = points[i + 1] - points[i];
      final segmentLength = segmentVector.distance;

      if (segmentLength <= 0) {
        continue;
      }

      if (remainingInset < segmentLength) {
        // Inset ends within this segment
        final direction = segmentVector / segmentLength;
        final newStart = points[i] + direction * remainingInset;
        return [newStart, ...points.sublist(i + 1)];
      }

      remainingInset -= segmentLength;
    }

    // Inset is longer than the entire path
    return [points.last];
  }

  /// Shortens the path from the end by the given distance.
  static List<Offset> _insetFromEnd(List<Offset> points, double inset) {
    if (points.length < 2 || inset <= 0) {
      return points;
    }

    var remainingInset = inset;
    for (var i = points.length - 1; i > 0; i--) {
      final segmentVector = points[i - 1] - points[i];
      final segmentLength = segmentVector.distance;

      if (segmentLength <= 0) {
        continue;
      }

      if (remainingInset < segmentLength) {
        // Inset ends within this segment
        final direction = segmentVector / segmentLength;
        final newEnd = points[i] + direction * remainingInset;
        return [...points.sublist(0, i), newEnd];
      }

      remainingInset -= segmentLength;
    }

    // Inset is longer than the entire path
    return [points.first];
  }
}

class ArrowGeometryDescriptor {
  ArrowGeometryDescriptor({
    required this.data,
    required this.rect,
  });

  final ArrowData data;
  final DrawRect rect;

  List<Offset>? _localPoints;
  List<Offset>? _worldPoints;
  List<Offset>? _insetPoints;
  Offset? _startDirection;
  Offset? _endDirection;
  double? _startInset;
  double? _endInset;
  double? _startDirectionOffset;
  double? _endDirectionOffset;
  double? _shaftLength;
  DrawRect? _pathBounds;
  _CurvedPathAnalysis? _curvedAnalysis;
  _CurvedPathAnalysis? _insetCurvedAnalysis;

  List<Offset> get localPoints =>
      _localPoints ??= ArrowGeometry.resolveLocalPoints(
        rect: rect,
        normalizedPoints: data.points,
      );

  List<Offset> get worldPoints {
    final cached = _worldPoints;
    if (cached != null) {
      return cached;
    }
    final local = localPoints;
    final world = local
        .map(
          (point) => Offset(point.dx + rect.minX, point.dy + rect.minY),
        )
        .toList(growable: false);
    _worldPoints = world;
    return world;
  }

  double get startInset =>
      _startInset ??= ArrowGeometry.calculateArrowheadInset(
        style: data.startArrowhead,
        strokeWidth: data.strokeWidth,
      );

  double get endInset =>
      _endInset ??= ArrowGeometry.calculateArrowheadInset(
        style: data.endArrowhead,
        strokeWidth: data.strokeWidth,
      );

  double get startDirectionOffset =>
      _startDirectionOffset ??=
          ArrowGeometry.calculateArrowheadDirectionOffset(
            style: data.startArrowhead,
            strokeWidth: data.strokeWidth,
          );

  double get endDirectionOffset =>
      _endDirectionOffset ??=
          ArrowGeometry.calculateArrowheadDirectionOffset(
            style: data.endArrowhead,
            strokeWidth: data.strokeWidth,
          );

  List<Offset> get insetPoints {
    final cached = _insetPoints;
    if (cached != null) {
      return cached;
    }
    if (localPoints.length < 2) {
      _insetPoints = localPoints;
      return localPoints;
    }
    final applied = (startInset <= 0 && endInset <= 0)
        ? localPoints
        : ArrowGeometry._applyInsets(
            points: localPoints,
            arrowType: data.arrowType,
            startInset: startInset,
            endInset: endInset,
          );
    _insetPoints = applied;
    return applied;
  }

  Offset? get startDirection =>
      _startDirection ??= _resolveDirection(fromStart: true);

  Offset? get endDirection =>
      _endDirection ??= _resolveDirection(fromStart: false);

  double get shaftLength {
    final cached = _shaftLength;
    if (cached != null) {
      return cached;
    }
    final points = localPoints;
    if (points.length < 2) {
      _shaftLength = 0;
      return 0;
    }
    if (data.arrowType == ArrowType.curved && points.length > 2) {
      final analysis = _resolveCurvedAnalysis(points, inset: false);
      _shaftLength = analysis.totalLength;
      return analysis.totalLength;
    }
    final resolvedPoints = data.arrowType == ArrowType.elbowLine
        ? ArrowGeometry.expandElbowLinePoints(points)
        : points;
    var length = 0.0;
    for (var i = 1; i < resolvedPoints.length; i++) {
      length += (resolvedPoints[i] - resolvedPoints[i - 1]).distance;
    }
    _shaftLength = length;
    return length;
  }

  DrawRect get pathBounds {
    final cached = _pathBounds;
    if (cached != null) {
      return cached;
    }
    final points = worldPoints;
    if (points.isEmpty) {
      _pathBounds = const DrawRect();
      return _pathBounds!;
    }

    if (data.arrowType != ArrowType.curved || points.length < 3) {
      final bounds = _boundsFromOffsets(points);
      _pathBounds = bounds;
      return bounds;
    }

    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;

    for (var i = 0; i < points.length - 1; i++) {
      final segment = ArrowGeometry._buildCubicSegment(points, i);
      ArrowGeometry._expandBoundsForCubic(
        segment: segment,
        minX: (value) => minX = math.min(minX, value),
        maxX: (value) => maxX = math.max(maxX, value),
        minY: (value) => minY = math.min(minY, value),
        maxY: (value) => maxY = math.max(maxY, value),
      );
    }

    final bounds = DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
    _pathBounds = bounds;
    return bounds;
  }

  Offset? _resolveDirection({required bool fromStart}) {
    final points = insetPoints;
    if (points.length < 2) {
      return null;
    }

    if (data.arrowType == ArrowType.curved && points.length > 2) {
      final directionOffset = fromStart
          ? (startDirectionOffset - startInset)
          : (endDirectionOffset - endInset);
      final effectiveOffset = math.max(0, directionOffset).toDouble();
      final analysis = _resolveCurvedAnalysis(points, inset: true);
      final direction = fromStart
          ? analysis.directionFromStart(effectiveOffset)
          : analysis.directionFromEnd(effectiveOffset);
      if (direction == null) {
        return null;
      }
      return fromStart ? Offset(-direction.dx, -direction.dy) : direction;
    }

    final resolvedPoints = data.arrowType == ArrowType.elbowLine
        ? ArrowGeometry.expandElbowLinePoints(points)
        : points;
    if (resolvedPoints.length < 2) {
      return null;
    }
    final vector = fromStart
        ? resolvedPoints.first - resolvedPoints[1]
        : resolvedPoints.last - resolvedPoints[resolvedPoints.length - 2];
    return ArrowGeometry._normalize(vector);
  }

  _CurvedPathAnalysis _resolveCurvedAnalysis(
    List<Offset> points, {
    required bool inset,
  }) {
    if (inset) {
      return _insetCurvedAnalysis ??= _CurvedPathAnalysis(points);
    }
    return _curvedAnalysis ??= _CurvedPathAnalysis(points);
  }

  DrawRect _boundsFromOffsets(List<Offset> points) {
    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;

    for (final point in points.skip(1)) {
      if (point.dx < minX) {
        minX = point.dx;
      }
      if (point.dx > maxX) {
        maxX = point.dx;
      }
      if (point.dy < minY) {
        minY = point.dy;
      }
      if (point.dy > maxY) {
        maxY = point.dy;
      }
    }

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }
}

class _CurvedPathAnalysis {
  _CurvedPathAnalysis(this.points)
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

  final List<Offset> points;
  final List<_CubicSegment> segments;
  final List<double> lengths;
  late final double totalLength;

  Offset? directionFromStart(double offset) {
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
        final t = length == 0
            ? 0.0
            : (remaining / length).clamp(0.0, 1.0);
        final tangent = ArrowGeometry._cubicTangent(segments[i], t);
        return ArrowGeometry._normalize(tangent);
      }
      remaining -= length;
    }
    return null;
  }

  Offset? directionFromEnd(double offset) {
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
        final t = length == 0
            ? 1.0
            : (1.0 - (remaining / length)).clamp(0.0, 1.0);
        final tangent = ArrowGeometry._cubicTangent(segments[i], t);
        return ArrowGeometry._normalize(tangent);
      }
      remaining -= length;
    }
    return null;
  }
}


