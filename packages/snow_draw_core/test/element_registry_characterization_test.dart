import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/core/element_data.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/core/element_type_id.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_definition.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_definition.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_definition.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_definition.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_definition.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_definition.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_definition.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_definition.dart';

void main() {
  group('DefaultElementRegistry characterization', () {
    DefaultElementRegistry createRegistryWithBuiltIns() {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      return registry;
    }

    test(
      'registerBuiltInElements is idempotent and registers all built-ins',
      () {
        final registry = DefaultElementRegistry();

        registerBuiltInElements(registry);
        registerBuiltInElements(registry);

        final typeIds = registry.registeredTypeIds
            .map((type) => type.value)
            .toList();
        final expectedTypeIds = {
          rectangleDefinition.typeId.value,
          arrowDefinition.typeId.value,
          lineDefinition.typeId.value,
          freeDrawDefinition.typeId.value,
          filterDefinition.typeId.value,
          highlightDefinition.typeId.value,
          textDefinition.typeId.value,
          serialNumberDefinition.typeId.value,
        };

        expect(typeIds.toSet(), equals(expectedTypeIds));
        expect(typeIds, hasLength(expectedTypeIds.length));
      },
    );

    test('all built-in elements expose scene encoders', () {
      final registry = createRegistryWithBuiltIns();
      final builtInTypeValues = <String>{
        rectangleDefinition.typeId.value,
        arrowDefinition.typeId.value,
        lineDefinition.typeId.value,
        freeDrawDefinition.typeId.value,
        filterDefinition.typeId.value,
        highlightDefinition.typeId.value,
        textDefinition.typeId.value,
        serialNumberDefinition.typeId.value,
      };
      final missingSceneEncoders = <String>[];

      for (final typeValue in builtInTypeValues) {
        final definition = registry.getDefinitionByValue(typeValue);
        if (definition == null) {
          missingSceneEncoders.add(typeValue);
        }
      }

      expect(
        missingSceneEncoders,
        isEmpty,
        reason:
            'Built-in elements must keep scene encoders to avoid falling back '
            'to non-scene rendering paths.',
      );
    });

    test('lookups work with equivalent ElementTypeId instances', () {
      final registry = createRegistryWithBuiltIns();

      const lookupTypeId = ElementTypeId<ElementData>('rectangle');
      final definition = registry.getDefinition(lookupTypeId);

      expect(definition, isNotNull);
      expect(definition!.typeId.value, rectangleDefinition.typeId.value);
      expect(registry.supports(lookupTypeId), isTrue);
    });

    test('supports lookup by serialized type string', () {
      final registry = createRegistryWithBuiltIns();

      final definition = registry.getDefinitionByValue(
        rectangleDefinition.typeId.value,
      );

      expect(definition, isNotNull);
      expect(definition!.typeId.value, rectangleDefinition.typeId.value);
      expect(
        registry.supportsTypeValue(rectangleDefinition.typeId.value),
        isTrue,
      );
      expect(registry.supportsTypeValue('missing_type'), isFalse);
    });

    test('clone keeps entries detached from future registrations', () {
      final registry = DefaultElementRegistry()..register(rectangleDefinition);

      final cloned = registry.clone();

      registry.register(lineDefinition);
      cloned.register(arrowDefinition);

      expect(cloned.get(rectangleDefinition.typeId), isNotNull);
      expect(cloned.get(lineDefinition.typeId), isNull);
      expect(registry.get(arrowDefinition.typeId), isNull);
    });

    test('typed lookup with mismatched generic returns null', () {
      final registry = createRegistryWithBuiltIns();

      const mismatched = ElementTypeId<LineData>('rectangle');

      expect(registry.getDefinition(mismatched), isNull);
    });

    test('supports honors generic type when value matches another element', () {
      final registry = createRegistryWithBuiltIns();

      const mismatched = ElementTypeId<LineData>('rectangle');

      expect(registry.supports(mismatched), isFalse);
    });

    test('require throws StateError for mismatched generic lookups', () {
      final registry = createRegistryWithBuiltIns();

      const mismatched = ElementTypeId<LineData>('rectangle');

      expect(
        () => registry.require(mismatched),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('not registered'),
          ),
        ),
      );
    });
  });
}
