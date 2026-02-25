import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:test/test.dart';

void main() {
  test('built-in task encoders support default element payloads', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    for (final typeId in registry.registeredTypeIds) {
      final definition = registry.getDefinitionByValue(typeId.value);
      expect(
        definition,
        isNotNull,
        reason: 'Missing definition for "$typeId".',
      );
      final element = ElementState(
        id: 'compat-$typeId',
        rect: const DrawRect(maxX: 100, maxY: 100),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: definition!.createDefaultData(),
      );

      final tasks = definition.taskEncoder.encodeTasks(
        element: element,
        localeTag: 'en-US',
      );
      expect(
        tasks,
        isNotEmpty,
        reason: 'Expected task encoder support for type "$typeId".',
      );
    }
  });
}
