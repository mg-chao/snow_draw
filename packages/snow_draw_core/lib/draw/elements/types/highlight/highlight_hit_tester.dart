import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/element_hit_tester.dart';
import 'highlight_data.dart';

class HighlightHitTester implements ElementHitTester {
  const HighlightHitTester();

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) {
    final data = element.data;
    if (data is! HighlightData) {
      throw StateError(
        'HighlightHitTester can only hit test HighlightData (got '
        '${data.runtimeType})',
      );
    }

    final rect = element.rect;
    final localPosition = _toLocalPosition(element, position);

    switch (data.shape) {
      case HighlightShape.rectangle:
        if (_testRectStroke(
          rect: rect,
          position: localPosition,
          strokeWidth: data.strokeWidth,
          tolerance: tolerance,
        )) {
          return true;
        }
        if (_fillOpacity(element, data) <= 0) {
          return false;
        }
        return _isInsideRect(rect, localPosition);
      case HighlightShape.ellipse:
        if (_testEllipseStroke(
          rect: rect,
          position: localPosition,
          strokeWidth: data.strokeWidth,
          tolerance: tolerance,
        )) {
          return true;
        }
        if (_fillOpacity(element, data) <= 0) {
          return false;
        }
        return _isInsideEllipse(rect, localPosition);
    }
  }

  DrawPoint _toLocalPosition(ElementState element, DrawPoint position) {
    if (element.rotation == 0) {
      return position;
    }
    final rect = element.rect;
    final space = ElementSpace(rotation: element.rotation, origin: rect.center);
    return space.fromWorld(position);
  }

  double _fillOpacity(ElementState element, HighlightData data) =>
      (data.color.a * element.opacity).clamp(0.0, 1.0);

  bool _isInsideRect(DrawRect rect, DrawPoint position) =>
      position.x >= rect.minX &&
      position.x <= rect.maxX &&
      position.y >= rect.minY &&
      position.y <= rect.maxY;

  bool _isInsideEllipse(DrawRect rect, DrawPoint position) {
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    if (rx <= 0 || ry <= 0) {
      return false;
    }
    final dx = position.x - rect.centerX;
    final dy = position.y - rect.centerY;
    return _ellipseContains(dx, dy, rx, ry);
  }

  bool _ellipseContains(double dx, double dy, double rx, double ry) {
    final nx = dx / rx;
    final ny = dy / ry;
    return (nx * nx) + (ny * ny) <= 1;
  }

  bool _testRectStroke({
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

  bool _testEllipseStroke({
    required DrawRect rect,
    required DrawPoint position,
    required double strokeWidth,
    required double tolerance,
  }) {
    if (strokeWidth <= 0) {
      return false;
    }

    final rx = rect.width / 2;
    final ry = rect.height / 2;
    if (rx <= 0 || ry <= 0) {
      return false;
    }

    final margin = (strokeWidth / 2) + tolerance;
    final outerRx = rx + margin;
    final outerRy = ry + margin;
    final dx = position.x - rect.centerX;
    final dy = position.y - rect.centerY;

    if (!_ellipseContains(dx, dy, outerRx, outerRy)) {
      return false;
    }

    final innerRx = rx - margin;
    final innerRy = ry - margin;
    if (innerRx <= 0 || innerRy <= 0) {
      return true;
    }

    return !_ellipseContains(dx, dy, innerRx, innerRy);
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}
