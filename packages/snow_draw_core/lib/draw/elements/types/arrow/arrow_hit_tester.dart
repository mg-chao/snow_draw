import 'dart:math' as math;
import 'dart:ui';

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/element_hit_tester.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';

class ArrowHitTester implements ElementHitTester {
  const ArrowHitTester();

  static const _cacheLimit = 512;
  static const _hotCacheSize = 6;
  static final _cache = <String, _ArrowHitTestCacheEntry>{};
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

    if (cache.hasCurvedShaft) {
      if (_hitTestSamples(cache.shaftSamples, testPoint, radiusSq)) {
        return true;
      }
    } else {
      if (_hitTestSegments(cache.shaftPoints, testPoint, radiusSq)) {
        return true;
      }
    }

    return _hitTestSamples(cache.arrowheadSamples, testPoint, radiusSq);
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

  bool _hitTestSamples(List<Offset> samples, Offset position, double radiusSq) {
    for (final sample in samples) {
      final dx = sample.dx - position.dx;
      final dy = sample.dy - position.dy;
      if (dx * dx + dy * dy <= radiusSq) {
        return true;
      }
    }
    return false;
  }

  double _distanceSquaredToSegment(Offset p, Offset a, Offset b) {
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
    for (final entry in _hotCache) {
      if (entry != null &&
          entry.id == id &&
          entry.matches(element.rect, data)) {
        return entry;
      }
    }

    final cached = _cache[id];
    if (cached != null && cached.matches(element.rect, data)) {
      _touchHotCache(cached);
      _cache.remove(id);
      _cache[id] = cached;
      return cached;
    }

    final next = _ArrowHitTestCacheEntry.build(element: element, data: data);
    _cache[id] = next;
    _touchHotCache(next);
    if (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
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
    required this.rect,
    required this.data,
    required this.shaftPoints,
    required this.shaftSamples,
    required this.arrowheadSamples,
    required this.hasCurvedShaft,
  });

  final String id;
  final DrawRect rect;
  final ArrowData data;
  final List<Offset> shaftPoints;
  final List<Offset> shaftSamples;
  final List<Offset> arrowheadSamples;
  final bool hasCurvedShaft;

  bool matches(DrawRect rect, ArrowData data) =>
      this.rect == rect && this.data == data;

  factory _ArrowHitTestCacheEntry.build({
    required ElementState element,
    required ArrowData data,
  }) {
    final rect = element.rect;
    final points = ArrowGeometry.resolveLocalPoints(
      rect: rect,
      normalizedPoints: data.points,
    );
    final hasCurvedShaft =
        data.arrowType == ArrowType.curved && points.length > 2;
    final shaftPoints = hasCurvedShaft
        ? points
        : (data.arrowType == ArrowType.polyline
              ? ArrowGeometry.expandPolylinePoints(points)
              : points);
    final samples = hasCurvedShaft
        ? _sampleCurvedShaft(points, _sampleStep(data.strokeWidth))
        : const <Offset>[];

    final arrowheadSamples = _buildArrowheadSamples(points, data);

    return _ArrowHitTestCacheEntry(
      id: element.id,
      rect: rect,
      data: data,
      shaftPoints: shaftPoints,
      shaftSamples: samples,
      arrowheadSamples: arrowheadSamples,
      hasCurvedShaft: hasCurvedShaft,
    );
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

List<Offset> _sampleCurvedShaft(List<Offset> points, double step) {
  if (points.length < 2 || step <= 0) {
    return const <Offset>[];
  }

  final samples = <Offset>[];
  for (var i = 0; i < points.length - 1; i++) {
    final chord = (points[i + 1] - points[i]).distance;
    final sampleCount = math.max(1, (chord / step).ceil());
    final start = i == 0 ? 0 : 1;
    for (var s = start; s <= sampleCount; s++) {
      final t = s / sampleCount;
      final point = ArrowGeometry.calculateCurvePoint(
        points: points,
        segmentIndex: i,
        t: t,
      );
      if (point != null) {
        samples.add(point);
      }
    }
  }
  return samples;
}

List<Offset> _samplePath(Path path, double step) {
  if (step <= 0) {
    return const <Offset>[];
  }

  final samples = <Offset>[];
  for (final metric in path.computeMetrics()) {
    final length = metric.length;
    if (length <= 0) {
      continue;
    }
    var distance = 0.0;
    while (distance < length) {
      final tangent = metric.getTangentForOffset(distance);
      if (tangent != null) {
        samples.add(tangent.position);
      }
      distance += step;
    }
    final endTangent = metric.getTangentForOffset(length);
    if (endTangent != null) {
      samples.add(endTangent.position);
    }
  }
  return samples;
}

List<Offset> _buildArrowheadSamples(List<Offset> points, ArrowData data) {
  if (points.length < 2) {
    return const <Offset>[];
  }

  final samples = <Offset>[];
  final step = _sampleStep(data.strokeWidth);
  final startInset = ArrowGeometry.calculateArrowheadInset(
    style: data.startArrowhead,
    strokeWidth: data.strokeWidth,
  );
  final endInset = ArrowGeometry.calculateArrowheadInset(
    style: data.endArrowhead,
    strokeWidth: data.strokeWidth,
  );
  final startDirectionOffset = ArrowGeometry.calculateArrowheadDirectionOffset(
    style: data.startArrowhead,
    strokeWidth: data.strokeWidth,
  );
  final endDirectionOffset = ArrowGeometry.calculateArrowheadDirectionOffset(
    style: data.endArrowhead,
    strokeWidth: data.strokeWidth,
  );

  final startDirection = ArrowGeometry.resolveStartDirection(
    points,
    data.arrowType,
    startInset: startInset,
    endInset: endInset,
    directionOffset: startDirectionOffset,
  );
  if (startDirection != null && data.startArrowhead != ArrowheadStyle.none) {
    final path = ArrowGeometry.buildArrowheadPath(
      tip: points.first,
      direction: startDirection,
      style: data.startArrowhead,
      strokeWidth: data.strokeWidth,
    );
    samples.addAll(_samplePath(path, step));
  }

  final endDirection = ArrowGeometry.resolveEndDirection(
    points,
    data.arrowType,
    startInset: startInset,
    endInset: endInset,
    directionOffset: endDirectionOffset,
  );
  if (endDirection != null && data.endArrowhead != ArrowheadStyle.none) {
    final path = ArrowGeometry.buildArrowheadPath(
      tip: points.last,
      direction: endDirection,
      style: data.endArrowhead,
      strokeWidth: data.strokeWidth,
    );
    samples.addAll(_samplePath(path, step));
  }

  return samples;
}
