import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/input/input_event.dart';
import 'package:snow_draw_core/draw/input/plugin_core.dart';
import 'package:snow_draw_core/draw/input/plugin_input_coordinator.dart';
import 'package:snow_draw_core/draw/input/plugin_registry.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';

void main() {
  group('PluginRegistry dispatch hooks', () {
    test('calls onAfterEvent once per plugin with final result', () async {
      final context = _createPluginContext();
      final registry = PluginRegistry(context: context);
      final afterCallsA = <PluginResult?>[];
      final afterCallsB = <PluginResult?>[];
      var handleCallsB = 0;

      final pluginA = _TestPlugin(
        id: 'a',
        priority: 0,
        onHandle: (_) async => const PluginResult.handled(message: 'A handled'),
        onAfter: (_, result) async => afterCallsA.add(result),
      );
      final pluginB = _TestPlugin(
        id: 'b',
        priority: 10,
        onHandle: (_) async {
          handleCallsB += 1;
          return const PluginResult.handled(message: 'B handled');
        },
        onAfter: (_, result) async => afterCallsB.add(result),
      );

      await registry.registerAll([pluginA, pluginB]);

      final result = await registry.dispatch(_pointerDown(), DrawState());

      expect(result, const PluginResult.handled(message: 'A handled'));
      expect(handleCallsB, 0);
      expect(afterCallsA, [result]);
      expect(afterCallsB, [result]);
    });

    test('still runs onAfterEvent when onBeforeEvent intercepts', () async {
      final context = _createPluginContext();
      final registry = PluginRegistry(context: context);
      final beforeAfterCalls = <PluginResult?>[];
      final observerAfterCalls = <PluginResult?>[];

      final intercepting = _TestPlugin(
        id: 'intercept',
        priority: 0,
        onBefore: (_) async => true,
        onHandle: (_) async => const PluginResult.unhandled(),
        onAfter: (_, result) async => beforeAfterCalls.add(result),
      );
      final observer = _TestPlugin(
        id: 'observer',
        priority: 10,
        onHandle: (_) async => const PluginResult.unhandled(),
        onAfter: (_, result) async => observerAfterCalls.add(result),
      );

      await registry.registerAll([intercepting, observer]);

      final result = await registry.dispatch(_pointerDown(), DrawState());

      expect(result, isNotNull);
      expect(result!.isHandled, isTrue);
      expect(beforeAfterCalls, [result]);
      expect(observerAfterCalls, [result]);
    });

    test('continues dispatch when onBeforeEvent throws', () async {
      final context = _createPluginContext();
      final registry = PluginRegistry(context: context);
      var fallbackHandled = 0;

      final throwing = _TestPlugin(
        id: 'throwing',
        priority: 0,
        onBefore: (_) async => throw StateError('before failed'),
        canHandle: (event, state) => false,
        onHandle: (_) async => const PluginResult.unhandled(),
      );
      final fallback = _TestPlugin(
        id: 'fallback',
        priority: 10,
        onHandle: (_) async {
          fallbackHandled += 1;
          return const PluginResult.handled(message: 'fallback handled');
        },
      );

      await registry.registerAll([throwing, fallback]);

      final result = await registry.dispatch(_pointerDown(), DrawState());

      expect(result, const PluginResult.handled(message: 'fallback handled'));
      expect(fallbackHandled, 1);
    });

    test(
      'continues dispatch when before-hook logging context is unavailable',
      () async {
        final state = DrawState();
        final context = PluginContext(
          stateProvider: () => state,
          contextProvider: () => throw StateError('context unavailable'),
          selectionConfigProvider: () => DrawConfig.defaultConfig.selection,
          dispatcher: (_) async {},
        );
        final registry = PluginRegistry(context: context);
        var fallbackHandled = 0;

        final throwing = _TestPlugin(
          id: 'throwing',
          priority: 0,
          onBefore: (_) async => throw StateError('before failed'),
          canHandle: (_, _) => false,
          onHandle: (_) async => const PluginResult.unhandled(),
        );
        final fallback = _TestPlugin(
          id: 'fallback',
          priority: 10,
          onHandle: (_) async {
            fallbackHandled += 1;
            return const PluginResult.handled(message: 'fallback handled');
          },
        );

        await registry.registerAll([throwing, fallback]);

        final result = await registry.dispatch(_pointerDown(), state);

        expect(result, const PluginResult.handled(message: 'fallback handled'));
        expect(fallbackHandled, 1);
      },
    );

    test('ignores onBeforeEvent interception from plugins '
        'that do not support the event type', () async {
      final context = _createPluginContext();
      final registry = PluginRegistry(context: context);
      var downHandled = 0;

      final moveOnlyInterceptor = _TestPlugin(
        id: 'move-only-interceptor',
        priority: 0,
        supportedEventTypes: const {PointerMoveInputEvent},
        onBefore: (_) async => true,
        canHandle: (_, _) => false,
        onHandle: (_) async => const PluginResult.unhandled(),
      );
      final downHandler = _TestPlugin(
        id: 'down-handler',
        priority: 10,
        onHandle: (_) async {
          downHandled += 1;
          return const PluginResult.handled(message: 'down handled');
        },
      );

      await registry.registerAll([moveOnlyInterceptor, downHandler]);

      final result = await registry.dispatch(_pointerDown(), DrawState());

      expect(result, const PluginResult.handled(message: 'down handled'));
      expect(downHandled, 1);
    });

    test(
      'runs onAfterEvent only for plugins supporting the event type',
      () async {
        final context = _createPluginContext();
        final registry = PluginRegistry(context: context);
        final downAfterCalls = <PluginResult?>[];
        final moveAfterCalls = <PluginResult?>[];

        final downPlugin = _TestPlugin(
          id: 'down',
          priority: 0,
          onHandle: (_) async => const PluginResult.handled(message: 'down'),
          onAfter: (_, result) async => downAfterCalls.add(result),
        );
        final movePlugin = _TestPlugin(
          id: 'move',
          priority: 10,
          supportedEventTypes: const {PointerMoveInputEvent},
          onHandle: (_) async => const PluginResult.handled(message: 'move'),
          onAfter: (_, result) async => moveAfterCalls.add(result),
        );

        await registry.registerAll([downPlugin, movePlugin]);

        final result = await registry.dispatch(_pointerDown(), DrawState());

        expect(result, const PluginResult.handled(message: 'down'));
        expect(downAfterCalls, [result]);
        expect(moveAfterCalls, isEmpty);
      },
    );
  });

  group('PluginRegistry registerAll transactional behavior', () {
    test(
      'rolls back loaded plugins when a later plugin fails during onLoad',
      () async {
        final context = _createPluginContext();
        final registry = PluginRegistry(context: context);

        final okPlugin = _LifecyclePlugin(id: 'ok');
        final failingPlugin = _LifecyclePlugin(id: 'failing', failOnLoad: true);

        await expectLater(
          registry.registerAll([okPlugin, failingPlugin]),
          throwsA(isA<StateError>()),
        );

        expect(okPlugin.loadCount, 1);
        expect(okPlugin.unloadCount, 1);
        expect(failingPlugin.loadCount, 1);
        expect(failingPlugin.unloadCount, 1);
        expect(registry.pluginCount, 0);
        expect(registry.isRegistered('ok'), isFalse);
        expect(registry.isRegistered('failing'), isFalse);
      },
    );

    test(
      'rethrows the original onLoad error when rollback logging also fails',
      () async {
        final state = DrawState();
        final context = PluginContext(
          stateProvider: () => state,
          contextProvider: () => throw StateError('context unavailable'),
          selectionConfigProvider: () => DrawConfig.defaultConfig.selection,
          dispatcher: (_) async {},
        );
        final registry = PluginRegistry(context: context);
        final failingPlugin = _LifecyclePlugin(
          id: 'failing',
          failOnLoad: true,
          failOnUnload: true,
        );

        await expectLater(
          registry.registerAll([failingPlugin]),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'toString',
              contains('onLoad failed for failing'),
            ),
          ),
        );

        expect(failingPlugin.loadCount, 1);
        expect(failingPlugin.unloadCount, 1);
        expect(registry.pluginCount, 0);
        expect(registry.isRegistered('failing'), isFalse);
      },
    );

    test(
      'fails fast on duplicate ids in one batch without loading any plugin',
      () async {
        final context = _createPluginContext();
        final registry = PluginRegistry(context: context);

        final first = _LifecyclePlugin(id: 'duplicate');
        final second = _LifecyclePlugin(id: 'duplicate');

        await expectLater(
          registry.registerAll([first, second]),
          throwsA(isA<StateError>()),
        );

        expect(first.loadCount, 0);
        expect(second.loadCount, 0);
        expect(registry.pluginCount, 0);
      },
    );

    test('fails fast when batch contains an already-registered id', () async {
      final context = _createPluginContext();
      final registry = PluginRegistry(context: context);

      final existing = _LifecyclePlugin(id: 'existing');
      await registry.register(existing);
      final duplicate = _LifecyclePlugin(id: 'existing');
      final another = _LifecyclePlugin(id: 'another');

      await expectLater(
        registry.registerAll([duplicate, another]),
        throwsA(isA<StateError>()),
      );

      expect(duplicate.loadCount, 0);
      expect(another.loadCount, 0);
      expect(registry.pluginCount, 1);
      expect(registry.isRegistered('existing'), isTrue);
      expect(registry.isRegistered('another'), isFalse);
    });
  });

  group('PluginInputCoordinator ordering', () {
    test(
      'serializes event handling to avoid overlapping plugin execution',
      () async {
        final context = _createPluginContext();
        final coordinator = PluginInputCoordinator(pluginContext: context);
        final probe = _ProbeSequentialPlugin();

        await coordinator.registry.register(probe);

        final firstEvent = _pointerDown(x: 1);
        final secondEvent = _pointerDown(x: 2);

        final future1 = coordinator.handleEvent(firstEvent);
        final future2 = coordinator.handleEvent(secondEvent);

        await Future.wait([future1, future2]);

        expect(probe.hadOverlap, isFalse);
        expect(probe.timeline, ['start:1', 'end:1', 'start:2', 'end:2']);

        await coordinator.dispose();
      },
    );
  });

  group('PluginInputCoordinator event coalescing', () {
    test(
      'coalesces queued pointer move events while processing is busy',
      () async {
        final context = _createPluginContext();
        final coordinator = PluginInputCoordinator(pluginContext: context);
        final firstEventGate = Completer<void>();
        final plugin = _CoalescingProbePlugin(
          pauseOnFirstEvent: firstEventGate,
        );

        await coordinator.registry.register(plugin);

        final firstFuture = coordinator.handleEvent(_pointerMove(x: 1));
        await plugin.firstEventStarted.future;

        final secondFuture = coordinator.handleEvent(_pointerMove(x: 2));
        final thirdFuture = coordinator.handleEvent(_pointerMove(x: 3));

        expect(
          await secondFuture,
          const PluginResult.consumed(
            message: 'Event coalesced by coordinator',
          ),
        );

        firstEventGate.complete();

        expect(
          await firstFuture,
          const PluginResult.handled(message: 'coalescing probe handled'),
        );
        expect(
          await thirdFuture,
          const PluginResult.handled(message: 'coalescing probe handled'),
        );
        expect(plugin.events, hasLength(2));

        final processedXs = plugin.events
            .whereType<PointerMoveInputEvent>()
            .map((event) => event.position.x)
            .toList();
        expect(processedXs, [1, 3]);
        expect(coordinator.getStats()['coalescedEvents'], 1);

        await coordinator.dispose();
      },
    );

    test('does not coalesce across different event types', () async {
      final context = _createPluginContext();
      final coordinator = PluginInputCoordinator(pluginContext: context);
      final firstEventGate = Completer<void>();
      final plugin = _CoalescingProbePlugin(pauseOnFirstEvent: firstEventGate);

      await coordinator.registry.register(plugin);

      final firstFuture = coordinator.handleEvent(_pointerMove(x: 1));
      await plugin.firstEventStarted.future;

      final secondFuture = coordinator.handleEvent(_pointerDown(x: 2));
      final thirdFuture = coordinator.handleEvent(_pointerMove(x: 3));

      firstEventGate.complete();

      expect(
        await firstFuture,
        const PluginResult.handled(message: 'coalescing probe handled'),
      );
      expect(
        await secondFuture,
        const PluginResult.handled(message: 'coalescing probe handled'),
      );
      expect(
        await thirdFuture,
        const PluginResult.handled(message: 'coalescing probe handled'),
      );

      expect(plugin.events.map((event) => event.runtimeType).toList(), [
        PointerMoveInputEvent,
        PointerDownInputEvent,
        PointerMoveInputEvent,
      ]);
      expect(coordinator.getStats()['coalescedEvents'], 0);

      await coordinator.dispose();
    });

    test(
      'does not coalesce pointer move events when modifiers differ',
      () async {
        final context = _createPluginContext();
        final coordinator = PluginInputCoordinator(pluginContext: context);
        final firstEventGate = Completer<void>();
        final plugin = _CoalescingProbePlugin(
          pauseOnFirstEvent: firstEventGate,
        );

        await coordinator.registry.register(plugin);

        final firstFuture = coordinator.handleEvent(_pointerMove(x: 1));
        await plugin.firstEventStarted.future;

        final secondFuture = coordinator.handleEvent(_pointerMove(x: 2));
        final thirdFuture = coordinator.handleEvent(
          _pointerMove(x: 3, modifiers: const KeyModifiers(shift: true)),
        );

        firstEventGate.complete();

        expect(
          await firstFuture,
          const PluginResult.handled(message: 'coalescing probe handled'),
        );
        expect(
          await secondFuture,
          const PluginResult.handled(message: 'coalescing probe handled'),
        );
        expect(
          await thirdFuture,
          const PluginResult.handled(message: 'coalescing probe handled'),
        );

        final processedMoves = plugin.events.whereType<PointerMoveInputEvent>();
        expect(processedMoves, hasLength(3));
        expect(processedMoves.map((event) => event.modifiers).toList(), const [
          KeyModifiers.none,
          KeyModifiers.none,
          KeyModifiers(shift: true),
        ]);
        expect(coordinator.getStats()['coalescedEvents'], 0);

        await coordinator.dispose();
      },
    );

    test(
      'does not coalesce pointer move events when pressure differs',
      () async {
        final context = _createPluginContext();
        final coordinator = PluginInputCoordinator(pluginContext: context);
        final firstEventGate = Completer<void>();
        final plugin = _CoalescingProbePlugin(
          pauseOnFirstEvent: firstEventGate,
        );

        await coordinator.registry.register(plugin);

        final firstFuture = coordinator.handleEvent(
          _pointerMove(x: 1, pressure: 0.2),
        );
        await plugin.firstEventStarted.future;

        final secondFuture = coordinator.handleEvent(
          _pointerMove(x: 2, pressure: 0.5),
        );
        final thirdFuture = coordinator.handleEvent(
          _pointerMove(x: 3, pressure: 0.8),
        );

        firstEventGate.complete();

        expect(
          await firstFuture,
          const PluginResult.handled(message: 'coalescing probe handled'),
        );
        expect(
          await secondFuture,
          const PluginResult.handled(message: 'coalescing probe handled'),
        );
        expect(
          await thirdFuture,
          const PluginResult.handled(message: 'coalescing probe handled'),
        );

        final processedMoves = plugin.events.whereType<PointerMoveInputEvent>();
        expect(processedMoves, hasLength(3));
        expect(processedMoves.map((event) => event.pressure).toList(), [
          0.2,
          0.5,
          0.8,
        ]);
        expect(coordinator.getStats()['coalescedEvents'], 0);

        await coordinator.dispose();
      },
    );

    test(
      'does not coalesce when one pointer move has unknown pressure',
      () async {
        final context = _createPluginContext();
        final coordinator = PluginInputCoordinator(pluginContext: context);
        final firstEventGate = Completer<void>();
        final plugin = _CoalescingProbePlugin(
          pauseOnFirstEvent: firstEventGate,
        );

        await coordinator.registry.register(plugin);

        final firstFuture = coordinator.handleEvent(_pointerMove(x: 1));
        await plugin.firstEventStarted.future;

        final secondFuture = coordinator.handleEvent(_pointerMove(x: 2));
        final thirdFuture = coordinator.handleEvent(
          _pointerMove(x: 3, pressure: 0.00005),
        );

        firstEventGate.complete();

        expect(
          await firstFuture,
          const PluginResult.handled(message: 'coalescing probe handled'),
        );
        expect(
          await secondFuture,
          const PluginResult.handled(message: 'coalescing probe handled'),
        );
        expect(
          await thirdFuture,
          const PluginResult.handled(message: 'coalescing probe handled'),
        );

        final processedMoves = plugin.events.whereType<PointerMoveInputEvent>();
        expect(processedMoves, hasLength(3));
        expect(processedMoves.map((event) => event.pressure).toList(), [
          0,
          0,
          0.00005,
        ]);
        expect(coordinator.getStats()['coalescedEvents'], 0);

        await coordinator.dispose();
      },
    );
  });

  group('PluginInputCoordinator error containment', () {
    test(
      'returns unhandled when processing throws and still handles later events',
      () async {
        var shouldThrowState = true;
        final stableState = DrawState();
        final drawContext = DrawContext.withDefaults();
        final context = PluginContext(
          stateProvider: () {
            if (shouldThrowState) {
              throw StateError('state unavailable');
            }
            return stableState;
          },
          contextProvider: () => drawContext,
          selectionConfigProvider: () => DrawConfig.defaultConfig.selection,
          dispatcher: (_) async {},
        );

        final coordinator = PluginInputCoordinator(pluginContext: context);
        await coordinator.registry.register(
          _TestPlugin(
            id: 'handler',
            priority: 0,
            onHandle: (_) async => const PluginResult.handled(message: 'ok'),
          ),
        );

        final firstResult = await coordinator.handleEvent(_pointerDown(x: 1));
        expect(
          firstResult,
          const PluginResult.unhandled(reason: 'Input processing failed'),
        );

        shouldThrowState = false;

        final secondResult = await coordinator.handleEvent(_pointerDown(x: 2));
        expect(secondResult, const PluginResult.handled(message: 'ok'));

        await coordinator.dispose();
      },
    );
  });
}

PluginContext _createPluginContext() {
  final state = DrawState();
  final drawContext = DrawContext.withDefaults();
  return PluginContext(
    stateProvider: () => state,
    contextProvider: () => drawContext,
    selectionConfigProvider: () => DrawConfig.defaultConfig.selection,
    dispatcher: (_) async {},
  );
}

PointerDownInputEvent _pointerDown({double x = 10, double y = 20}) =>
    PointerDownInputEvent(
      position: DrawPoint(x: x, y: y),
      modifiers: KeyModifiers.none,
    );

PointerMoveInputEvent _pointerMove({
  double x = 10,
  double y = 20,
  KeyModifiers modifiers = KeyModifiers.none,
  double pressure = 0.0,
}) => PointerMoveInputEvent(
  position: DrawPoint(x: x, y: y, pressure: pressure),
  modifiers: modifiers,
  pressure: pressure,
);

class _TestPlugin extends InputPluginBase {
  _TestPlugin({
    required super.id,
    required super.priority,
    required Future<PluginResult> Function(InputEvent event) onHandle,
    Future<bool> Function(InputEvent event)? onBefore,
    Future<void> Function(InputEvent event, PluginResult? result)? onAfter,
    bool Function(InputEvent event, DrawState state)? canHandle,
    super.supportedEventTypes = const {PointerDownInputEvent},
  }) : _onHandle = onHandle,
       _onBefore = onBefore,
       _onAfter = onAfter,
       _canHandle = canHandle,
       super(name: 'TestPlugin($id)');

  final Future<PluginResult> Function(InputEvent event) _onHandle;
  final Future<bool> Function(InputEvent event)? _onBefore;
  final Future<void> Function(InputEvent event, PluginResult? result)? _onAfter;
  final bool Function(InputEvent event, DrawState state)? _canHandle;

  @override
  bool canHandle(InputEvent event, DrawState state) =>
      _canHandle?.call(event, state) ?? true;

  @override
  Future<PluginResult> handleEvent(InputEvent event) => _onHandle(event);

  @override
  Future<bool> onBeforeEvent(InputEvent event) =>
      _onBefore?.call(event) ?? Future<bool>.value(false);

  @override
  Future<void> onAfterEvent(InputEvent event, PluginResult? result) =>
      _onAfter?.call(event, result) ?? Future<void>.value();
}

class _ProbeSequentialPlugin extends InputPluginBase {
  _ProbeSequentialPlugin()
    : super(
        id: 'probe',
        name: 'Probe',
        priority: 0,
        supportedEventTypes: const {PointerDownInputEvent},
      );

  final timeline = <String>[];
  var _activeHandlers = 0;
  var hadOverlap = false;

  @override
  bool canHandle(InputEvent event, DrawState state) => true;

  @override
  Future<PluginResult> handleEvent(InputEvent event) async {
    final pointerEvent = event as PointerDownInputEvent;
    final label = pointerEvent.position.x.toInt();
    timeline.add('start:$label');
    _activeHandlers += 1;
    if (_activeHandlers > 1) {
      hadOverlap = true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _activeHandlers -= 1;
    timeline.add('end:$label');
    return const PluginResult.handled(message: 'probe handled');
  }
}

class _LifecyclePlugin extends InputPluginBase {
  _LifecyclePlugin({
    required super.id,
    this.failOnLoad = false,
    this.failOnUnload = false,
  }) : super(
         name: 'Lifecycle($id)',
         priority: 0,
         supportedEventTypes: const {PointerDownInputEvent},
       );

  final bool failOnLoad;
  final bool failOnUnload;
  var loadCount = 0;
  var unloadCount = 0;

  @override
  Future<void> onLoad(PluginContext context) async {
    await super.onLoad(context);
    loadCount += 1;
    if (failOnLoad) {
      throw StateError('onLoad failed for $id');
    }
  }

  @override
  Future<void> onUnload() async {
    unloadCount += 1;
    if (failOnUnload) {
      throw StateError('onUnload failed for $id');
    }
    await super.onUnload();
  }

  @override
  bool canHandle(InputEvent event, DrawState state) => true;

  @override
  Future<PluginResult> handleEvent(InputEvent event) async =>
      const PluginResult.unhandled();
}

class _CoalescingProbePlugin extends InputPluginBase {
  _CoalescingProbePlugin({required this.pauseOnFirstEvent})
    : super(
        id: 'coalescing-probe',
        name: 'CoalescingProbe',
        priority: 0,
        supportedEventTypes: const {
          PointerMoveInputEvent,
          PointerDownInputEvent,
        },
      );

  final Completer<void> pauseOnFirstEvent;
  final firstEventStarted = Completer<void>();
  final events = <InputEvent>[];
  var _hasPaused = false;

  @override
  bool canHandle(InputEvent event, DrawState state) => true;

  @override
  Future<PluginResult> handleEvent(InputEvent event) async {
    events.add(event);
    if (!firstEventStarted.isCompleted) {
      firstEventStarted.complete();
    }
    if (!_hasPaused) {
      _hasPaused = true;
      await pauseOnFirstEvent.future;
    }
    return const PluginResult.handled(message: 'coalescing probe handled');
  }
}
