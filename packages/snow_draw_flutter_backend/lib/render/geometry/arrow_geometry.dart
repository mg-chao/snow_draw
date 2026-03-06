import 'dart:ui';

import 'package:snow_draw_engine/snow_draw_engine.dart';

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
      ArrowType.elbow => _buildElbowPath(points),
    };
  }

  static FlutterArrowheadPaths buildArrowheadPaths({
    required List<Offset> points,
    required ArrowType arrowType,
    required ArrowheadStyle style,
    required StrokeStyle strokeStyle,
    required double strokeWidth,
    required ArrowEndpointPosition position,
    Offset? directionOverride,
  }) {
    final drawPoints = points
        .map((point) => DrawPoint(x: point.dx, y: point.dy))
        .toList(growable: false);
    final overrideDirection = directionOverride == null
        ? null
        : DrawPoint(x: directionOverride.dx, y: directionOverride.dy);
    final primitives = ArrowRenderPrimitives.resolveArrowheadPrimitives(
      points: drawPoints,
      arrowType: arrowType,
      style: style,
      strokeStyle: strokeStyle,
      strokeWidth: strokeWidth,
      position: position,
      directionOverride: overrideDirection,
    );
    if (primitives.isEmpty) {
      return FlutterArrowheadPaths.empty();
    }

    final strokePath = Path();
    final fillPath = Path();
    for (final primitive in primitives) {
      switch (primitive) {
        case ArrowheadLinePrimitiveData():
          strokePath
            ..moveTo(primitive.from.x, primitive.from.y)
            ..lineTo(primitive.to.x, primitive.to.y);
        case ArrowheadPolygonPrimitiveData():
          if (primitive.points.isEmpty) {
            continue;
          }
          final polygonPath = Path()
            ..moveTo(primitive.points.first.x, primitive.points.first.y);
          for (var i = 1; i < primitive.points.length; i++) {
            polygonPath.lineTo(primitive.points[i].x, primitive.points[i].y);
          }
          polygonPath.close();
          strokePath.addPath(polygonPath, Offset.zero);
          if (primitive.fillMode == ArrowheadPrimitiveFillMode.stroke) {
            fillPath.addPath(polygonPath, Offset.zero);
          }
        case ArrowheadCirclePrimitiveData():
          final circlePath = Path()
            ..addOval(
              Rect.fromCircle(
                center: Offset(primitive.center.x, primitive.center.y),
                radius: primitive.radius,
              ),
            );
          strokePath.addPath(circlePath, Offset.zero);
          if (primitive.fillMode == ArrowheadPrimitiveFillMode.stroke) {
            fillPath.addPath(circlePath, Offset.zero);
          }
      }
    }

    return FlutterArrowheadPaths(strokePath: strokePath, fillPath: fillPath);
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

  static Path _buildElbowPath(List<Offset> points) {
    if (points.length < 2) {
      return Path();
    }

    final pathData = ArrowGeometry.generateElbowPathData(
      points: points
          .map((point) => DrawPoint(x: point.dx, y: point.dy))
          .toList(growable: false),
    );
    final parsedPath = _pathFromCorePathData(pathData);
    return parsedPath ?? _buildStraightPath(points);
  }

  static Path? _pathFromCorePathData(String pathData) {
    if (pathData.isEmpty) {
      return Path();
    }

    final tokens = pathData
        .replaceAll(',', ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return Path();
    }

    final path = Path();
    var index = 0;

    double? readNumber() {
      if (index >= tokens.length) {
        return null;
      }
      return double.tryParse(tokens[index++]);
    }

    while (index < tokens.length) {
      final commandToken = tokens[index++];
      if (commandToken.length != 1) {
        return null;
      }
      final command = commandToken.toUpperCase();

      if (command == 'M' || command == 'L') {
        final x = readNumber();
        final y = readNumber();
        if (x == null || y == null) {
          return null;
        }
        if (command == 'M') {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        continue;
      }

      if (command == 'Q') {
        final cx = readNumber();
        final cy = readNumber();
        final x = readNumber();
        final y = readNumber();
        if (cx == null || cy == null || x == null || y == null) {
          return null;
        }
        path.quadraticBezierTo(cx, cy, x, y);
        continue;
      }

      return null;
    }

    return path;
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
    : _engineDescriptor = ArrowGeometryDescriptor(data: data, rect: rect);

  final ArrowLikeData data;
  final ArrowGeometryDescriptor _engineDescriptor;

  late final List<Offset> localPoints = _toOffsets(
    _engineDescriptor.localDrawPoints,
  );
  late final List<Offset> insetPoints = _toOffsets(
    _engineDescriptor.insetDrawPoints,
  );
  late final Offset? startDirection = _toOffsetOrNull(
    _engineDescriptor.startDirectionPoint,
  );
  late final Offset? endDirection = _toOffsetOrNull(
    _engineDescriptor.endDirectionPoint,
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

class FlutterArrowheadPaths {
  const FlutterArrowheadPaths({
    required this.strokePath,
    required this.fillPath,
  });

  factory FlutterArrowheadPaths.empty() =>
      FlutterArrowheadPaths(strokePath: Path(), fillPath: Path());

  final Path strokePath;
  final Path fillPath;
}
