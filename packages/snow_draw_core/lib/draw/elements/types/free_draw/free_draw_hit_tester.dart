import '../../../config/draw_config.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../utils/lru_cache.dart';
import '../../core/element_hit_tester.dart';
import '../shared/hit_test_geometry.dart';
import 'free_draw_data.dart';

class FreeDrawHitTester implements ElementHitTester {
  const FreeDrawHitTester();

  static final _geometryCache = LruCache<String, _FreeDrawHitGeometry>(
    maxEntries: 256,
  );

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) {
    final data = element.data;
    if (data is! FreeDrawData) {
      throw StateError(
        'FreeDrawHitTester can only hit test FreeDrawData '
        '(got ${data.runtimeType})',
      );
    }

    final rect = element.rect;
    final worldLocalPosition = resolveElementLocalPosition(
      element: element,
      position: position,
    );
    final localPosition = _toElementRectLocalPosition(
      position: worldLocalPosition,
      rect: rect,
    );
    final localRect = _toElementRectLocalBounds(rect);
    final points = data.points;

    if (points.length == 2) {
      if (data.strokeWidth <= 0) {
        return false;
      }
      return _hitTestTwoPointStrokeFast(
        rect: localRect,
        points: points,
        localPosition: localPosition,
        tolerance: tolerance,
        strokeWidth: data.strokeWidth,
      );
    }

    final hasStroke = data.strokeWidth > 0;
    final fillOpacity = (data.fillColor.a * element.opacity).clamp(0.0, 1.0);
    final hasFill = fillOpacity > 0 && _isClosed(points, rect);
    if (!hasStroke && !hasFill) {
      return false;
    }
    final geometry = _resolveGeometry(
      element: element,
      data: data,
      points: points,
    );
    if (geometry.strokePoints.length < 2) {
      return false;
    }

    if (hasStroke &&
        _hitTestStroke(
          rect: localRect,
          strokeWidth: data.strokeWidth,
          localPosition: localPosition,
          tolerance: tolerance,
          flattenedStrokePoints: geometry.flattenedStrokePoints,
        )) {
      return true;
    }

    if (!hasFill ||
        geometry.fillOutline.length < 3 ||
        !isPointInsideRect(localRect, localPosition, 0)) {
      return false;
    }
    return isPointInsidePolygon(localPosition, geometry.fillOutline);
  }

  _FreeDrawHitGeometry _resolveGeometry({
    required ElementState element,
    required FreeDrawData data,
    required List<DrawPoint> points,
  }) {
    final rect = element.rect;
    final width = rect.width;
    final height = rect.height;
    final existing = _geometryCache.get(element.id);
    if (existing != null && existing.matches(data, width, height)) {
      return existing;
    }

    final strokePoints = _resolveStrokePoints(rect: rect, points: points);
    final flattenedStrokePoints = strokePoints.length < 2
        ? const <DrawPoint>[]
        : _resolveFlattenedStrokePoints(
            strokePoints: strokePoints,
            strokeWidth: data.strokeWidth,
          );
    final fillOutline = flattenedStrokePoints.length < 3
        ? const <DrawPoint>[]
        : _resolveClosedFillOutlinePointsFromFlattened(flattenedStrokePoints);
    final resolved = _FreeDrawHitGeometry(
      data: data,
      width: width,
      height: height,
      strokePoints: strokePoints,
      flattenedStrokePoints: flattenedStrokePoints,
      fillOutline: fillOutline,
    );
    _geometryCache.put(element.id, resolved);
    return resolved;
  }

  List<DrawPoint> _resolveStrokePoints({
    required DrawRect rect,
    required List<DrawPoint> points,
  }) {
    if (points.isEmpty) {
      return const <DrawPoint>[];
    }
    final width = rect.width;
    final height = rect.height;
    if (!width.isFinite || !height.isFinite || width < 0 || height < 0) {
      return const <DrawPoint>[];
    }
    return points
        .map(
          (point) => DrawPoint(
            x: point.x * width,
            y: point.y * height,
            pressure: point.pressure,
            timestamp: point.timestamp,
          ),
        )
        .toList(growable: false);
  }

  bool _isClosed(List<DrawPoint> points, DrawRect rect) {
    if (points.length < 3) {
      return false;
    }
    final first = points.first;
    final last = points.last;
    if (first == last) {
      return true;
    }
    const closeTolerance =
        ConfigDefaults.handleTolerance *
        ConfigDefaults.freeDrawCloseToleranceMultiplier;
    final dx = (first.x - last.x) * rect.width;
    final dy = (first.y - last.y) * rect.height;
    return (dx * dx + dy * dy) <= closeTolerance * closeTolerance;
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;

  DrawRect _toElementRectLocalBounds(DrawRect rect) =>
      DrawRect(maxX: rect.width, maxY: rect.height);

  DrawPoint _toElementRectLocalPosition({
    required DrawPoint position,
    required DrawRect rect,
  }) => DrawPoint(
    x: position.x - rect.minX,
    y: position.y - rect.minY,
    pressure: position.pressure,
    timestamp: position.timestamp,
  );

  bool _hitTestTwoPointStrokeFast({
    required DrawRect rect,
    required List<DrawPoint> points,
    required DrawPoint localPosition,
    required double tolerance,
    required double strokeWidth,
  }) => hitTestNormalizedTwoPointStroke(
    rect: rect,
    normalizedStart: points.first,
    normalizedEnd: points.last,
    localPosition: localPosition,
    strokeWidth: strokeWidth,
    tolerance: tolerance,
  );

  bool _hitTestStroke({
    required DrawRect rect,
    required double strokeWidth,
    required DrawPoint localPosition,
    required double tolerance,
    required List<DrawPoint> flattenedStrokePoints,
  }) {
    final radius = (strokeWidth / 2) + tolerance;
    if (!radius.isFinite || radius <= 0) {
      return false;
    }
    if (!isPointInsideRect(rect, localPosition, radius)) {
      return false;
    }

    final flattened = flattenedStrokePoints;
    if (flattened.length < 2) {
      return false;
    }
    final radiusSq = radius * radius;
    for (var i = 1; i < flattened.length; i++) {
      final distance = distanceSquaredToSegment(
        localPosition,
        flattened[i - 1],
        flattened[i],
      );
      if (distance <= radiusSq) {
        return true;
      }
    }
    return false;
  }

  List<DrawPoint> _resolveFlattenedStrokePoints({
    required List<DrawPoint> strokePoints,
    required double strokeWidth,
  }) {
    if (strokePoints.length < 3) {
      return strokePoints;
    }
    final closed = _sameLocation(strokePoints.first, strokePoints.last);
    final source = closed && strokePoints.length > 3
        ? strokePoints.sublist(0, strokePoints.length - 1)
        : strokePoints;
    final flattened = flattenCatmullRomDrawPoints(
      points: source,
      strokeWidth: strokeWidth,
      maxPoints: 1024,
      tension: 0.5,
      useOpenEndpointPhantomPoints: !closed,
    );
    if (flattened.length < 2) {
      return source;
    }
    if (closed && !_sameLocation(flattened.first, flattened.last)) {
      return <DrawPoint>[...flattened, flattened.first];
    }
    return flattened;
  }

  List<DrawPoint> _resolveClosedFillOutlinePointsFromFlattened(
    List<DrawPoint> flattened,
  ) {
    if (flattened.length < 3) {
      return const <DrawPoint>[];
    }
    final outline = <DrawPoint>[];
    DrawPoint? previous;
    for (final point in flattened) {
      if (previous != null && previous.x == point.x && previous.y == point.y) {
        continue;
      }
      outline.add(point);
      previous = point;
    }
    if (outline.length < 3) {
      return const <DrawPoint>[];
    }
    final first = outline.first;
    final last = outline.last;
    if (first.x != last.x || first.y != last.y) {
      outline.add(first);
    }
    return outline;
  }

  bool _sameLocation(DrawPoint a, DrawPoint b) => a.x == b.x && a.y == b.y;
}

class _FreeDrawHitGeometry {
  const _FreeDrawHitGeometry({
    required this.data,
    required this.width,
    required this.height,
    required this.strokePoints,
    required this.flattenedStrokePoints,
    required this.fillOutline,
  });

  final FreeDrawData data;
  final double width;
  final double height;
  final List<DrawPoint> strokePoints;
  final List<DrawPoint> flattenedStrokePoints;
  final List<DrawPoint> fillOutline;

  bool matches(FreeDrawData data, double width, double height) =>
      identical(this.data, data) &&
      this.width == width &&
      this.height == height;
}
