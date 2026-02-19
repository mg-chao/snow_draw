import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/edit/core/edit_event_factory.dart';
import 'package:snow_draw_core/draw/edit/core/edit_session_service.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/events/event_bus.dart';
import 'package:snow_draw_core/draw/events/state_events.dart';
import 'package:snow_draw_core/draw/models/application_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/store/dispatch/action_processor.dart';
import 'package:snow_draw_core/draw/store/history_manager.dart';
import 'package:snow_draw_core/draw/store/listener_registry.dart';
import 'package:snow_draw_core/draw/store/middleware/middleware_base.dart';
import 'package:snow_draw_core/draw/store/middleware/middleware_context.dart';
import 'package:snow_draw_core/draw/store/middleware/middleware_pipeline.dart';
import 'package:snow_draw_core/draw/store/snapshot_builder.dart';
import 'package:snow_draw_core/draw/store/state_manager.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ActionProcessor interaction mutation fast path', () {
    test(
      'bypasses middleware for UpdateCreatingElement when enabled',
      () async {
        final harness = _ActionProcessorHarness(
          enableInteractionMutationFastPath: true,
        );
        addTearDown(harness.dispose);

        await harness.processor.dispatch(
          const UpdateCreatingElement(currentPosition: DrawPoint(x: 42, y: 66)),
        );
        await harness.flushEvents();

        expect(harness.middlewareInvocations, isEmpty);
        expect(harness.listenerNotificationCount, 1);
        expect(harness.interactionEvents, hasLength(1));

        final interaction = harness.processor.state.application.interaction;
        expect(interaction, isA<CreatingState>());
        final creating = interaction as CreatingState;
        expect(
          creating.currentRect,
          const DrawRect(minX: 12, minY: 24, maxX: 42, maxY: 66),
        );
      },
    );

    test(
      'bypasses middleware for UpdateCreatingElementBatch when enabled',
      () async {
        final harness = _ActionProcessorHarness(
          enableInteractionMutationFastPath: true,
        );
        addTearDown(harness.dispose);

        await harness.processor.dispatch(
          UpdateCreatingElementBatch(
            positions: const [DrawPoint(x: 20, y: 30), DrawPoint(x: 52, y: 78)],
          ),
        );
        await harness.flushEvents();

        expect(harness.middlewareInvocations, isEmpty);
        expect(harness.listenerNotificationCount, 1);
        expect(harness.interactionEvents, hasLength(1));

        final interaction = harness.processor.state.application.interaction;
        expect(interaction, isA<CreatingState>());
        final creating = interaction as CreatingState;
        expect(
          creating.currentRect,
          const DrawRect(minX: 12, minY: 24, maxX: 52, maxY: 78),
        );
      },
    );

    test('uses middleware pipeline when fast path is disabled', () async {
      final harness = _ActionProcessorHarness(
        enableInteractionMutationFastPath: false,
      );
      addTearDown(harness.dispose);

      await harness.processor.dispatch(
        const UpdateCreatingElement(currentPosition: DrawPoint(x: 42, y: 66)),
      );
      await harness.flushEvents();

      expect(harness.middlewareInvocations, hasLength(1));
      expect(harness.middlewareInvocations.single, UpdateCreatingElement);
      expect(harness.listenerNotificationCount, 0);
      expect(harness.interactionEvents, isEmpty);

      final interaction = harness.processor.state.application.interaction;
      expect(interaction, isA<CreatingState>());
      final creating = interaction as CreatingState;
      expect(
        creating.currentRect,
        const DrawRect(minX: 12, minY: 24, maxX: 12, maxY: 24),
      );
    });
  });
}

class _ActionProcessorHarness {
  _ActionProcessorHarness({required bool enableInteractionMutationFastPath})
    : _eventBus = EventBus(),
      _drawContext = _createContext(),
      _stateManager = StateManager(_initialCreatingRectangleState()),
      _historyManager = HistoryManager(),
      _listenerRegistry = ListenerRegistry(),
      _middleware = _RecordingMiddleware() {
    var nextSessionId = 0;
    final editSessionService = EditSessionService.fromRegistry(
      _drawContext.editOperations,
      configProvider: () => _drawContext.configManager.current,
      logService: _drawContext.log,
    );

    final services = ActionProcessorServices(
      drawContext: _drawContext,
      stateManager: _stateManager,
      historyManager: _historyManager,
      configManager: _drawContext.configManager,
      listenerRegistry: _listenerRegistry,
      snapshotBuilder: const SnapshotBuilder(),
      editSessionService: editSessionService,
      sessionIdGenerator: () => 'session-${nextSessionId++}',
      isBatching: () => false,
      includeSelectionInHistory: false,
      eventBus: _eventBus,
      publishEditEvents: _publishedEditEvents.addAll,
      enableInteractionMutationFastPath: enableInteractionMutationFastPath,
    );

    final pipeline = MiddlewarePipeline(middlewares: [_middleware]);
    processor = ActionProcessor(services: services, pipeline: pipeline);

    _listenerRegistry.register((_) => listenerNotificationCount += 1);
    _interactionSubscription = _eventBus.on<InteractionChangedEvent>(
      interactionEvents.add,
    );
  }

  final EventBus _eventBus;
  final DrawContext _drawContext;
  final StateManager _stateManager;
  final HistoryManager _historyManager;
  final ListenerRegistry _listenerRegistry;
  final _RecordingMiddleware _middleware;
  final _publishedEditEvents = <EditSessionEvent>[];
  late final StreamSubscription<InteractionChangedEvent>
  _interactionSubscription;

  final interactionEvents = <InteractionChangedEvent>[];
  var listenerNotificationCount = 0;

  late final ActionProcessor processor;

  List<Type> get middlewareInvocations => _middleware.invocations;

  Future<void> flushEvents() async {
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> dispose() async {
    await _interactionSubscription.cancel();
    processor.dispose();
    await _drawContext.configManager.dispose();
    await _eventBus.dispose();
  }
}

class _RecordingMiddleware extends MiddlewareBase {
  final invocations = <Type>[];

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) {
    invocations.add(context.action.runtimeType);
    return next(context);
  }
}

DrawContext _createContext() {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  return DrawContext.withDefaults(
    elementRegistry: registry,
    config: DrawConfig.defaultConfig,
  );
}

DrawState _initialCreatingRectangleState() {
  const initialRect = DrawRect(minX: 12, minY: 24, maxX: 12, maxY: 24);
  const draftElement = ElementState(
    id: 'draft-rectangle',
    rect: initialRect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(),
  );
  return DrawState(
    application: ApplicationState.initial().copyWith(
      interaction: CreatingState(
        element: draftElement,
        startPosition: const DrawPoint(x: 12, y: 24),
        currentRect: initialRect,
      ),
    ),
  );
}
