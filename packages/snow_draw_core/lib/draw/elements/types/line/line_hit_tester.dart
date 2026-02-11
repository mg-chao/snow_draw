import 'dart:ui';

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/element_hit_tester.dart';
import '../arrow/arrow_hit_tester.dart';
import '../arrow/arrow_visual_cache.dart';
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

    if (data.strokeWidth > 0 &&
        _strokeTester.hitTest(
          element: element,
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
    if (cached.geometry.localPoints.length < 3) {
      return false;
    }

    final fillPath = cached.getOrBuildClosedFillPath();
    final testPoint = Offset(
      localPosition.x - rect.minX,
      localPosition.y - rect.minY,
    );
    return fillPath.contains(testPoint);
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
      position.x >= rect.minX - padding &&
      position.x <= rect.maxX + padding &&
      position.y >= rect.minY - padding &&
      position.y <= rect.maxY + padding;

  bool _isClosed(LineData data) =>
      data.points.length > 2 && data.points.first == data.points.last;

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}
