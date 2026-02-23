import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:test/test.dart';

void main() {
  group('built-in type id compatibility', () {
    test('type id tokens stay stable', () {
      expect(RectangleData.typeIdToken.value, 'rectangle');
      expect(ArrowData.typeIdToken.value, 'arrow');
      expect(LineData.typeIdToken.value, 'line');
      expect(FreeDrawData.typeIdToken.value, 'free_draw');
      expect(FilterData.typeIdToken.value, 'filter');
      expect(HighlightData.typeIdToken.value, 'highlight');
      expect(TextData.typeIdToken.value, 'text');
      expect(SerialNumberData.typeIdToken.value, 'serial_number');
    });

    test('built-in registry contains exactly compatibility type ids', () {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);

      const expectedTypeIds = <String>{
        'rectangle',
        'arrow',
        'line',
        'free_draw',
        'filter',
        'highlight',
        'text',
        'serial_number',
      };
      final registeredTypeIds = registry.registeredTypeIds
          .map((typeId) => typeId.value)
          .toSet();

      expect(registeredTypeIds, equals(expectedTypeIds));
      expect(registeredTypeIds, hasLength(expectedTypeIds.length));
    });
  });
}
