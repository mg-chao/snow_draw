import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/element_hit_tester.dart';
import '../arrow/arrow_hit_tester.dart';
import '../arrow/arrow_visual_cache.dart';
import '../shared/hit_test_geometry.dart';
import 'line_data.dart';

class LineHitTester implements ElementHitTester {
  const LineHitTester();

  static const _strokeTester = ArrowHitTester();

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
    final localPosition = _toLocalPosition(element, position);
    if (!_isInsideRect(rect, localPosition, 0)) {
      return false;
    }

    final cached = arrowVisualCache.resolve(element: element, data: data);
    final fillOutline = cached.getOrBuildClosedFillOutlinePoints(
      data.strokeWidth,
    );
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
      final localPosition = _toLocalPosition(element, position);
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

  DrawPoint _toLocalPosition(ElementState element, DrawPoint position) {
    if (element.rotation == 0) {
      return position;
    }
    final rect = element.rect;
    final space = ElementSpace(rotation: element.rotation, origin: rect.center);
    return space.fromWorld(position);
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
  }) {
    final radius = (data.strokeWidth / 2) + tolerance;
    if (!radius.isFinite || radius <= 0) {
      return false;
    }
    if (!_isInsideRect(rect, localPosition, radius)) {
      return false;
    }
    if (!rect.width.isFinite ||
        !rect.height.isFinite ||
        rect.width < 0 ||
        rect.height < 0) {
      return false;
    }

    final startPoint = data.points.first;
    final endPoint = data.points.last;
    final start = DrawPoint(
      x: rect.minX + (startPoint.x * rect.width),
      y: rect.minY + (startPoint.y * rect.height),
    );
    final end = DrawPoint(
      x: rect.minX + (endPoint.x * rect.width),
      y: rect.minY + (endPoint.y * rect.height),
    );
    if (!isFiniteDrawPoint(start) || !isFiniteDrawPoint(end)) {
      return false;
    }
    return distanceSquaredToSegment(localPosition, start, end) <=
        radius * radius;
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}
