import 'dart:math' as math;

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import '../../core/element_hit_tester.dart';
import '../shared/hit_test_geometry.dart';
import 'arrow_geometry.dart';
import 'arrow_like_data.dart';
import 'arrow_render_primitives.dart';

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
    final shaftPoints = ArrowGeometry.sampleShaftForHitTest(
      points: geometry.insetDrawPoints,
      arrowType: data.arrowType,
      strokeWidth: data.strokeWidth,
    );

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
  required ArrowheadPrimitiveFillMode fillMode,
}) => (position, tolerance, _) {
  final dx = position.x - center.x;
  final dy = position.y - center.y;
  final distanceSq = dx * dx + dy * dy;
  final max = radius + tolerance;
  if (fillMode == ArrowheadPrimitiveFillMode.stroke) {
    return distanceSq <= max * max;
  }
  final min = math.max(0, radius - tolerance);
  return distanceSq >= min * min && distanceSq <= max * max;
};

_ArrowheadHitTarget _polygonTarget({
  required List<DrawPoint> vertices,
  required ArrowheadPrimitiveFillMode fillMode,
}) => (position, _, radiusSq) {
  if (_segmentsTarget(_closedSegments(vertices))(position, 0, radiusSq)) {
    return true;
  }
  if (fillMode != ArrowheadPrimitiveFillMode.stroke) {
    return false;
  }
  return _isPointInsidePolygon(position: position, vertices: vertices);
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

double _arrowheadLength(double strokeWidth) =>
    ArrowGeometry.resolveArrowheadLength(strokeWidth);

List<_ArrowheadHitTarget> _buildArrowheadTargets(
  ArrowGeometryDescriptor geometry,
) {
  final points = geometry.localDrawPoints;
  final data = geometry.data;
  final startDirection = geometry.startDirectionPoint;
  final endDirection = geometry.endDirectionPoint;

  final targets = <_ArrowheadHitTarget>[];
  if (data.startArrowhead != ArrowheadStyle.none) {
    final primitives = ArrowRenderPrimitives.resolveArrowheadPrimitives(
      points: points,
      arrowType: data.arrowType,
      style: data.startArrowhead,
      strokeStyle: data.strokeStyle,
      strokeWidth: data.strokeWidth,
      position: ArrowEndpointPosition.start,
      directionOverride: startDirection,
    );
    for (final primitive in primitives) {
      targets.add(_primitiveToTarget(primitive));
    }
  }

  if (data.endArrowhead != ArrowheadStyle.none) {
    final primitives = ArrowRenderPrimitives.resolveArrowheadPrimitives(
      points: points,
      arrowType: data.arrowType,
      style: data.endArrowhead,
      strokeStyle: data.strokeStyle,
      strokeWidth: data.strokeWidth,
      position: ArrowEndpointPosition.end,
      directionOverride: endDirection,
    );
    for (final primitive in primitives) {
      targets.add(_primitiveToTarget(primitive));
    }
  }

  return List<_ArrowheadHitTarget>.unmodifiable(targets);
}

_ArrowheadHitTarget _primitiveToTarget(ArrowheadRenderPrimitiveData primitive) {
  switch (primitive) {
    case ArrowheadLinePrimitiveData():
      return _segmentsTarget(<_ArrowheadSegment>[
        _ArrowheadSegment(start: primitive.from, end: primitive.to),
      ]);
    case ArrowheadPolygonPrimitiveData():
      return _polygonTarget(
        vertices: primitive.points,
        fillMode: primitive.fillMode,
      );
    case ArrowheadCirclePrimitiveData():
      return _circleTarget(
        center: primitive.center,
        radius: primitive.radius,
        fillMode: primitive.fillMode,
      );
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

bool _isPointInsidePolygon({
  required DrawPoint position,
  required List<DrawPoint> vertices,
}) {
  if (vertices.length < 3) {
    return false;
  }

  var inside = false;
  for (var i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
    final pi = vertices[i];
    final pj = vertices[j];
    final intersects =
        ((pi.y > position.y) != (pj.y > position.y)) &&
        (position.x <
            (pj.x - pi.x) * (position.y - pi.y) / (pj.y - pi.y) + pi.x);
    if (intersects) {
      inside = !inside;
    }
  }
  return inside;
}
