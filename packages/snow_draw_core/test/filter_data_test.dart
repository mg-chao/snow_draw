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
    final updated = data.withElementStyle(style);

    expect(updated.type, style.filterType);
    expect(updated.strength, style.filterStrength);
  });

  test('FilterData.withStyleUpdate applies filter type and strength', () {
    const data = FilterData();
    const update = ElementStyleUpdate(
      filterType: CanvasFilterType.inversion,
      filterStrength: 0.3,
    );

    final updated = data.withStyleUpdate(update);

    expect(updated.type, update.filterType);
    expect(updated.strength, update.filterStrength);
  });

  test('FilterData normalizes strength values into [0, 1]', () {
    expect(const FilterData(strength: -1).strength, 0);
    expect(const FilterData(strength: 2).strength, 1);
    expect(const FilterData(strength: double.nan).strength, 1);
  });

  test('FilterData.fromJson normalizes out-of-range strengths', () {
    final negative = FilterData.fromJson(const {'strength': -0.5});
    final overflow = FilterData.fromJson(const {'strength': 1.5});

    expect(negative.strength, 0);
    expect(overflow.strength, 1);
  });
}
