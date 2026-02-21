import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_flutter_backend/visual/built_in_element_visuals.dart';
import 'package:snow_draw_flutter_backend/visual/element_visual_registry.dart';

void main() {
  group('built-in element visuals', () {
    test('covers every built-in core element type', () {
      final coreRegistry = DefaultElementRegistry();
      registerBuiltInElements(coreRegistry);
      final visualRegistry = createDefaultElementVisualRegistry();

      for (final typeId in coreRegistry.registeredTypeIds) {
        final visual = visualRegistry.getDefinitionByValue(typeId.value);
        expect(
          visual,
          isNotNull,
          reason: 'Missing visual for element type ${typeId.value}',
        );
        expect(
          visual!.icon,
          isNotNull,
          reason: 'Visual for ${typeId.value} must expose an icon',
        );
      }
    });

    test('registration is idempotent for existing entries', () {
      final visualRegistry = DefaultElementVisualRegistry();
      registerBuiltInElementVisuals(visualRegistry);
      registerBuiltInElementVisuals(visualRegistry);

      final coreRegistry = DefaultElementRegistry();
      registerBuiltInElements(coreRegistry);
      for (final typeId in coreRegistry.registeredTypeIds) {
        expect(visualRegistry.supportsTypeValue(typeId.value), isTrue);
      }
    });
  });
}
