import '../../../config/draw_config.dart';
import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/element_hit_tester.dart';
import '../shared/hit_test_geometry.dart';
import 'free_draw_data.dart';
import 'free_draw_visual_cache.dart';

class FreeDrawHitTester implements ElementHitTester {
  const FreeDrawHitTester();

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
    final localPosition = _toLocalPosition(element, position);

    if (data.points.length == 2) {
      if (data.strokeWidth <= 0) {
        return false;
      }
      return _hitTestTwoPointStrokeFast(
        rect: rect,
        data: data,
        localPosition: localPosition,
        tolerance: tolerance,
      );
    }

    final hasStroke = data.strokeWidth > 0;
    final fillOpacity = (data.fillColor.a * element.opacity).clamp(0.0, 1.0);
    final hasFill = fillOpacity > 0 && _isClosed(data, rect);
    if (!hasStroke && !hasFill) {
      return false;
    }

    final cached = FreeDrawVisualCache.instance.resolve(
      element: element,
      data: data,
    );

    if (hasStroke &&
        _hitTestStroke(
          rect: rect,
          data: data,
          localPosition: localPosition,
          tolerance: tolerance,
          cached: cached,
        )) {
      return true;
    }

    if (!hasFill ||
        cached.pointCount < 3 ||
        !isPointInsideRect(rect, localPosition, 0)) {
      return false;
    }

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

  DrawPoint _toLocalPosition(ElementState element, DrawPoint position) {
    if (element.rotation == 0) {
      return position;
    }
    final rect = element.rect;
    final space = ElementSpace(rotation: element.rotation, origin: rect.center);
    return space.fromWorld(position);
  }

  bool _isClosed(FreeDrawData data, DrawRect rect) {
    if (data.points.length < 3) {
      return false;
    }
    final first = data.points.first;
    final last = data.points.last;
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

  bool _hitTestTwoPointStrokeFast({
    required DrawRect rect,
    required FreeDrawData data,
    required DrawPoint localPosition,
    required double tolerance,
  }) {
    final radius = (data.strokeWidth / 2) + tolerance;
    if (!radius.isFinite || radius <= 0) {
      return false;
    }
    if (!isPointInsideRect(rect, localPosition, radius)) {
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

  bool _hitTestStroke({
    required DrawRect rect,
    required FreeDrawData data,
    required DrawPoint localPosition,
    required double tolerance,
    required FreeDrawVisualEntry cached,
  }) {
    final radius = (data.strokeWidth / 2) + tolerance;
    if (!radius.isFinite || radius <= 0) {
      return false;
    }
    if (!isPointInsideRect(rect, localPosition, radius)) {
      return false;
    }

    final flattened = cached.getOrBuildFlattenedPoints(data.strokeWidth);
    if (flattened.length < 2) {
      return false;
    }

    final testPoint = DrawPoint(
      x: localPosition.x - rect.minX,
      y: localPosition.y - rect.minY,
    );
    final radiusSq = radius * radius;
    for (var i = 1; i < flattened.length; i++) {
      final distance = distanceSquaredToSegment(
        testPoint,
        flattened[i - 1],
        flattened[i],
      );
      if (distance <= radiusSq) {
        return true;
      }
    }
    return false;
  }
}
