import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/element_hit_tester.dart';
import 'filter_data.dart';

class FilterHitTester implements ElementHitTester {
  const FilterHitTester();

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) {
    final data = element.data;
    if (data is! FilterData) {
      throw StateError(
        'FilterHitTester can only hit test FilterData (got '
        '${data.runtimeType})',
      );
    }

    final rect = element.rect;
    final localPosition = _toLocalPosition(element, position);
    return localPosition.x >= rect.minX - tolerance &&
        localPosition.x <= rect.maxX + tolerance &&
        localPosition.y >= rect.minY - tolerance &&
        localPosition.y <= rect.maxY + tolerance;
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
