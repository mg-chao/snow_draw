import 'dart:ui';

import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';

import 'element_type_renderer.dart';

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
