import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/grid_toolbar_adapter.dart';
import 'package:snow_draw/snap_toolbar_adapter.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/events/event_bus.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';
import 'package:snow_draw_core/draw/store/selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LaggingConfigStore store;

  setUp(() {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    store = _LaggingConfigStore(context: context);
  });

  tearDown(() async {
    await store.dispose();
  });

  test('grid adapter reads latest config when stream delivery lags', () async {
    final adapter = GridToolbarAdapter(store: store);
    addTearDown(adapter.dispose);

    await store.dispatch(
      UpdateConfig(
        store.config.copyWith(snap: store.config.snap.copyWith(enabled: true)),
      ),
    );

    await adapter.setGridSize(48);

    expect(store.config.grid.size, 48);
    expect(store.config.snap.enabled, isTrue);
  });

  test('snap adapter reads latest config when stream delivery lags', () async {
    final adapter = SnapToolbarAdapter(store: store);
    addTearDown(adapter.dispose);

    await store.dispatch(
      UpdateConfig(
        store.config.copyWith(grid: store.config.grid.copyWith(size: 44)),
      ),
    );

    await adapter.setEnabled(enabled: true);

    expect(store.config.snap.enabled, isTrue);
    expect(store.config.grid.size, 44);
  });

  test('style adapter reads latest config when stream delivery lags', () async {
    final adapter = StyleToolbarAdapter(store: store);
    addTearDown(adapter.dispose);

    await store.dispatch(
      UpdateConfig(
        store.config.copyWith(
          lineStyle: store.config.lineStyle.copyWith(strokeWidth: 17),
        ),
      ),
    );

    await adapter.applyStyleUpdate(
      color: const Color(0xFF008A44),
      toolType: ToolType.rectangle,
    );

    expect(store.config.rectangleStyle.color, const Color(0xFF008A44));
    expect(store.config.lineStyle.strokeWidth, 17);
  });
}

class _LaggingConfigStore implements DrawStore {
  _LaggingConfigStore({required this.context}) : _config = DrawConfig();

  @override
  final DrawContext context;

  DrawConfig _config;
  final _state = DrawState();
  final _pendingConfigEvents = Queue<DrawConfig>();
  final _configController = StreamController<DrawConfig>.broadcast();
  final _eventController = StreamController<DrawEvent>.broadcast();
  final _stateListeners = <StateChangeListener<DrawState>>[];

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
  Future<void> call(DrawAction action) => dispatch(action);

  @override
  Future<void> dispatch(DrawAction action) async {
    if (action is UpdateConfig) {
      _config = action.config;
      _pendingConfigEvents.add(_config);
      return;
    }
    throw UnsupportedError('Action not supported in test store: $action');
  }

  @override
  VoidCallback listen(
    StateChangeListener<DrawState> listener, {
    Set<DrawStateChange>? changeTypes,
  }) {
    _stateListeners.add(listener);
    return () => _stateListeners.remove(listener);
  }

  @override
  void unsubscribe(StateChangeListener<DrawState> listener) {
    _stateListeners.remove(listener);
  }

  @override
  VoidCallback select<T>(
    StateSelector<DrawState, T> selector,
    StateChangeListener<T> listener, {
    bool Function(T, T)? equals,
  }) {
    var previous = selector.select(_state);
    return listen((state) {
      final next = selector.select(state);
      final compare = equals ?? selector.equals;
      if (!compare(previous, next)) {
        previous = next;
        listener(next);
      }
    });
  }

  Future<void> flushConfigEvents() async {
    while (_pendingConfigEvents.isNotEmpty) {
      _configController.add(_pendingConfigEvents.removeFirst());
    }
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> dispose() async {
    await flushConfigEvents();
    await _configController.close();
    await _eventController.close();
  }
}
