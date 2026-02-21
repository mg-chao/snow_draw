import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  group('core entrypoint contract', () {
    test('exports draw context and core value types', () {
      final context = DrawContext.withDefaults();
      final idGenerator = RandomStringIdGenerator();

      expect(context.config, isA<DrawConfig>());
      expect(context.textMetricsService, same(defaultTextMetricsService));
      expect(LogConfig.production.minLevel.toString(), contains('warning'));
      expect(LogConfig.production.emojiOutput, isFalse);
      expect(idGenerator.call(), isNotEmpty);

      const color = DrawColor(0xFF102030);
      expect(color.toARGB32(), 0xFF102030);
    });

    test('exports element registry APIs and built-in registration', () {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      const arrow = ArrowData(strokeStyle: StrokeStyle.dotted);
      const interaction = IdleState();

      expect(registry.registeredTypeIds, isNotEmpty);
      expect(registry, isA<ElementRegistry>());
      expect(arrow.strokeStyle, StrokeStyle.dotted);
      expect(interaction, isA<InteractionState>());
    });

    test('exports coordinate and scene contracts', () {
      const service = CoordinateService(
        camera: CameraState(position: DrawPoint(x: 10, y: 20), zoom: 1),
        scaleFactor: 2,
      );

      expect(
        service.screenToWorld(const DrawPoint(x: 14, y: 24)),
        const DrawPoint(x: 2, y: 2),
      );

      const scene = RenderScene(primitives: <RenderPrimitive>[]);
      expect(scene.primitives, isEmpty);
    });
  });
}
