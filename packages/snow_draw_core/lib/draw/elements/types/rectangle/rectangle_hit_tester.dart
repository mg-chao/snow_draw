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
    if (_hitsStroke(
      rect: rect,
      position: localPosition,
      strokeWidth: data.strokeWidth,
      tolerance: tolerance,
    )) {
      return true;
    }

    final fillOpacity = data.fillColor.a * element.opacity;
    return fillOpacity > 0 && rect.containsPoint(localPosition);
  }

  DrawPoint _toLocalPosition(ElementState element, DrawPoint position) {
    if (element.rotation == 0) {
      return position;
    }
    final rect = element.rect;
    final space = ElementSpace(rotation: element.rotation, origin: rect.center);
    return space.fromWorld(position);
  }

  bool _hitsStroke({
    required DrawRect rect,
    required DrawPoint position,
    required double strokeWidth,
    required double tolerance,
  }) {
    if (strokeWidth <= 0) {
      return false;
    }

    final strokeMargin = (strokeWidth / 2) + tolerance;
    final outerRect = DrawRect(
      minX: rect.minX - strokeMargin,
      minY: rect.minY - strokeMargin,
      maxX: rect.maxX + strokeMargin,
      maxY: rect.maxY + strokeMargin,
    );
    if (!outerRect.containsPoint(position)) {
      return false;
    }

    final innerRect = DrawRect(
      minX: rect.minX + strokeMargin,
      minY: rect.minY + strokeMargin,
      maxX: rect.maxX - strokeMargin,
      maxY: rect.maxY - strokeMargin,
    );
    if (innerRect.minX >= innerRect.maxX || innerRect.minY >= innerRect.maxY) {
      return true;
    }

    return !_isStrictlyInside(innerRect, position);
  }

  bool _isStrictlyInside(DrawRect rect, DrawPoint position) =>
      position.x > rect.minX &&
      position.x < rect.maxX &&
      position.y > rect.minY &&
      position.y < rect.maxY;

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}
