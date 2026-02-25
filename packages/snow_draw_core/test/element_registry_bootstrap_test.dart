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
      final registry = _CustomElementRegistryProxy();

      final resolved = resolveElementRegistry(elementRegistry: registry);

      expect(resolved, same(registry));
      expect(resolved.supports(FilterData.typeIdToken), isTrue);
      expect(resolved.supports(SerialNumberData.typeIdToken), isTrue);
    });
  });
}

class _CustomElementRegistryProxy implements DefaultElementRegistry {
  _CustomElementRegistryProxy();

  final DefaultElementRegistry _delegate = DefaultElementRegistry();

  @override
  void register<T extends ElementData>(ElementDefinition<T> definition) {
    _delegate.register(definition);
  }

  @override
  ElementDefinition<T>? getDefinition<T extends ElementData>(
    ElementTypeId<T> typeId,
  ) => _delegate.getDefinition(typeId);

  @override
  ElementDefinition<T>? get<T extends ElementData>(ElementTypeId<T> typeId) =>
      _delegate.get(typeId);

  @override
  ElementDefinition<ElementData>? getDefinitionByValue(String typeValue) =>
      _delegate.getDefinitionByValue(typeValue);

  @override
  Iterable<ElementTypeId<ElementData>> get registeredTypeIds =>
      _delegate.registeredTypeIds;

  @override
  bool supports<T extends ElementData>(ElementTypeId<T> typeId) =>
      _delegate.supports(typeId);

  @override
  bool supportsTypeValue(String typeValue) =>
      _delegate.supportsTypeValue(typeValue);

  @override
  ElementDefinition<T> require<T extends ElementData>(
    ElementTypeId<T> typeId,
  ) => _delegate.require(typeId);

  @override
  void clear() => _delegate.clear();

  @override
  DefaultElementRegistry clone() => _delegate.clone();
}
