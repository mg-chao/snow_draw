import 'package:meta/meta.dart';

import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import 'arrow_core.dart' as core;

/// Endpoint position for arrowhead primitive resolution.
enum ArrowEndpointPosition { start, end }

/// Fill mode attached to a render primitive.
enum ArrowheadPrimitiveFillMode { none, stroke, background }

/// Dash semantics attached to a line primitive.
enum ArrowheadPrimitiveDashMode { solid, inherit, dottedCap }

/// Engine-friendly render primitive descriptor for arrowheads.
@immutable
sealed class ArrowheadRenderPrimitiveData {
  const ArrowheadRenderPrimitiveData();
}

/// Line-segment primitive for arrowhead rendering/hit testing.
@immutable
final class ArrowheadLinePrimitiveData extends ArrowheadRenderPrimitiveData {
  const ArrowheadLinePrimitiveData({
    required this.from,
    required this.to,
    required this.dashMode,
  });

  final DrawPoint from;
  final DrawPoint to;
  final ArrowheadPrimitiveDashMode dashMode;
}

/// Polygon primitive for arrowhead rendering/hit testing.
@immutable
final class ArrowheadPolygonPrimitiveData extends ArrowheadRenderPrimitiveData {
  const ArrowheadPolygonPrimitiveData({
    required this.points,
    required this.fillMode,
  });

  final List<DrawPoint> points;
  final ArrowheadPrimitiveFillMode fillMode;
}

/// Circle primitive for arrowhead rendering/hit testing.
@immutable
final class ArrowheadCirclePrimitiveData extends ArrowheadRenderPrimitiveData {
  const ArrowheadCirclePrimitiveData({
    required this.center,
    required this.radius,
    required this.fillMode,
  });

  final DrawPoint center;
  final double radius;
  final ArrowheadPrimitiveFillMode fillMode;
}

/// Resolves arrowhead primitives strictly via arrow-core.
final class ArrowRenderPrimitives {
  const ArrowRenderPrimitives._();

  /// Builds render primitives for a single endpoint arrowhead.
  static List<ArrowheadRenderPrimitiveData> resolveArrowheadPrimitives({
    required List<DrawPoint> points,
    required ArrowType arrowType,
    required ArrowheadStyle style,
    required StrokeStyle strokeStyle,
    required double strokeWidth,
    required ArrowEndpointPosition position,
    DrawPoint? directionOverride,
  }) {
    // Keep API shape stable while forcing all geometry onto arrow-core.
    final _ = directionOverride;
    if (style == ArrowheadStyle.none || strokeWidth <= 0 || points.length < 2) {
      return const <ArrowheadRenderPrimitiveData>[];
    }

    return _resolveCoreArrowheadPrimitives(
      points: points,
      arrowType: arrowType,
      style: style,
      strokeStyle: strokeStyle,
      strokeWidth: strokeWidth,
      position: position,
    );
  }
}

List<ArrowheadRenderPrimitiveData> _resolveCoreArrowheadPrimitives({
  required List<DrawPoint> points,
  required ArrowType arrowType,
  required ArrowheadStyle style,
  required StrokeStyle strokeStyle,
  required double strokeWidth,
  required ArrowEndpointPosition position,
}) {
  final coreArrowhead = _toCoreRenderableArrowhead(style);
  if (coreArrowhead == null) {
    return const <ArrowheadRenderPrimitiveData>[];
  }

  final curveOps = _buildCoreCurveOps(points: points, arrowType: arrowType);
  if (curveOps.length < 2) {
    return const <ArrowheadRenderPrimitiveData>[];
  }

  final primitives = core.getArrowheadRenderPrimitives(
    core.ArrowheadRenderPrimitivesInput(
      arrowPoints: points
          .map((point) => <double>[point.x, point.y])
          .toList(growable: false),
      strokeWidth: strokeWidth,
      curveOps: curveOps,
      position: _toCoreEndpointPosition(position),
      arrowhead: coreArrowhead,
      strokeStyle: _toCoreStrokeStyle(strokeStyle),
    ),
  );
  if (primitives.isEmpty) {
    return const <ArrowheadRenderPrimitiveData>[];
  }

  final converted = <ArrowheadRenderPrimitiveData>[];
  for (final primitive in primitives) {
    switch (primitive) {
      case core.ArrowheadLinePrimitive():
        converted.add(
          ArrowheadLinePrimitiveData(
            from: DrawPoint(x: primitive.from[0], y: primitive.from[1]),
            to: DrawPoint(x: primitive.to[0], y: primitive.to[1]),
            dashMode: _fromCoreDashMode(primitive.dashMode),
          ),
        );
      case core.ArrowheadPolygonPrimitive():
        converted.add(
          ArrowheadPolygonPrimitiveData(
            points: List<DrawPoint>.unmodifiable(
              primitive.points
                  .map((point) => DrawPoint(x: point[0], y: point[1]))
                  .toList(growable: false),
            ),
            fillMode: _fromCoreFillMode(primitive.fillMode),
          ),
        );
      case core.ArrowheadCirclePrimitive():
        converted.add(
          ArrowheadCirclePrimitiveData(
            center: DrawPoint(x: primitive.center[0], y: primitive.center[1]),
            radius: primitive.diameter / 2,
            fillMode: _fromCoreFillMode(primitive.fillMode),
          ),
        );
    }
  }

  return List<ArrowheadRenderPrimitiveData>.unmodifiable(converted);
}

core.Arrowhead? _toCoreRenderableArrowhead(ArrowheadStyle style) {
  switch (style) {
    case ArrowheadStyle.none:
      return null;
    case ArrowheadStyle.standard:
    case ArrowheadStyle.triangle:
    case ArrowheadStyle.triangleOutline:
    case ArrowheadStyle.square:
    case ArrowheadStyle.dot:
    case ArrowheadStyle.circle:
    case ArrowheadStyle.circleOutline:
    case ArrowheadStyle.diamond:
    case ArrowheadStyle.diamondOutline:
    case ArrowheadStyle.crowfootOne:
    case ArrowheadStyle.crowfootMany:
    case ArrowheadStyle.crowfootOneOrMany:
    case ArrowheadStyle.invertedTriangle:
    case ArrowheadStyle.verticalLine:
      return _toCoreArrowhead(style);
  }
}

core.Arrowhead _toCoreArrowhead(ArrowheadStyle style) {
  switch (style) {
    case ArrowheadStyle.standard:
      return 'arrow';
    case ArrowheadStyle.triangle:
      return 'triangle';
    case ArrowheadStyle.triangleOutline:
      return 'triangle_outline';
    case ArrowheadStyle.square:
      return 'square';
    case ArrowheadStyle.dot:
      return 'dot';
    case ArrowheadStyle.circle:
      return 'circle';
    case ArrowheadStyle.circleOutline:
      return 'circle_outline';
    case ArrowheadStyle.diamond:
      return 'diamond';
    case ArrowheadStyle.diamondOutline:
      return 'diamond_outline';
    case ArrowheadStyle.crowfootOne:
      return 'crowfoot_one';
    case ArrowheadStyle.crowfootMany:
      return 'crowfoot_many';
    case ArrowheadStyle.crowfootOneOrMany:
      return 'crowfoot_one_or_many';
    case ArrowheadStyle.invertedTriangle:
      return 'inverted_triangle';
    case ArrowheadStyle.verticalLine:
      return 'bar';
    case ArrowheadStyle.none:
      return 'arrow';
  }
}

core.ArrowEndpointPosition _toCoreEndpointPosition(
  ArrowEndpointPosition position,
) => position == ArrowEndpointPosition.start
    ? core.arrowEndpointPositionStart
    : core.arrowEndpointPositionEnd;

core.ArrowStrokeStyle _toCoreStrokeStyle(StrokeStyle style) {
  switch (style) {
    case StrokeStyle.solid:
      return 'solid';
    case StrokeStyle.dashed:
      return 'dashed';
    case StrokeStyle.dotted:
      return 'dotted';
  }
}

ArrowheadPrimitiveDashMode _fromCoreDashMode(core.ArrowheadDashMode dashMode) {
  if (dashMode == 'solid') {
    return ArrowheadPrimitiveDashMode.solid;
  }
  if (dashMode == 'dotted-cap') {
    return ArrowheadPrimitiveDashMode.dottedCap;
  }
  if (dashMode == 'inherit') {
    return ArrowheadPrimitiveDashMode.inherit;
  }
  return ArrowheadPrimitiveDashMode.solid;
}

ArrowheadPrimitiveFillMode _fromCoreFillMode(core.ArrowheadFillMode fillMode) {
  if (fillMode == 'stroke') {
    return ArrowheadPrimitiveFillMode.stroke;
  }
  if (fillMode == 'background') {
    return ArrowheadPrimitiveFillMode.background;
  }
  return ArrowheadPrimitiveFillMode.none;
}

List<core.CurvePathOp> _buildCoreCurveOps({
  required List<DrawPoint> points,
  required ArrowType arrowType,
}) {
  if (points.length < 2) {
    return const <core.CurvePathOp>[];
  }

  final ops = <core.CurvePathOp>[
    core.CurvePathOp(
      op: 'move',
      data: <double>[points.first.x, points.first.y],
    ),
  ];
  for (var index = 0; index < points.length - 1; index++) {
    final cubic = arrowType == ArrowType.curved && points.length >= 3
        ? _buildCurvedCubicSegment(points, index)
        : _buildLinearCubicSegment(points[index], points[index + 1]);
    ops.add(
      core.CurvePathOp(
        op: 'bcurveTo',
        data: <double>[
          cubic.control1.x,
          cubic.control1.y,
          cubic.control2.x,
          cubic.control2.y,
          cubic.end.x,
          cubic.end.y,
        ],
      ),
    );
  }
  return List<core.CurvePathOp>.unmodifiable(ops);
}

({DrawPoint control1, DrawPoint control2, DrawPoint end})
_buildLinearCubicSegment(DrawPoint start, DrawPoint end) {
  final control1 = DrawPoint(
    x: start.x + (end.x - start.x) / 3,
    y: start.y + (end.y - start.y) / 3,
  );
  final control2 = DrawPoint(
    x: start.x + (end.x - start.x) * (2 / 3),
    y: start.y + (end.y - start.y) * (2 / 3),
  );
  return (control1: control1, control2: control2, end: end);
}

({DrawPoint control1, DrawPoint control2, DrawPoint end})
_buildCurvedCubicSegment(List<DrawPoint> points, int index) {
  final p0 = index == 0 ? points[index] : points[index - 1];
  final p1 = points[index];
  final p2 = points[index + 1];
  final p3 = index + 2 < points.length ? points[index + 2] : points[index + 1];
  const tension = 1.0;
  final control1 = p1 + (p2 - p0) * (tension / 6);
  final control2 = p2 - (p3 - p1) * (tension / 6);
  return (control1: control1, control2: control2, end: p2);
}
