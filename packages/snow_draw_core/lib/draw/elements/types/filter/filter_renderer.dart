import 'dart:ui';

import '../../../models/element_state.dart';
import '../../core/element_renderer.dart';
import 'filter_data.dart';

class FilterRenderer extends ElementTypeRenderer {
  const FilterRenderer();

  @override
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  }) {
    final data = element.data;
    if (data is! FilterData) {
      throw StateError(
        'FilterRenderer can only render FilterData (got '
        '${data.runtimeType})',
      );
    }
  }
}
