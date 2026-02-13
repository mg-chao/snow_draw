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

class _TestPlugin extends InputPluginBase {
  _TestPlugin({
    required super.id,
    required super.priority,
    required Future<PluginResult> Function(InputEvent event) onHandle,
    Future<bool> Function(InputEvent event)? onBefore,
    Future<void> Function(InputEvent event, PluginResult? result)? onAfter,
    bool Function(InputEvent event, DrawState state)? canHandle,
  }) : _onHandle = onHandle,
       _onBefore = onBefore,
       _onAfter = onAfter,
       _canHandle = canHandle,
       super(
         name: 'TestPlugin($id)',
         supportedEventTypes: const {PointerDownInputEvent},
       );

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
