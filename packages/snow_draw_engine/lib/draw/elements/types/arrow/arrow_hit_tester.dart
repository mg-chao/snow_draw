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
    final hasCurvedShaft =
        data.arrowType == ArrowType.curved && points.length > 2;
    final shaftPoints = hasCurvedShaft
        ? _flattenCurvedShaft(points, data.strokeWidth)
        : points;

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
    final target = _arrowheadTargetForStyle(
      tip: points.first,
      direction: startDirection,
      style: data.startArrowhead,
      strokeWidth: data.strokeWidth,
    );
    if (target != null) {
      targets.add(target);
    }
  }

  final endDirection = pointDirections.end;
  if (endDirection != null && data.endArrowhead != ArrowheadStyle.none) {
    final target = _arrowheadTargetForStyle(
      tip: points.last,
      direction: endDirection,
      style: data.endArrowhead,
      strokeWidth: data.strokeWidth,
    );
    if (target != null) {
      targets.add(target);
    }
  }

  return targets;
}

_ArrowheadHitTarget? _arrowheadTargetForStyle({
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
