import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/element_hit_tester.dart';
import 'text_data.dart';

class TextHitTester implements ElementHitTester {
  const TextHitTester();

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) {
    final data = element.data;
    if (data is! TextData) {
      throw StateError(
        'TextHitTester can only hit test TextData (got ${data.runtimeType})',
      );
    }

    final rect = element.rect;
    final localPosition = _toLocalPosition(element, position);
    final minX = rect.minX - tolerance;
    final maxX = rect.maxX + tolerance;
    final minY = rect.minY - tolerance;
    final maxY = rect.maxY + tolerance;

    return localPosition.x >= minX &&
        localPosition.x <= maxX &&
        localPosition.y >= minY &&
        localPosition.y <= maxY;
  }

  DrawPoint _toLocalPosition(ElementState element, DrawPoint position) {
    if (element.rotation == 0) {
      return position;
    }
    final rect = element.rect;
    final space = ElementSpace(rotation: element.rotation, origin: rect.center);
    return space.fromWorld(position);
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}
