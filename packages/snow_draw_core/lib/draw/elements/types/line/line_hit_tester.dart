import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import '../../core/element_hit_tester.dart';
import '../arrow/arrow_hit_tester.dart';
import '../shared/hit_test_geometry.dart';
import 'line_data.dart';

class LineHitTester implements ElementHitTester {
  const LineHitTester();

  static const _cacheLimit = 512;
  static const _strokeTester = ArrowHitTester();
  static final _fillOutlineCache = LruCache<String, _LineFillOutlineCacheEntry>(
    maxEntries: _cacheLimit,
  );

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) {
    final data = element.data;
    if (data is! LineData) {
      throw StateError(
        'LineHitTester can only hit test LineData (got ${data.runtimeType})',
      );
    }

    if (_hitTestStroke(
      element: element,
      data: data,
      position: position,
      tolerance: tolerance,
    )) {
      return true;
    }

    final fillOpacity = (data.fillColor.a * element.opacity).clamp(0.0, 1.0);
    if (fillOpacity <= 0 || !_isClosed(data)) {
      return false;
    }

    final rect = element.rect;
    final localPosition = resolveElementLocalPosition(
      element: element,
      position: position,
    );
    if (!_isInsideRect(rect, localPosition, 0)) {
      return false;
    }

    final fillOutline = _resolveFillOutline(element: element, data: data);
    if (fillOutline.length < 3) {
      return false;
    }
    final testPoint = DrawPoint(
      x: localPosition.x - rect.minX,
      y: localPosition.y - rect.minY,
    );
    return isPointInsidePolygon(testPoint, fillOutline);
  }

  bool _hitTestStroke({
    required ElementState element,
    required LineData data,
    required DrawPoint position,
    required double tolerance,
  }) {
    if (data.strokeWidth <= 0) {
      return false;
    }

    if (data.points.length == 2) {
      final rect = element.rect;
      final localPosition = resolveElementLocalPosition(
        element: element,
        position: position,
      );
      if (_hitTestTwoPointStrokeFast(
        rect: rect,
        data: data,
        localPosition: localPosition,
        tolerance: tolerance,
      )) {
        return true;
      }
    }

    return _strokeTester.hitTest(
      element: element,
      position: position,
      tolerance: tolerance,
    );
  }

  bool _isInsideRect(DrawRect rect, DrawPoint position, double padding) =>
      isPointInsideRect(rect, position, padding);

  bool _isClosed(LineData data) =>
      data.points.length > 2 && data.points.first == data.points.last;

  bool _hitTestTwoPointStrokeFast({
    required DrawRect rect,
    required LineData data,
    required DrawPoint localPosition,
    required double tolerance,
  }) => hitTestNormalizedTwoPointStroke(
    rect: rect,
    normalizedStart: data.points.first,
    normalizedEnd: data.points.last,
    localPosition: localPosition,
    strokeWidth: data.strokeWidth,
    tolerance: tolerance,
  );

  List<DrawPoint> _resolveFillOutline({
    required ElementState element,
    required LineData data,
  }) {
    final rect = element.rect;
    final id = element.id;
    final width = rect.width;
    final height = rect.height;
    final cached = _fillOutlineCache.get(id);
    if (cached != null && cached.matches(width, height, data)) {
      return cached.fillOutline;
    }

    final localPoints = data.points
        .map((point) => DrawPoint(x: point.x * width, y: point.y * height))
        .toList(growable: false);
    final fillOutline =
        data.arrowType == ArrowType.curved && localPoints.length > 2
        ? flattenCatmullRomDrawPoints(
            points: localPoints,
            strokeWidth: data.strokeWidth,
          )
        : localPoints;
    final normalizedOutline = _ensureClosedOutline(fillOutline);
    final entry = _LineFillOutlineCacheEntry(
      width: width,
      height: height,
      data: data,
      fillOutline: normalizedOutline,
    );
    _fillOutlineCache.put(id, entry);
    return normalizedOutline;
  }

  List<DrawPoint> _ensureClosedOutline(List<DrawPoint> points) {
    if (points.isEmpty || points.first == points.last) {
      return List<DrawPoint>.unmodifiable(points);
    }
    return List<DrawPoint>.unmodifiable([...points, points.first]);
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}

class _LineFillOutlineCacheEntry {
  const _LineFillOutlineCacheEntry({
    required this.width,
    required this.height,
    required this.data,
    required this.fillOutline,
  });

  final double width;
  final double height;
  final LineData data;
  final List<DrawPoint> fillOutline;

  bool matches(double width, double height, LineData data) =>
      this.width == width &&
      this.height == height &&
      identical(this.data, data);
}
