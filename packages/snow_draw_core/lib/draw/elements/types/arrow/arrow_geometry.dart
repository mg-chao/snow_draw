import 'dart:math' as math;
import 'dart:ui';

import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';

class ArrowGeometry {
  const ArrowGeometry._();

  static const List<DrawPoint> _defaultPoints = [
    DrawPoint.zero,
    DrawPoint(x: 1, y: 1),
  ];

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
          (point) => Offset(
            rect.minX + point.x * width,
            rect.minY + point.y * height,
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
        );
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
      return switch (arrowType) {
        ArrowType.curved => _buildCurvedPath(points),
        ArrowType.polyline => _buildPolylinePath(points),
        ArrowType.straight => _buildStraightPath(points),
      };
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

    return switch (arrowType) {
      ArrowType.curved => _buildCurvedPath(adjustedPoints),
      ArrowType.polyline => _buildPolylinePath(adjustedPoints),
      ArrowType.straight => _buildStraightPath(adjustedPoints),
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
      final path = buildShaftPath(points: points, arrowType: arrowType);
      var length = 0.0;
      for (final metric in path.computeMetrics()) {
        length += metric.length;
      }
      return length;
    }

    final resolvedPoints = arrowType == ArrowType.polyline
        ? expandPolylinePoints(points)
        : points;
    var length = 0.0;
    for (var i = 1; i < resolvedPoints.length; i++) {
      length += (resolvedPoints[i] - resolvedPoints[i - 1]).distance;
    }
    return length;
  }

  static Offset? resolveStartDirection(
    List<Offset> points,
    ArrowType arrowType,
  ) {
    final resolvedPoints = arrowType == ArrowType.polyline
        ? expandPolylinePoints(points)
        : points;
    if (resolvedPoints.length < 2) {
      return null;
    }
    final vector = resolvedPoints.first - resolvedPoints[1];
    return _normalize(vector);
  }

  static Offset? resolveEndDirection(
    List<Offset> points,
    ArrowType arrowType,
  ) {
    final resolvedPoints = arrowType == ArrowType.polyline
        ? expandPolylinePoints(points)
        : points;
    if (resolvedPoints.length < 2) {
      return null;
    }
    final vector = resolvedPoints.last -
        resolvedPoints[resolvedPoints.length - 2];
    return _normalize(vector);
  }

  static List<Offset> expandPolylinePoints(List<Offset> points) {
    if (points.length < 2) {
      return points;
    }

    final expanded = <Offset>[points.first];
    for (var i = 1; i < points.length; i++) {
      final prev = expanded.last;
      final target = points[i];
      final dx = target.dx - prev.dx;
      final dy = target.dy - prev.dy;

      if (_nearZero(dx) || _nearZero(dy)) {
        expanded.add(target);
        continue;
      }

      final corner = dx.abs() >= dy.abs()
          ? Offset(target.dx, prev.dy)
          : Offset(prev.dx, target.dy);

      if (corner != prev) {
        expanded.add(corner);
      }
      expanded.add(target);
    }
    return expanded;
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
      ArrowheadStyle.verticalLine => _buildLineArrowhead(
        tip,
        perp,
        width,
      ),
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

  static Path _buildPolylinePath(List<Offset> points) =>
      _buildStraightPath(expandPolylinePoints(points));

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

  static Path _buildCircleArrowhead(
    Offset tip,
    Offset dir,
    double length,
  ) {
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
    return math.max(6, strokeWidth * 6);
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

  static bool _nearZero(double value) => value.abs() <= 0.00001;

  static Offset? _normalize(Offset value) {
    final length = value.distance;
    if (length == 0) {
      return null;
    }
    return Offset(value.dx / length, value.dy / length);
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

    // Expand polyline points first if needed
    final workingPoints = arrowType == ArrowType.polyline
        ? expandPolylinePoints(points)
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
