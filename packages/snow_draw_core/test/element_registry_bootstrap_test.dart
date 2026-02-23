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

    test('supports custom mutable registries', () {
      final registry = _MutableElementRegistryProxy();

      final resolved = resolveElementRegistry(elementRegistry: registry);

      expect(resolved, same(registry));
      expect(resolved.supports(FilterData.typeIdToken), isTrue);
      expect(resolved.supports(SerialNumberData.typeIdToken), isTrue);
    });

    test('throws for read-only registries when built-ins are enabled', () {
      expect(
        () => resolveElementRegistry(
          elementRegistry: const _ReadOnlyElementRegistry(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('keeps read-only registries when built-ins are disabled', () {
      const registry = _ReadOnlyElementRegistry();

      final resolved = resolveElementRegistry(
        elementRegistry: registry,
        registerBuiltInElementDefinitions: false,
      );

      expect(resolved, same(registry));
    });
  });
}

class _ReadOnlyElementRegistry implements ElementRegistry {
  const _ReadOnlyElementRegistry();

  @override
  ElementDefinition<T>? getDefinition<T extends ElementData>(
    ElementTypeId<T> typeId,
  ) => null;

  @override
  ElementDefinition<ElementData>? getDefinitionByValue(String typeValue) =>
      null;

  @override
  Iterable<ElementTypeId<ElementData>> get registeredTypeIds =>
      const <ElementTypeId<ElementData>>[];

  @override
  bool supports<T extends ElementData>(ElementTypeId<T> typeId) => false;

  @override
  bool supportsTypeValue(String typeValue) => false;
}

class _MutableElementRegistryProxy implements MutableElementRegistry {
  _MutableElementRegistryProxy();

  final DefaultElementRegistry _delegate = DefaultElementRegistry();

  @override
  ElementDefinition<T>? getDefinition<T extends ElementData>(
    ElementTypeId<T> typeId,
  ) => _delegate.getDefinition(typeId);

  @override
  ElementDefinition<ElementData>? getDefinitionByValue(String typeValue) =>
      _delegate.getDefinitionByValue(typeValue);

  @override
  Iterable<ElementTypeId<ElementData>> get registeredTypeIds =>
      _delegate.registeredTypeIds;

  @override
  void register<T extends ElementData>(ElementDefinition<T> definition) {
    _delegate.register(definition);
  }

  @override
  bool supports<T extends ElementData>(ElementTypeId<T> typeId) =>
      _delegate.supports(typeId);

  @override
  bool supportsTypeValue(String typeValue) =>
      _delegate.supportsTypeValue(typeValue);
}
