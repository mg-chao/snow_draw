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
    final localPosition = element.rotation == 0
        ? position
        : ElementSpace(
            rotation: element.rotation,
            origin: rect.center,
          ).fromWorld(position);

    return localPosition.x >= rect.minX - tolerance &&
        localPosition.x <= rect.maxX + tolerance &&
        localPosition.y >= rect.minY - tolerance &&
        localPosition.y <= rect.maxY + tolerance;
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}
