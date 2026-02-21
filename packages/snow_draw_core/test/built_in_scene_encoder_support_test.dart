import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  test('built-in scene encoders support default element payloads', () {
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

      expect(
        () => definition.sceneEncoder.encodeScene(
          element: element,
          scaleFactor: 1,
          localeTag: 'en-US',
        ),
        returnsNormally,
        reason: 'Expected scene encoder support for type "$typeId".',
      );
    }
  });
}
