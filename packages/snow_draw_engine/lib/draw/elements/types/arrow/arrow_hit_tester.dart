import 'dart:math' as math;

import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import '../../core/element_hit_tester.dart';
import '../shared/hit_test_geometry.dart';
import 'arrow_core_bridge.dart';
import 'arrow_geometry.dart';
import 'arrow_like_data.dart';

class ArrowHitTester implements ElementHitTester {
  const ArrowHitTester();

  static const _cacheLimit = 512;
  static final _cache = LruCache<String, _ArrowHitTestCacheEntry>(
    maxEntries: _cacheLimit,
  );

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) {
    final data = element.data;
    if (data is! ArrowLikeData) {
      throw StateError(
        'ArrowHitTester can only hit test ArrowLikeData '
        '(got ${data.runtimeType})',
      );
    }

    if (data.strokeWidth <= 0) {
      return false;
    }

    final localPosition = resolveElementLocalPosition(
      element: element,
      position: position,
    );
    final rect = element.rect;
    final radius = (data.strokeWidth / 2) + tolerance;
    final boundsPadding = radius + _arrowheadExtent(data);
    if (!isPointInsideRect(rect, localPosition, boundsPadding)) {
      return false;
    }

    final cache = _resolveCache(element, data);
    final testPoint = DrawPoint(
      x: localPosition.x - rect.minX,
      y: localPosition.y - rect.minY,
    );

    final radiusSq = radius * radius;
    if (_hitTestSegments(cache.shaftPoints, testPoint, radiusSq)) {
      return true;
    }

    return _hitTestArrowheads(
      cache.arrowheadTargets,
      testPoint,
      radius,
      radiusSq,
    );
  }

  bool _hitTestSegments(
    List<DrawPoint> points,
    DrawPoint position,
    double radiusSq,
  ) {
    for (var i = 1; i < points.length; i++) {
      final distance = distanceSquaredToSegment(
        position,
        points[i - 1],
        points[i],
      );
      if (distance <= radiusSq) {
        return true;
      }
    }
    return false;
  }

  bool _hitTestArrowheads(
    List<_ArrowheadHitTarget> targets,
    DrawPoint position,
    double radius,
    double radiusSq,
  ) {
    for (final target in targets) {
      if (target(position, radius, radiusSq)) {
        return true;
      }
    }
    return false;
  }

  _ArrowHitTestCacheEntry _resolveCache(
    ElementState element,
    ArrowLikeData data,
  ) {
    final id = element.id;
    final rect = element.rect;
    final width = rect.width;
    final height = rect.height;
    final cached = _cache.get(id);
    if (cached != null && cached.matches(width, height, data)) {
      return cached;
    }

    final next = _ArrowHitTestCacheEntry.build(element: element, data: data);
    _cache.put(id, next);
    return next;
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}

class _ArrowHitTestCacheEntry {
  _ArrowHitTestCacheEntry({
    required this.width,
    required this.height,
    required this.data,
    required this.shaftPoints,
    required this.arrowheadTargets,
  });

  final double width;
  final double height;
  final ArrowLikeData data;
  final List<DrawPoint> shaftPoints;
  final List<_ArrowheadHitTarget> arrowheadTargets;

  bool matches(double width, double height, ArrowLikeData data) =>
      this.width == width &&
      this.height == height &&
      identical(this.data, data);

  factory _ArrowHitTestCacheEntry.build({
    required ElementState element,
    required ArrowLikeData data,
  }) {
    final rect = element.rect;
    final geometry = ArrowGeometryDescriptor(data: data, rect: rect);
    final points = geometry.localDrawPoints;
    final shaftPoints = switch (data.arrowType) {
      ArrowType.curved when points.length > 2 => _flattenCurvedShaft(
        points,
        data.strokeWidth,
      ),
      ArrowType.elbow when points.length > 2 => _flattenElbowShaft(
        points,
        data.strokeWidth,
      ),
      _ => points,
    };

    final arrowheadTargets = _buildArrowheadTargets(geometry);

    return _ArrowHitTestCacheEntry(
      width: rect.width,
      height: rect.height,
      data: data,
      shaftPoints: shaftPoints,
      arrowheadTargets: arrowheadTargets,
    );
  }
}

typedef _ArrowheadHitTarget =
    bool Function(DrawPoint position, double radius, double radiusSq);

class _ArrowheadSegment {
  const _ArrowheadSegment({required this.start, required this.end});

  final DrawPoint start;
  final DrawPoint end;
}

_ArrowheadHitTarget _segmentsTarget(List<_ArrowheadSegment> segments) =>
    (position, _, radiusSq) {
      for (final segment in segments) {
        final distance = distanceSquaredToSegment(
          position,
          segment.start,
          segment.end,
        );
        if (distance <= radiusSq) {
          return true;
        }
      }
      return false;
    };

_ArrowheadHitTarget _circleTarget({
  required DrawPoint center,
  required double radius,
}) => (position, tolerance, _) {
  final dx = position.x - center.x;
  final dy = position.y - center.y;
  final distanceSq = dx * dx + dy * dy;
  final min = math.max(0, radius - tolerance);
  final max = radius + tolerance;
  return distanceSq >= min * min && distanceSq <= max * max;
};

double _arrowheadExtent(ArrowLikeData data) {
  final hasArrowhead =
      data.startArrowhead != ArrowheadStyle.none ||
      data.endArrowhead != ArrowheadStyle.none;
  if (!hasArrowhead) {
    return 0;
  }
  final length = _arrowheadLength(data.strokeWidth);
  return length * 0.3;
}

double _arrowheadLength(double strokeWidth) => strokeWidth * 4 + 12.0;

List<DrawPoint> _flattenCurvedShaft(
  List<DrawPoint> points,
  double strokeWidth,
) => flattenCatmullRomDrawPoints(points: points, strokeWidth: strokeWidth);

List<DrawPoint> _flattenElbowShaft(List<DrawPoint> points, double strokeWidth) {
  if (points.length < 3) {
    return points;
  }

  final pathData = ArrowGeometry.generateElbowPathData(points: points);
  if (pathData.isEmpty) {
    return points;
  }

  final tokens = pathData
      .replaceAll(',', ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  if (tokens.isEmpty) {
    return points;
  }

  final flattened = <DrawPoint>[];
  DrawPoint? current;
  var index = 0;

  double? readNumber() {
    if (index >= tokens.length) {
      return null;
    }
    return double.tryParse(tokens[index++]);
  }

  while (index < tokens.length) {
    final command = tokens[index++].toUpperCase();
    if (command == 'M' || command == 'L') {
      final x = readNumber();
      final y = readNumber();
      if (x == null || y == null) {
        return points;
      }
      final next = DrawPoint(x: x, y: y);
      _appendPointIfDistinct(flattened, next);
      current = next;
      continue;
    }

    if (command == 'Q') {
      final cx = readNumber();
      final cy = readNumber();
      final x = readNumber();
      final y = readNumber();
      final start = current;
      if (cx == null || cy == null || x == null || y == null || start == null) {
        return points;
      }
      final control = DrawPoint(x: cx, y: cy);
      final end = DrawPoint(x: x, y: y);
      final chordLength = (end - start).distance(DrawPoint.zero);
      final roughLength =
          chordLength + (control - start).distance(DrawPoint.zero) * 0.5;
      final stepSize = math.max(1.5, strokeWidth * 0.7);
      final steps = roughLength <= 0 ? 6 : roughLength ~/ stepSize + 1;
      final clampedSteps = steps.clamp(6, 32);
      for (var i = 1; i <= clampedSteps; i++) {
        final t = i / clampedSteps;
        final point = _quadraticPoint(start, control, end, t);
        _appendPointIfDistinct(flattened, point);
      }
      current = end;
      continue;
    }

    return points;
  }

  return flattened.length >= 2 ? flattened : points;
}

void _appendPointIfDistinct(List<DrawPoint> points, DrawPoint point) {
  if (points.isEmpty) {
    points.add(point);
    return;
  }
  final previous = points.last;
  if ((previous.x - point.x).abs() <= 1e-6 &&
      (previous.y - point.y).abs() <= 1e-6) {
    return;
  }
  points.add(point);
}

DrawPoint _quadraticPoint(
  DrawPoint start,
  DrawPoint control,
  DrawPoint end,
  double t,
) {
  final oneMinusT = 1 - t;
  final oneMinusTSq = oneMinusT * oneMinusT;
  final tSq = t * t;
  return DrawPoint(
    x: oneMinusTSq * start.x + 2 * oneMinusT * t * control.x + tSq * end.x,
    y: oneMinusTSq * start.y + 2 * oneMinusT * t * control.y + tSq * end.y,
  );
}

List<_ArrowheadHitTarget> _buildArrowheadTargets(
  ArrowGeometryDescriptor geometry,
) {
  final points = geometry.localDrawPoints;
  final pointDirections = (
    start: geometry.startDirectionPoint,
    end: geometry.endDirectionPoint,
  );
  final data = geometry.data;

  final targets = <_ArrowheadHitTarget>[];
  final startDirection = pointDirections.start;
  if (startDirection != null && data.startArrowhead != ArrowheadStyle.none) {
    targets.addAll(
      _arrowheadTargetsForStyle(
        points: points,
        arrowType: data.arrowType,
        tip: points.first,
        direction: startDirection,
        style: data.startArrowhead,
        strokeWidth: data.strokeWidth,
        strokeStyle: data.strokeStyle,
        position: core.arrowEndpointPositionStart,
      ),
    );
  }

  final endDirection = pointDirections.end;
  if (endDirection != null && data.endArrowhead != ArrowheadStyle.none) {
    targets.addAll(
      _arrowheadTargetsForStyle(
        points: points,
        arrowType: data.arrowType,
        tip: points.last,
        direction: endDirection,
        style: data.endArrowhead,
        strokeWidth: data.strokeWidth,
        strokeStyle: data.strokeStyle,
        position: core.arrowEndpointPositionEnd,
      ),
    );
  }

  return targets;
}

List<_ArrowheadHitTarget> _arrowheadTargetsForStyle({
  required List<DrawPoint> points,
  required ArrowType arrowType,
  required DrawPoint tip,
  required DrawPoint direction,
  required ArrowheadStyle style,
  required double strokeWidth,
  required StrokeStyle strokeStyle,
  required core.ArrowEndpointPosition position,
}) {
  final coreTargets = _coreArrowheadTargetsForStyle(
    points: points,
    arrowType: arrowType,
    style: style,
    strokeWidth: strokeWidth,
    strokeStyle: strokeStyle,
    position: position,
  );
  if (coreTargets.isNotEmpty) {
    return coreTargets;
  }

  final fallbackTarget = _legacyArrowheadTargetForStyle(
    tip: tip,
    direction: direction,
    style: style,
    strokeWidth: strokeWidth,
  );
  return fallbackTarget == null
      ? const <_ArrowheadHitTarget>[]
      : <_ArrowheadHitTarget>[fallbackTarget];
}

List<_ArrowheadHitTarget> _coreArrowheadTargetsForStyle({
  required List<DrawPoint> points,
  required ArrowType arrowType,
  required ArrowheadStyle style,
  required double strokeWidth,
  required StrokeStyle strokeStyle,
  required core.ArrowEndpointPosition position,
}) {
  final coreArrowhead = _toCoreRenderableArrowhead(style);
  if (coreArrowhead == null || points.length < 2 || strokeWidth <= 0) {
    return const <_ArrowheadHitTarget>[];
  }

  final curveOps = _buildCoreCurveOps(points: points, arrowType: arrowType);
  if (curveOps.length < 2) {
    return const <_ArrowheadHitTarget>[];
  }

  final primitives = core.getArrowheadRenderPrimitives(
    core.ArrowheadRenderPrimitivesInput(
      arrowPoints: points
          .map((point) => <double>[point.x, point.y])
          .toList(growable: false),
      strokeWidth: strokeWidth,
      curveOps: curveOps,
      position: position,
      arrowhead: coreArrowhead,
      strokeStyle: _toCoreStrokeStyle(strokeStyle),
    ),
  );
  if (primitives.isEmpty) {
    return const <_ArrowheadHitTarget>[];
  }

  final targets = <_ArrowheadHitTarget>[];
  for (final primitive in primitives) {
    switch (primitive) {
      case core.ArrowheadLinePrimitive():
        targets.add(
          _segmentsTarget(<_ArrowheadSegment>[
            _ArrowheadSegment(
              start: DrawPoint(x: primitive.from[0], y: primitive.from[1]),
              end: DrawPoint(x: primitive.to[0], y: primitive.to[1]),
            ),
          ]),
        );
      case core.ArrowheadPolygonPrimitive():
        final vertices = primitive.points
            .map((point) => DrawPoint(x: point[0], y: point[1]))
            .toList(growable: false);
        if (vertices.length >= 2) {
          targets.add(_segmentsTarget(_closedSegments(vertices)));
        }
      case core.ArrowheadCirclePrimitive():
        targets.add(
          _circleTarget(
            center: DrawPoint(x: primitive.center[0], y: primitive.center[1]),
            radius: primitive.diameter / 2,
          ),
        );
    }
  }
  return List<_ArrowheadHitTarget>.unmodifiable(targets);
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

core.Arrowhead? _toCoreRenderableArrowhead(ArrowheadStyle style) {
  switch (style) {
    case ArrowheadStyle.none:
      return null;
    case ArrowheadStyle.square:
    case ArrowheadStyle.invertedTriangle:
      return null;
    default:
      return toCoreArrowhead(style);
  }
}

_ArrowheadHitTarget? _legacyArrowheadTargetForStyle({
  required DrawPoint tip,
  required DrawPoint direction,
  required ArrowheadStyle style,
  required double strokeWidth,
}) {
  final normalized = normalizeDrawVector(direction);
  if (normalized == null) {
    return null;
  }

  var dir = normalized;
  final length = _arrowheadLength(strokeWidth);
  final width = length * 0.6;

  if (style == ArrowheadStyle.invertedTriangle) {
    dir = DrawPoint(x: -dir.x, y: -dir.y);
  }

  final perp = DrawPoint(x: -dir.y, y: dir.x);
  switch (style) {
    case ArrowheadStyle.standard:
      final base = subtractScaledDrawPoint(tip, dir, length);
      final left = addScaledDrawPoint(base, perp, width / 2);
      final right = addScaledDrawPoint(base, perp, -width / 2);
      return _segmentsTarget([
        _ArrowheadSegment(start: tip, end: left),
        _ArrowheadSegment(start: tip, end: right),
      ]);
    case ArrowheadStyle.triangle:
    case ArrowheadStyle.invertedTriangle:
      final base = subtractScaledDrawPoint(tip, dir, length);
      final left = addScaledDrawPoint(base, perp, width / 2);
      final right = addScaledDrawPoint(base, perp, -width / 2);
      return _segmentsTarget(_closedSegments([tip, left, right]));
    case ArrowheadStyle.square:
      final side = length * 0.6;
      final half = side / 2;
      final center = subtractScaledDrawPoint(tip, dir, half);
      final corner1 = addDrawPoints(
        addScaledDrawPoint(center, perp, half),
        addScaledDrawPoint(DrawPoint.zero, dir, half),
      );
      final corner2 = addDrawPoints(
        addScaledDrawPoint(center, perp, -half),
        addScaledDrawPoint(DrawPoint.zero, dir, half),
      );
      final corner3 = addDrawPoints(
        addScaledDrawPoint(center, perp, -half),
        addScaledDrawPoint(DrawPoint.zero, dir, -half),
      );
      final corner4 = addDrawPoints(
        addScaledDrawPoint(center, perp, half),
        addScaledDrawPoint(DrawPoint.zero, dir, -half),
      );
      return _segmentsTarget(
        _closedSegments([corner1, corner2, corner3, corner4]),
      );
    case ArrowheadStyle.circle:
      final radius = length * 0.3;
      final center = subtractScaledDrawPoint(tip, dir, radius);
      return _circleTarget(center: center, radius: radius);
    case ArrowheadStyle.diamond:
      final base = subtractScaledDrawPoint(tip, dir, length);
      final mid = subtractScaledDrawPoint(tip, dir, length / 2);
      final left = addScaledDrawPoint(mid, perp, width / 2);
      final right = addScaledDrawPoint(mid, perp, -width / 2);
      return _segmentsTarget(_closedSegments([tip, left, base, right]));
    case ArrowheadStyle.verticalLine:
      final half = width / 2;
      final left = addScaledDrawPoint(tip, perp, half);
      final right = addScaledDrawPoint(tip, perp, -half);
      return _segmentsTarget([_ArrowheadSegment(start: left, end: right)]);
    case ArrowheadStyle.none:
      return null;
  }
}

List<_ArrowheadSegment> _closedSegments(List<DrawPoint> vertices) {
  final segments = <_ArrowheadSegment>[];
  for (var i = 0; i < vertices.length; i++) {
    final next = vertices[(i + 1) % vertices.length];
    segments.add(_ArrowheadSegment(start: vertices[i], end: next));
  }
  return segments;
}
