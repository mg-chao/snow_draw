import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/events/event_bus.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';
import 'package:snow_draw_core/draw/store/selector.dart';
import 'package:snow_draw_core/ui/canvas/plugin_draw_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PluginDrawCanvas state subscription', () {
    testWidgets(
      'subscribes through DrawStore.listen with full state change scope',
      (tester) async {
        final store = _RecordingDrawStore(context: _createContext());
        addTearDown(store.dispose);

        await tester.pumpWidget(_buildHarness(store: store));
        await tester.pump();

        expect(store.listenCallCount, 1);
        expect(
          store.lastListenChangeTypes,
          equals({
            DrawStateChange.document,
            DrawStateChange.selection,
            DrawStateChange.view,
            DrawStateChange.interaction,
          }),
        );
        expect(store.onEventCallCount, 0);
      },
    );

    testWidgets('moves state subscription to a replaced store', (tester) async {
      final firstStore = _RecordingDrawStore(context: _createContext());
      final secondStore = _RecordingDrawStore(context: _createContext());
      addTearDown(firstStore.dispose);
      addTearDown(secondStore.dispose);

      await tester.pumpWidget(_buildHarness(store: firstStore));
      await tester.pump();

      expect(firstStore.listenCallCount, 1);
      expect(firstStore.activeListenerCount, 1);

      await tester.pumpWidget(_buildHarness(store: secondStore));
      await tester.pump();

      expect(firstStore.unsubscribeCallCount, 1);
      expect(firstStore.activeListenerCount, 0);
      expect(secondStore.listenCallCount, 1);
      expect(secondStore.activeListenerCount, 1);
    });

    testWidgets('cleans up state subscription on dispose', (tester) async {
      final store = _RecordingDrawStore(context: _createContext());
      addTearDown(store.dispose);

      await tester.pumpWidget(_buildHarness(store: store));
      await tester.pump();

      expect(store.listenCallCount, 1);
      expect(store.activeListenerCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(store.unsubscribeCallCount, 1);
      expect(store.activeListenerCount, 0);
    });
  });
}

Widget _buildHarness({required DrawStore store}) => MaterialApp(
  home: Scaffold(
    body: PluginDrawCanvas(
      key: const ValueKey<String>('plugin-draw-canvas'),
      size: const Size(320, 240),
      store: store,
    ),
  ),
);

DrawContext _createContext() {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  return DrawContext.withDefaults(elementRegistry: registry);
}

class _RecordingDrawStore implements DrawStore {
  _RecordingDrawStore({required this.context});

  @override
  final DrawContext context;

  final _state = DrawState();
  var _config = DrawConfig();
  final _configController = StreamController<DrawConfig>.broadcast();
  final _eventController = StreamController<DrawEvent>.broadcast();
  final _listeners = <_StateListenerEntry>[];

  var listenCallCount = 0;
  var unsubscribeCallCount = 0;
  var onEventCallCount = 0;
  Set<DrawStateChange>? lastListenChangeTypes;

  int get activeListenerCount => _listeners.length;

  @override
  DrawState get state => _state;

  @override
  DrawState get currentState => _state;

  @override
  DrawConfig get config => _config;

  @override
  Stream<DrawConfig> get configStream => _configController.stream;

  @override
  Stream<DrawEvent> get eventStream => _eventController.stream;

  @override
  Stream<T> eventStreamOf<T extends DrawEvent>() =>
      eventStream.where((event) => event is T).cast<T>();

  @override
  StreamSubscription<T> onEvent<T extends DrawEvent>(
    void Function(T event) handler, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    onEventCallCount += 1;
    return eventStreamOf<T>().listen(
      handler,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<void> call(DrawAction action) => dispatch(action);

  @override
  Future<void> dispatch(DrawAction action) async {
    if (action is UpdateConfig) {
      _config = action.config;
      _configController.add(_config);
    }
  }

  @override
  VoidCallback listen(
    StateChangeListener<DrawState> listener, {
    Set<DrawStateChange>? changeTypes,
  }) {
    listenCallCount += 1;
    lastListenChangeTypes = changeTypes;
    final entry = _StateListenerEntry(
      listener: listener,
      changeTypes: changeTypes,
    );
    _listeners.add(entry);
    return () {
      if (_listeners.remove(entry)) {
        unsubscribeCallCount += 1;
      }
    };
  }

  @override
  void unsubscribe(StateChangeListener<DrawState> listener) {
    final before = _listeners.length;
    _listeners.removeWhere((entry) => entry.listener == listener);
    final removedCount = before - _listeners.length;
    if (removedCount > 0) {
      unsubscribeCallCount += removedCount;
    }
  }

  @override
  VoidCallback select<T>(
    StateSelector<DrawState, T> selector,
    StateChangeListener<T> listener, {
    bool Function(T, T)? equals,
    Set<DrawStateChange>? changeTypes,
  }) {
    var previous = selector.select(_state);
    return listen((state) {
      final next = selector.select(state);
      final compare = equals ?? selector.equals;
      if (!compare(previous, next)) {
        previous = next;
        listener(next);
      }
    }, changeTypes: changeTypes);
  }

  Future<void> dispose() async {
    _listeners.clear();
    await _configController.close();
    await _eventController.close();
  }
}

class _StateListenerEntry {
  _StateListenerEntry({required this.listener, this.changeTypes});

  final StateChangeListener<DrawState> listener;
  final Set<DrawStateChange>? changeTypes;
}
