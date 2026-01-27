import 'dart:math' as math;
import 'dart:ui';

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import '../../core/element_hit_tester.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';

class ArrowHitTester implements ElementHitTester {
  const ArrowHitTester();

  static const _cacheLimit = 512;
  static const _hotCacheSize = 16;
  static final _cache = LruCache<String, _ArrowHitTestCacheEntry>(
    maxEntries: _cacheLimit,
  );
  static final _hotCache = List<_ArrowHitTestCacheEntry?>.filled(
    _hotCacheSize,
    null,
  );
  static var _hotCacheCursor = 0;

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) {
    final data = element.data;
    if (data is! ArrowData) {
      throw StateError(
        'ArrowHitTester can only hit test ArrowData (got ${data.runtimeType})',
      );
    }

    if (data.strokeWidth <= 0) {
      return false;
    }

    final localPosition = _toLocalPosition(element, position);
    final rect = element.rect;
    final radius = (data.strokeWidth / 2) + tolerance;
    final boundsPadding = radius + _arrowheadExtent(data);
    if (!_isInsideRect(rect, localPosition, boundsPadding)) {
      return false;
    }

    final cache = _resolveCache(element, data);
    final testPoint = Offset(
      localPosition.x - rect.minX,
      localPosition.y - rect.minY,
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

  DrawPoint _toLocalPosition(ElementState element, DrawPoint position) {
    if (element.rotation == 0) {
      return position;
    }
    final rect = element.rect;
    final space = ElementSpace(rotation: element.rotation, origin: rect.center);
    return space.fromWorld(position);
  }

  bool _hitTestSegments(List<Offset> points, Offset position, double radiusSq) {
    if (points.length < 2) {
      return false;
    }

    for (var i = 1; i < points.length; i++) {
      final distance = _distanceSquaredToSegment(
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
    Offset position,
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

  static double _distanceSquaredToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final abLengthSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLengthSq == 0) {
      final dx = ap.dx;
      final dy = ap.dy;
      return dx * dx + dy * dy;
    }
    var t = (ap.dx * ab.dx + ap.dy * ab.dy) / abLengthSq;
    if (t < 0) {
      t = 0;
    } else if (t > 1) {
      t = 1;
    }
    final closest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    final dx = p.dx - closest.dx;
    final dy = p.dy - closest.dy;
    return dx * dx + dy * dy;
  }

  _ArrowHitTestCacheEntry _resolveCache(ElementState element, ArrowData data) {
    final id = element.id;
    final width = element.rect.width;
    final height = element.rect.height;
    for (final entry in _hotCache) {
      if (entry != null &&
          entry.id == id &&
          entry.matches(width, height, data)) {
        return entry;
      }
    }

    final cached = _cache.get(id);
    if (cached != null && cached.matches(width, height, data)) {
      _touchHotCache(cached);
      return cached;
    }

    final next = _ArrowHitTestCacheEntry.build(element: element, data: data);
    _cache.put(id, next);
    _touchHotCache(next);
    return next;
  }

  void _touchHotCache(_ArrowHitTestCacheEntry entry) {
    _hotCache[_hotCacheCursor] = entry;
    _hotCacheCursor = (_hotCacheCursor + 1) % _hotCacheSize;
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}

class _ArrowHitTestCacheEntry {
  _ArrowHitTestCacheEntry({
    required this.id,
    required this.width,
    required this.height,
    required this.data,
    required this.shaftPoints,
    required this.arrowheadTargets,
  });

  final String id;
  final double width;
  final double height;
  final ArrowData data;
  final List<Offset> shaftPoints;
  final List<_ArrowheadHitTarget> arrowheadTargets;

  bool matches(double width, double height, ArrowData data) =>
      this.width == width &&
      this.height == height &&
      identical(this.data, data);

  factory _ArrowHitTestCacheEntry.build({
    required ElementState element,
    required ArrowData data,
  }) {
    final rect = element.rect;
    final geometry = ArrowGeometryDescriptor(data: data, rect: rect);
    final points = geometry.localPoints;
    final hasCurvedShaft =
        data.arrowType == ArrowType.curved && points.length > 2;
    final shaftPoints = hasCurvedShaft
        ? _flattenCurvedShaft(points, _sampleStep(data.strokeWidth))
        : (data.arrowType == ArrowType.polyline
              ? ArrowGeometry.expandPolylinePoints(points)
              : points);

    final arrowheadTargets = _buildArrowheadTargets(geometry);

    return _ArrowHitTestCacheEntry(
      id: element.id,
      width: rect.width,
      height: rect.height,
      data: data,
      shaftPoints: shaftPoints,
      arrowheadTargets: arrowheadTargets,
    );
  }
}

typedef _ArrowheadHitTarget =
    bool Function(Offset position, double radius, double radiusSq);

class _ArrowheadSegment {
  const _ArrowheadSegment({required this.start, required this.end});

  final Offset start;
  final Offset end;
}

_ArrowheadHitTarget _segmentsTarget(List<_ArrowheadSegment> segments) =>
    (position, radius, radiusSq) {
      for (final segment in segments) {
        final distance = ArrowHitTester._distanceSquaredToSegment(
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
  required Offset center,
  required double radius,
}) =>
    (position, tolerance, radiusSq) {
      final dx = position.dx - center.dx;
      final dy = position.dy - center.dy;
      final distanceSq = dx * dx + dy * dy;
      final min = math.max(0, radius - tolerance);
      final max = radius + tolerance;
      return distanceSq >= min * min && distanceSq <= max * max;
    };

class _CubicSegment {
  _CubicSegment(this.start, this.control1, this.control2, this.end);

  _CubicSegment.empty()
    : start = Offset.zero,
      control1 = Offset.zero,
      control2 = Offset.zero,
      end = Offset.zero;

  Offset start;
  Offset control1;
  Offset control2;
  Offset end;

  void set(Offset start, Offset control1, Offset control2, Offset end) {
    this
      ..start = start
      ..control1 = control1
      ..control2 = control2
      ..end = end;
  }
}

class _CubicSegmentPool {
  _CubicSegmentPool(this.capacity)
    : _segments = List<_CubicSegment>.generate(
        capacity,
        (_) => _CubicSegment.empty(),
      );

  final int capacity;
  final List<_CubicSegment> _segments;
  var _cursor = 0;

  _CubicSegment acquire() {
    if (_cursor < _segments.length) {
      return _segments[_cursor++];
    }
    return _CubicSegment.empty();
  }

  void reset() {
    _cursor = 0;
  }
}

double _sampleStep(double strokeWidth) => math.max(1, strokeWidth).toDouble();

double _arrowheadExtent(ArrowData data) {
  final hasArrowhead =
      data.startArrowhead != ArrowheadStyle.none ||
      data.endArrowhead != ArrowheadStyle.none;
  if (!hasArrowhead || data.strokeWidth <= 0) {
    return 0;
  }
  final length = _arrowheadLength(data.strokeWidth);
  return length * 0.3;
}

double _arrowheadLength(double strokeWidth) => strokeWidth * 4 + 12.0;

bool _isInsideRect(DrawRect rect, DrawPoint position, double padding) =>
    position.x >= rect.minX - padding &&
    position.x <= rect.maxX + padding &&
    position.y >= rect.minY - padding &&
    position.y <= rect.maxY + padding;

final _segmentPool = _CubicSegmentPool(96);

List<Offset> _flattenCurvedShaft(List<Offset> points, double step) {
  if (points.length < 2 || step <= 0) {
    return const <Offset>[];
  }

  _segmentPool.reset();
  final tolerance = math.max(0.5, step * 0.35);
  final toleranceSq = tolerance * tolerance;
  const maxPoints = 120;

  final flattened = <Offset>[points.first];
  for (var i = 0; i < points.length - 1; i++) {
    if (flattened.length >= maxPoints) {
      break;
    }
    final segment = _buildCubicSegment(points, i, _segmentPool);
    _flattenCubicSegment(
      segment,
      toleranceSq,
      flattened,
      maxPoints,
      _segmentPool,
    );
  }

  return flattened;
}

void _flattenCubicSegment(
  _CubicSegment segment,
  double toleranceSq,
  List<Offset> output,
  int maxPoints,
  _CubicSegmentPool pool,
) {
  final stack = <_CubicSegment>[segment];
  while (stack.isNotEmpty && output.length < maxPoints) {
    final current = stack.removeLast();
    if (_isCubicFlatEnough(current, toleranceSq) ||
        output.length >= maxPoints - 1) {
      output.add(current.end);
      continue;
    }
    final left = pool.acquire();
    final right = pool.acquire();
    _splitCubicSegment(current, left, right);
    stack
      ..add(right)
      ..add(left);
  }
}

bool _isCubicFlatEnough(_CubicSegment segment, double toleranceSq) {
  final dist1 = _distanceSquaredToLine(
    segment.control1,
    segment.start,
    segment.end,
  );
  final dist2 = _distanceSquaredToLine(
    segment.control2,
    segment.start,
    segment.end,
  );
  return math.max(dist1, dist2) <= toleranceSq;
}

double _distanceSquaredToLine(Offset point, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final lenSq = dx * dx + dy * dy;
  if (lenSq == 0) {
    final diff = point - a;
    return diff.dx * diff.dx + diff.dy * diff.dy;
  }
  final cross = dx * (point.dy - a.dy) - dy * (point.dx - a.dx);
  return (cross * cross) / lenSq;
}

void _splitCubicSegment(
  _CubicSegment segment,
  _CubicSegment left,
  _CubicSegment right,
) {
  Offset mid(Offset a, Offset b) =>
      Offset((a.dx + b.dx) * 0.5, (a.dy + b.dy) * 0.5);

  final p01 = mid(segment.start, segment.control1);
  final p12 = mid(segment.control1, segment.control2);
  final p23 = mid(segment.control2, segment.end);
  final p012 = mid(p01, p12);
  final p123 = mid(p12, p23);
  final p0123 = mid(p012, p123);

  left.set(segment.start, p01, p012, p0123);
  right.set(p0123, p123, p23, segment.end);
}

_CubicSegment _buildCubicSegment(
  List<Offset> points,
  int index,
  _CubicSegmentPool pool,
) {
  final p0 = index == 0 ? points[index] : points[index - 1];
  final p1 = points[index];
  final p2 = points[index + 1];
  final p3 = index + 2 < points.length ? points[index + 2] : points[index + 1];

  const tension = 1.0;
  final control1 = p1 + (p2 - p0) * (tension / 6);
  final control2 = p2 - (p3 - p1) * (tension / 6);
  return pool.acquire()..set(p1, control1, control2, p2);
}

List<_ArrowheadHitTarget> _buildArrowheadTargets(
  ArrowGeometryDescriptor geometry,
) {
  final points = geometry.localPoints;
  final data = geometry.data;
  if (points.length < 2 || data.strokeWidth <= 0) {
    return const <_ArrowheadHitTarget>[];
  }

  final targets = <_ArrowheadHitTarget>[];
  final startDirection = geometry.startDirection;
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

  final endDirection = geometry.endDirection;
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
  required Offset tip,
  required Offset direction,
  required ArrowheadStyle style,
  required double strokeWidth,
}) {
  if (style == ArrowheadStyle.none || strokeWidth <= 0) {
    return null;
  }
  final normalized = _normalize(direction);
  if (normalized == null) {
    return null;
  }

  var dir = normalized;
  final length = _arrowheadLength(strokeWidth);
  if (length <= 0) {
    return null;
  }
  final width = length * 0.6;

  if (style == ArrowheadStyle.invertedTriangle) {
    dir = Offset(-dir.dx, -dir.dy);
  }

  final perp = Offset(-dir.dy, dir.dx);
  switch (style) {
    case ArrowheadStyle.standard:
      final base = tip - dir * length;
      final left = base + perp * (width / 2);
      final right = base - perp * (width / 2);
      return _segmentsTarget([
        _ArrowheadSegment(start: tip, end: left),
        _ArrowheadSegment(start: tip, end: right),
      ]);
    case ArrowheadStyle.triangle:
    case ArrowheadStyle.invertedTriangle:
      final base = tip - dir * length;
      final left = base + perp * (width / 2);
      final right = base - perp * (width / 2);
      return _segmentsTarget(_closedSegments([tip, left, right]));
    case ArrowheadStyle.square:
      final side = length * 0.6;
      final half = side / 2;
      final center = tip - dir * half;
      final corner1 = center + perp * half + dir * half;
      final corner2 = center - perp * half + dir * half;
      final corner3 = center - perp * half - dir * half;
      final corner4 = center + perp * half - dir * half;
      return _segmentsTarget(
        _closedSegments([corner1, corner2, corner3, corner4]),
      );
    case ArrowheadStyle.circle:
      final radius = length * 0.3;
      final center = tip - dir * radius;
      return _circleTarget(center: center, radius: radius);
    case ArrowheadStyle.diamond:
      final base = tip - dir * length;
      final mid = tip - dir * (length / 2);
      final left = mid + perp * (width / 2);
      final right = mid - perp * (width / 2);
      return _segmentsTarget(
        _closedSegments([tip, left, base, right]),
      );
    case ArrowheadStyle.verticalLine:
      final half = width / 2;
      final left = tip + perp * half;
      final right = tip - perp * half;
      return _segmentsTarget([
        _ArrowheadSegment(start: left, end: right),
      ]);
    case ArrowheadStyle.none:
      return null;
  }
}

List<_ArrowheadSegment> _closedSegments(List<Offset> vertices) {
  if (vertices.length < 2) {
    return const <_ArrowheadSegment>[];
  }
  final segments = <_ArrowheadSegment>[];
  for (var i = 0; i < vertices.length; i++) {
    final next = vertices[(i + 1) % vertices.length];
    segments.add(_ArrowheadSegment(start: vertices[i], end: next));
  }
  return segments;
}

Offset? _normalize(Offset value) {
  final length = value.distance;
  if (length == 0) {
    return null;
  }
  return Offset(value.dx / length, value.dy / length);
}
