import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('FilterData.fromJson uses defaults', () {
    final data = FilterData.fromJson(const {});

    expect(data.type, ConfigDefaults.defaultFilterType);
    expect(data.strength, ConfigDefaults.defaultFilterStrength);
  });

  test('FilterData.withElementStyle applies filter fields', () {
    const style = ElementStyleConfig(
      filterType: CanvasFilterType.gaussianBlur,
      filterStrength: 0.75,
    );

    const data = FilterData();
    final updated = data.withElementStyle(style) as FilterData;

    expect(updated.type, style.filterType);
    expect(updated.strength, style.filterStrength);
  });

  test('FilterData.withStyleUpdate applies filter type and strength', () {
    const data = FilterData();
    const update = ElementStyleUpdate(
      filterType: CanvasFilterType.inversion,
      filterStrength: 0.3,
    );

    final updated = data.withStyleUpdate(update) as FilterData;

    expect(updated.type, update.filterType);
    expect(updated.strength, update.filterStrength);
  });
}
