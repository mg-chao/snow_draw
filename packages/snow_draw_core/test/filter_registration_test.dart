import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:test/test.dart';

void main() {
  test('filter is registered as a built-in element', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    expect(registry.get(FilterData.typeIdToken), isNotNull);
  });
}
