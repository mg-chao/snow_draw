import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/element_hit_tester.dart';
import 'rectangle_data.dart';

class RectangleHitTester implements ElementHitTester {
  const RectangleHitTester();

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) {
    final data = element.data;
    if (data is! RectangleData) {
      throw StateError(
        'RectangleHitTester can only hit test RectangleData (got '
        '${data.runtimeType})',
      );
    }

    final rect = element.rect;
    final localPosition = _toLocalPosition(element, position);
    final strokeHit = _testStroke(
      rect: rect,
      position: localPosition,
      strokeWidth: data.strokeWidth,
      tolerance: tolerance,
    );
    if (strokeHit) {
      return true;
    }

    final fillOpacity = (data.fillColor.a * element.opacity).clamp(0.0, 1.0);
    if (fillOpacity <= 0) {
      return false;
    }

    return _isInsideRect(rect, localPosition);
  }

  DrawPoint _toLocalPosition(ElementState element, DrawPoint position) {
    if (element.rotation == 0) {
      return position;
    }
    final rect = element.rect;
    final space = ElementSpace(rotation: element.rotation, origin: rect.center);
    return space.fromWorld(position);
  }

  bool _isInsideRect(DrawRect rect, DrawPoint position) =>
      position.x >= rect.minX &&
      position.x <= rect.maxX &&
      position.y >= rect.minY &&
      position.y <= rect.maxY;

  bool _testStroke({
    required DrawRect rect,
    required DrawPoint position,
    required double strokeWidth,
    required double tolerance,
  }) {
    if (strokeWidth <= 0) {
      return false;
    }

    final strokeMargin = (strokeWidth / 2) + tolerance;
    final outerMinX = rect.minX - strokeMargin;
    final outerMaxX = rect.maxX + strokeMargin;
    final outerMinY = rect.minY - strokeMargin;
    final outerMaxY = rect.maxY + strokeMargin;

    final insideOuter =
        position.x >= outerMinX &&
        position.x <= outerMaxX &&
        position.y >= outerMinY &&
        position.y <= outerMaxY;
    if (!insideOuter) {
      return false;
    }

    final innerMinX = rect.minX + strokeMargin;
    final innerMaxX = rect.maxX - strokeMargin;
    final innerMinY = rect.minY + strokeMargin;
    final innerMaxY = rect.maxY - strokeMargin;

    final innerValid = innerMinX < innerMaxX && innerMinY < innerMaxY;
    if (!innerValid) {
      return true;
    }

    final insideInner =
        position.x > innerMinX &&
        position.x < innerMaxX &&
        position.y > innerMinY &&
        position.y < innerMaxY;
    return !insideInner;
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}
