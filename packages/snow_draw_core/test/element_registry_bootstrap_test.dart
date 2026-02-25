import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  group('resolveElementRegistry', () {
    test('creates a default registry and registers built-ins', () {
      final registry = resolveElementRegistry();

      expect(registry, isA<DefaultElementRegistry>());
      expect(registry.supports(RectangleData.typeIdToken), isTrue);
      expect(registry.supports(TextData.typeIdToken), isTrue);
    });

    test('supports custom registries', () {
      final registry = DefaultElementRegistry();

      final resolved = resolveElementRegistry(elementRegistry: registry);

      expect(resolved, same(registry));
      expect(resolved.supports(FilterData.typeIdToken), isTrue);
      expect(resolved.supports(SerialNumberData.typeIdToken), isTrue);
    });
  });
}
