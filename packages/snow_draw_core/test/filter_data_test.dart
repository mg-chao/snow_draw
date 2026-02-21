import 'package:test/test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('FilterData.fromJson uses defaults', () {
    expect(FilterData.fromJson(const {}), const FilterData());
  });

  test('FilterData.withElementStyle applies filter fields', () {
    const style = ElementStyleConfig(
      filterType: CanvasFilterType.gaussianBlur,
      filterStrength: 0.75,
    );

    expect(
      const FilterData().withElementStyle(style),
      const FilterData(type: CanvasFilterType.gaussianBlur, strength: 0.75),
    );
  });

  test('FilterData.withStyleUpdate applies filter type and strength', () {
    const update = ElementStyleUpdate(
      filterType: CanvasFilterType.inversion,
      filterStrength: 0.3,
    );

    expect(
      const FilterData().withStyleUpdate(update),
      const FilterData(type: CanvasFilterType.inversion, strength: 0.3),
    );
  });

  test('FilterData normalizes strength values into [0, 1]', () {
    expect(const FilterData(strength: -1).strength, 0);
    expect(const FilterData(strength: 2).strength, 1);
    expect(const FilterData(strength: double.nan).strength, 1);
  });

  test('FilterData.fromJson normalizes out-of-range strengths', () {
    expect(FilterData.fromJson(const {'strength': -0.5}).strength, 0);
    expect(FilterData.fromJson(const {'strength': 1.5}).strength, 1);
  });
}
