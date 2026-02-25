import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_engine.dart';
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
        );
        expect(customContext.elementRegistry.registeredTypeIds, isNotEmpty);
      },
    );

    test('fails fast for custom read-only registries', () {
      expect(
        () => createFlutterDrawContext(
          elementRegistry: _ReadOnlyElementRegistry(),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

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

    test('forwards custom text metrics service and event bus overrides', () {
      const customTextMetrics = _StubTextMetricsService();
      final customEventBus = EventBus();
      final context = createFlutterDrawContext(
        textMetricsService: customTextMetrics,
        eventBus: customEventBus,
      );

      expect(context.textMetricsService, same(customTextMetrics));
      expect(context.eventBus, same(customEventBus));
    });
  });
}

class _ReadOnlyElementRegistry extends DefaultElementRegistry {
  @override
  void register<T extends ElementData>(ElementDefinition<T> definition) {
    throw UnsupportedError('Read-only registry');
  }
}

class _MutableElementRegistryProxy extends DefaultElementRegistry {}

class _StubTextMetricsService implements TextMetricsService {
  const _StubTextMetricsService();

  @override
  TextMetrics measure(TextLayoutRequest request) => const TextMetrics(
    width: 1,
    height: 1,
    lineHeight: 1,
    lines: <TextLineMetrics>[TextLineMetrics(width: 1, height: 1)],
  );

  @override
  void clearCaches() {}
}
