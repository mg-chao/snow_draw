import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';

void main() {
  test('highlight is registered as a built-in element', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    expect(registry.get(HighlightData.typeIdToken), isNotNull);
  });
}
