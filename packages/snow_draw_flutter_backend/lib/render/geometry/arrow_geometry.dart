import 'dart:ui';

import 'package:snow_draw_core/snow_draw_engine.dart';

class FlutterArrowGeometry {
  const FlutterArrowGeometry._();

  static List<Offset> resolveWorldPoints({
    required DrawRect rect,
    required List<DrawPoint> normalizedPoints,
  }) => _toOffsets(
    ArrowGeometry.resolveWorldPoints(
      rect: rect,
      normalizedPoints: normalizedPoints,
    ),
  );

  static List<DrawPoint> normalizePoints({
    required List<DrawPoint> worldPoints,
    required DrawRect rect,
  }) => ArrowGeometry.normalizePoints(worldPoints: worldPoints, rect: rect);

  static Path buildShaftPathFromResolvedPoints({
    required List<Offset> points,
    required ArrowType arrowType,
  }) {
    if (points.length < 2) {
      return Path();
    }
    return switch (arrowType) {
      ArrowType.curved => _buildCurvedPath(points),
      ArrowType.straight => _buildStraightPath(points),
      ArrowType.elbow => _buildStraightPath(points),
    };
  }

  static Path buildArrowheadPath({
    required Offset tip,
    required Offset direction,
    required ArrowheadStyle style,
    required double strokeWidth,
  }) {
    if (strokeWidth <= 0) {
      return Path();
    }

    final normalizedDirection = _normalize(direction);
    if (normalizedDirection == null) {
      return Path();
    }

    final length = ArrowGeometry.resolveArrowheadLength(strokeWidth);
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

  static Path _buildCurvedPath(List<Offset> points) {
    if (points.length < 3) {
      return _buildStraightPath(points);
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final segment = _buildCubicSegment(points, i);
      path.cubicTo(
        segment.control1.dx,
        segment.control1.dy,
        segment.control2.dx,
        segment.control2.dy,
        segment.end.dx,
        segment.end.dy,
      );
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

  static Offset? _normalize(Offset value) {
    final length = value.distance;
    if (length == 0) {
      return null;
    }
    return Offset(value.dx / length, value.dy / length);
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
    return _CubicSegment(control1: control1, control2: control2, end: p2);
  }
}

class FlutterArrowGeometryDescriptor {
  FlutterArrowGeometryDescriptor({required this.data, required DrawRect rect})
    : _coreDescriptor = ArrowGeometryDescriptor(data: data, rect: rect);

  final ArrowLikeData data;
  final ArrowGeometryDescriptor _coreDescriptor;

  late final List<Offset> localPoints = _toOffsets(
    _coreDescriptor.localDrawPoints,
  );
  late final List<Offset> insetPoints = _toOffsets(
    _coreDescriptor.insetDrawPoints,
  );
  late final Offset? startDirection = _toOffsetOrNull(
    _coreDescriptor.startDirectionPoint,
  );
  late final Offset? endDirection = _toOffsetOrNull(
    _coreDescriptor.endDirectionPoint,
  );
}

List<Offset> _toOffsets(List<DrawPoint> points) =>
    points.map(_toOffset).toList(growable: false);

Offset _toOffset(DrawPoint point) => Offset(point.x, point.y);

Offset? _toOffsetOrNull(DrawPoint? point) =>
    point == null ? null : _toOffset(point);

class _CubicSegment {
  const _CubicSegment({
    required this.control1,
    required this.control2,
    required this.end,
  });

  final Offset control1;
  final Offset control2;
  final Offset end;
}
