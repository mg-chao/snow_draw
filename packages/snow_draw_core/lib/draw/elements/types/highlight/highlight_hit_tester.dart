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
    final localPosition = element.rotation == 0
        ? position
        : ElementSpace(
            rotation: element.rotation,
            origin: rect.center,
          ).fromWorld(position);

    return switch (data.shape) {
      HighlightShape.rectangle =>
        _testRectStroke(
              rect: rect,
              position: localPosition,
              strokeWidth: data.strokeWidth,
              tolerance: tolerance,
            ) ||
            rect.containsPoint(localPosition),
      HighlightShape.ellipse =>
        _testEllipseStroke(
              rect: rect,
              position: localPosition,
              strokeWidth: data.strokeWidth,
              tolerance: tolerance,
            ) ||
            _ellipseContains(
              dx: localPosition.x - rect.centerX,
              dy: localPosition.y - rect.centerY,
              rx: rect.width / 2,
              ry: rect.height / 2,
            ),
    };
  }

  bool _ellipseContains({
    required double dx,
    required double dy,
    required double rx,
    required double ry,
  }) {
    if (rx <= 0 || ry <= 0) {
      return false;
    }
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
    final outerRect = DrawRect(
      minX: rect.minX - strokeMargin,
      minY: rect.minY - strokeMargin,
      maxX: rect.maxX + strokeMargin,
      maxY: rect.maxY + strokeMargin,
    );
    if (!outerRect.containsPoint(position)) {
      return false;
    }

    final innerMinX = rect.minX + strokeMargin;
    final innerMaxX = rect.maxX - strokeMargin;
    final innerMinY = rect.minY + strokeMargin;
    final innerMaxY = rect.maxY - strokeMargin;

    return innerMinX >= innerMaxX ||
        innerMinY >= innerMaxY ||
        position.x <= innerMinX ||
        position.x >= innerMaxX ||
        position.y <= innerMinY ||
        position.y >= innerMaxY;
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

    if (!_ellipseContains(dx: dx, dy: dy, rx: outerRx, ry: outerRy)) {
      return false;
    }

    final innerRx = rx - margin;
    final innerRy = ry - margin;
    return innerRx <= 0 ||
        innerRy <= 0 ||
        !_ellipseContains(dx: dx, dy: dy, rx: innerRx, ry: innerRy);
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}
