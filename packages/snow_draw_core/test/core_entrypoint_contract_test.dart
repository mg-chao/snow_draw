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
      expect(EditOperationIds.move, 'move');

      const color = DrawColor(0xFF102030);
      expect(color.toARGB32(), 0xFF102030);
    });

    test('exports element registry APIs and built-in registration', () {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final normalizedArrowPoints = ArrowGeometry.normalizePoints(
        worldPoints: const <DrawPoint>[
          DrawPoint(x: 10, y: 10),
          DrawPoint(x: 20, y: 30),
        ],
        rect: const DrawRect(minX: 10, minY: 10, maxX: 20, maxY: 30),
      );
      const arrow = ArrowData(strokeStyle: StrokeStyle.dotted);
      const interaction = IdleState();
      const startEdit = StartEdit(
        operationId: EditOperationIds.rotate,
        position: DrawPoint.zero,
        params: RotateOperationParams(),
      );

      expect(registry.registeredTypeIds, isNotEmpty);
      expect(registry, isA<DefaultElementRegistry>());
      expect(arrow.strokeStyle, StrokeStyle.dotted);
      expect(normalizedArrowPoints.length, 2);
      expect(interaction, isA<InteractionState>());
      expect(startEdit.operationId, EditOperationIds.rotate);
    });

    test('exports coordinate and render-task contracts', () {
      const service = CoordinateService(
        camera: CameraState(position: DrawPoint(x: 10, y: 20), zoom: 1),
        scaleFactor: 2,
      );

      expect(
        service.screenToWorld(const DrawPoint(x: 14, y: 24)),
        const DrawPoint(x: 2, y: 2),
      );

      const plan = FrameRenderPlan(
        tasks: <FrameRenderTask>[
          BackgroundRenderTask(color: DrawColor(0xFFFFFFFF)),
        ],
        camera: CameraState.initial,
        scaleFactor: 1,
      );
      expect(plan.tasks, hasLength(1));
    });

    test('exports app-facing state, event, and cache contracts', () async {
      final appState = ApplicationState.initial();
      final domainState = DomainState.empty();
      final drawStateView = DrawStateView.fromState(DrawState.initial());
      final eventBus = EventBus();
      final cache = LruCache<String, int>(maxEntries: 2);
      final validation = ValidationFailedEvent(
        action: 'test-action',
        reason: 'test-reason',
      );

      cache.put('a', 1);
      cache.put('b', 2);
      expect(appState.view, isA<ViewState>());
      expect(domainState.document, isA<DocumentState>());
      expect(domainState.selection, isA<SelectionState>());
      expect(drawStateView.state, isA<DrawState>());
      expect(validation.action, 'test-action');
      expect(eventBus.tryEmit(validation), isFalse);
      final invalidator = () {};
      registerTextRenderingCacheInvalidator(invalidator);
      unregisterTextRenderingCacheInvalidator(invalidator);
      expect(cache.get('a'), 1);
      await eventBus.dispose();
    });
  });
}
