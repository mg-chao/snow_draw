import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart';

void main() {
  group('backend entrypoint contract', () {
    test('exports color and coordinate extensions used by app boundary', () {
      final color = const DrawColor(0xFF123456).toFlutterColor();
      expect(color, equals(const Color(0xFF123456)));

      const service = CoordinateService(camera: CameraState.initial);
      final world = service.screenOffsetToWorld(const Offset(10, 20));
      expect(world.x, 10);
      expect(world.y, 20);
      expect(service.worldPointToScreenOffset(world), const Offset(10, 20));
    });

    test(
      'exports Flutter text metrics service used by app context injection',
      () {
        expect(flutterTextMetricsService, isA<FlutterTextMetricsService>());

        final metrics = flutterTextMetricsService.measure(
          const TextLayoutRequest(
            data: TextData(text: 'Backend', fontSize: 14),
            maxWidth: 180,
          ),
        );

        expect(metrics.width, greaterThan(0));
        expect(metrics.height, greaterThan(0));
        expect(metrics.lineHeight, greaterThan(0));
        expect(metrics.lines, isNotEmpty);
      },
    );

    test(
      'exports Flutter draw context factory with built-in element defaults',
      () {
        final context = createFlutterDrawContext();

        expect(context.textMetricsService, same(flutterTextMetricsService));
        expect(
          context.elementRegistry.supports(RectangleData.typeIdToken),
          isTrue,
        );
        expect(context.elementRegistry.supports(TextData.typeIdToken), isTrue);

        final customRegistry = DefaultElementRegistry();
        final customContext = createFlutterDrawContext(
          elementRegistry: customRegistry,
          registerBuiltInElementDefinitions: false,
        );
        expect(customContext.elementRegistry.registeredTypeIds, isEmpty);
      },
    );

    test(
      'allows custom read-only registries when built-in registration is off',
      () {
        const readOnlyRegistry = _ReadOnlyElementRegistry();
        final context = createFlutterDrawContext(
          elementRegistry: readOnlyRegistry,
          registerBuiltInElementDefinitions: false,
        );

        expect(context.elementRegistry, same(readOnlyRegistry));
      },
    );

    test(
      'fails fast for custom registries when built-in registration is on',
      () {
        expect(
          () => createFlutterDrawContext(
            elementRegistry: const _ReadOnlyElementRegistry(),
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('registers built-ins for custom mutable registries', () {
      final mutableRegistry = _MutableElementRegistryProxy();
      final context = createFlutterDrawContext(
        elementRegistry: mutableRegistry,
      );

      expect(context.elementRegistry, same(mutableRegistry));
      expect(
        context.elementRegistry.supports(RectangleData.typeIdToken),
        isTrue,
      );
      expect(context.elementRegistry.supports(TextData.typeIdToken), isTrue);
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
