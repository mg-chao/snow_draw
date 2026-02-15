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

  late _QueuedConfigStore store;

  setUp(() {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    store = _QueuedConfigStore(context: context);
  });

  tearDown(() async {
    await store.dispose();
  });

  test('concurrent grid and snap updates keep both changes', () async {
    final gridAdapter = GridToolbarAdapter(store: store);
    final snapAdapter = SnapToolbarAdapter(store: store);

    addTearDown(gridAdapter.dispose);
    addTearDown(snapAdapter.dispose);

    final setGridSize = gridAdapter.setGridSize(48);
    final enableSnap = snapAdapter.setEnabled(enabled: true);

    await Future.wait([setGridSize, enableSnap]);
    await pumpEventQueue();

    expect(store.config.grid.size, 48);
    expect(store.config.snap.enabled, isTrue);
  });

  test('concurrent style and snap updates keep both changes', () async {
    final styleAdapter = StyleToolbarAdapter(store: store);
    final snapAdapter = SnapToolbarAdapter(store: store);

    addTearDown(styleAdapter.dispose);
    addTearDown(snapAdapter.dispose);

    final updateStyle = styleAdapter.applyStyleUpdate(
      color: const Color(0xFF00AA55),
      toolType: ToolType.rectangle,
    );
    final enableSnap = snapAdapter.setEnabled(enabled: true);

    await Future.wait([updateStyle, enableSnap]);
    await pumpEventQueue();

    expect(store.config.rectangleStyle.color, const Color(0xFF00AA55));
    expect(store.config.snap.enabled, isTrue);
  });
}

class _QueuedConfigStore implements DrawStore {
  _QueuedConfigStore({required this.context}) : _config = DrawConfig();

  @override
  final DrawContext context;

  DrawConfig _config;
  final _state = DrawState();
  final _pendingUpdates = Queue<_QueuedUpdate>();
  final _configController = StreamController<DrawConfig>.broadcast();
  final _eventController = StreamController<DrawEvent>.broadcast();
  final _stateListeners = <StateChangeListener<DrawState>>[];
  Future<void>? _drainFuture;
  var _isProcessing = false;

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
  }) => eventStreamOf<T>().listen(
    handler,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Future<void> call(DrawAction action) => dispatch(action);

  @override
  Future<void> dispatch(DrawAction action) {
    if (action is! UpdateConfig) {
      throw UnsupportedError('Action not supported in test store: $action');
    }

    final completer = Completer<void>();
    _pendingUpdates.add(
      _QueuedUpdate(config: action.config, completer: completer),
    );
    if (!_isProcessing) {
      final drainFuture = _drainQueue();
      _drainFuture = drainFuture;
      unawaited(drainFuture);
    }
    return completer.future;
  }

  Future<void> _drainQueue() async {
    _isProcessing = true;
    try {
      while (_pendingUpdates.isNotEmpty) {
        final next = _pendingUpdates.removeFirst();
        await Future<void>.delayed(Duration.zero);
        _config = next.config;
        _configController.add(_config);
        next.completer.complete();
      }
    } finally {
      _isProcessing = false;
      _drainFuture = null;
    }
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
    await (_drainFuture ?? _drainQueue());
    await _configController.close();
    await _eventController.close();
  }
}

class _QueuedUpdate {
  const _QueuedUpdate({required this.config, required this.completer});

  final DrawConfig config;
  final Completer<void> completer;
}
