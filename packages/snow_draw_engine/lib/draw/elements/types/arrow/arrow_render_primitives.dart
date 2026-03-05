import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import 'arrow_core_bridge.dart';
import 'arrow_geometry.dart';

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

/// Resolves arrowhead primitives via arrow-core first, then engine fallback.
///
/// The fallback path is retained as a defensive safety net for unknown or
/// malformed host styles.
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
    if (style == ArrowheadStyle.none || strokeWidth <= 0 || points.length < 2) {
      return const <ArrowheadRenderPrimitiveData>[];
    }

    final corePrimitives = _resolveCoreArrowheadPrimitives(
      points: points,
      arrowType: arrowType,
      style: style,
      strokeStyle: strokeStyle,
      strokeWidth: strokeWidth,
      position: position,
    );
    if (corePrimitives.isNotEmpty) {
      return corePrimitives;
    }

    return _resolveFallbackPrimitives(
      points: points,
      arrowType: arrowType,
      style: style,
      strokeWidth: strokeWidth,
      position: position,
      directionOverride: directionOverride,
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

List<ArrowheadRenderPrimitiveData> _resolveFallbackPrimitives({
  required List<DrawPoint> points,
  required ArrowType arrowType,
  required ArrowheadStyle style,
  required double strokeWidth,
  required ArrowEndpointPosition position,
  DrawPoint? directionOverride,
}) {
  final tip = position == ArrowEndpointPosition.start
      ? points.first
      : points.last;
  final resolvedDirection =
      directionOverride ??
      _resolveEndpointDirection(points, arrowType, position);
  final normalizedDirection = _normalizeDirection(resolvedDirection);
  if (normalizedDirection == null) {
    return const <ArrowheadRenderPrimitiveData>[];
  }

  var direction = normalizedDirection;
  if (style == ArrowheadStyle.invertedTriangle) {
    direction = DrawPoint(x: -direction.x, y: -direction.y);
  }

  final length = ArrowGeometry.resolveArrowheadLength(strokeWidth);
  final width = length * 0.6;
  final perp = DrawPoint(x: -direction.y, y: direction.x);

  ArrowheadLinePrimitiveData line(DrawPoint from, DrawPoint to) =>
      ArrowheadLinePrimitiveData(
        from: from,
        to: to,
        dashMode: ArrowheadPrimitiveDashMode.solid,
      );

  switch (style) {
    case ArrowheadStyle.none:
      return const <ArrowheadRenderPrimitiveData>[];
    case ArrowheadStyle.standard:
      final base = tip - direction * length;
      final left = base + perp * (width / 2);
      final right = base - perp * (width / 2);
      return <ArrowheadRenderPrimitiveData>[line(tip, left), line(tip, right)];
    case ArrowheadStyle.triangle:
    case ArrowheadStyle.triangleOutline:
    case ArrowheadStyle.invertedTriangle:
      final base = tip - direction * length;
      final left = base + perp * (width / 2);
      final right = base - perp * (width / 2);
      return <ArrowheadRenderPrimitiveData>[
        ArrowheadPolygonPrimitiveData(
          points: List<DrawPoint>.unmodifiable(<DrawPoint>[tip, left, right]),
          fillMode: style == ArrowheadStyle.triangleOutline
              ? ArrowheadPrimitiveFillMode.background
              : ArrowheadPrimitiveFillMode.stroke,
        ),
      ];
    case ArrowheadStyle.square:
      final side = length * 0.6;
      final half = side / 2;
      final center = tip - direction * half;
      final corner1 = center + perp * half + direction * half;
      final corner2 = center - perp * half + direction * half;
      final corner3 = center - perp * half - direction * half;
      final corner4 = center + perp * half - direction * half;
      return <ArrowheadRenderPrimitiveData>[
        ArrowheadPolygonPrimitiveData(
          points: List<DrawPoint>.unmodifiable(<DrawPoint>[
            corner1,
            corner2,
            corner3,
            corner4,
          ]),
          fillMode: ArrowheadPrimitiveFillMode.stroke,
        ),
      ];
    case ArrowheadStyle.dot:
    case ArrowheadStyle.circle:
    case ArrowheadStyle.circleOutline:
      final radius = length * 0.3;
      final center = tip - direction * radius;
      return <ArrowheadRenderPrimitiveData>[
        ArrowheadCirclePrimitiveData(
          center: center,
          radius: radius,
          fillMode: style == ArrowheadStyle.circleOutline
              ? ArrowheadPrimitiveFillMode.background
              : ArrowheadPrimitiveFillMode.stroke,
        ),
      ];
    case ArrowheadStyle.diamond:
    case ArrowheadStyle.diamondOutline:
      final base = tip - direction * length;
      final mid = tip - direction * (length / 2);
      final left = mid + perp * (width / 2);
      final right = mid - perp * (width / 2);
      return <ArrowheadRenderPrimitiveData>[
        ArrowheadPolygonPrimitiveData(
          points: List<DrawPoint>.unmodifiable(<DrawPoint>[
            tip,
            left,
            base,
            right,
          ]),
          fillMode: style == ArrowheadStyle.diamondOutline
              ? ArrowheadPrimitiveFillMode.background
              : ArrowheadPrimitiveFillMode.stroke,
        ),
      ];
    case ArrowheadStyle.crowfootOne:
      final base = tip - direction * length;
      final left = base + perp * (width / 2);
      final right = base - perp * (width / 2);
      return <ArrowheadRenderPrimitiveData>[line(left, right)];
    case ArrowheadStyle.crowfootMany:
      final base = tip - direction * length;
      final left = base + perp * (width / 2);
      final right = base - perp * (width / 2);
      return <ArrowheadRenderPrimitiveData>[line(left, tip), line(right, tip)];
    case ArrowheadStyle.crowfootOneOrMany:
      final base = tip - direction * length;
      final left = base + perp * (width / 2);
      final right = base - perp * (width / 2);
      return <ArrowheadRenderPrimitiveData>[
        line(left, tip),
        line(right, tip),
        line(left, right),
      ];
    case ArrowheadStyle.verticalLine:
      final half = width / 2;
      final left = tip + perp * half;
      final right = tip - perp * half;
      return <ArrowheadRenderPrimitiveData>[line(left, right)];
  }
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
      return toCoreArrowhead(style);
  }
}

DrawPoint? _resolveEndpointDirection(
  List<DrawPoint> points,
  ArrowType arrowType,
  ArrowEndpointPosition position,
) {
  if (points.length < 2) {
    return null;
  }
  if (position == ArrowEndpointPosition.start) {
    final resolved = ArrowGeometry.resolveStartDirection(points, arrowType);
    return resolved ?? _normalizeDirection(points.first - points[1]);
  }
  final resolved = ArrowGeometry.resolveEndDirection(points, arrowType);
  return resolved ??
      _normalizeDirection(points.last - points[points.length - 2]);
}

DrawPoint? _normalizeDirection(DrawPoint? direction) {
  if (direction == null) {
    return null;
  }
  final length = math.sqrt(
    direction.x * direction.x + direction.y * direction.y,
  );
  if (!length.isFinite || length <= 1e-6) {
    return null;
  }
  return DrawPoint(x: direction.x / length, y: direction.y / length);
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
