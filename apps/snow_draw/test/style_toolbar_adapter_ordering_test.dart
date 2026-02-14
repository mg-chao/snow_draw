import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/events/event_bus.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';
import 'package:snow_draw_core/draw/store/selector.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'style updates keep invocation order when an earlier update finishes later',
    () async {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);
      final context = DrawContext.withDefaults(elementRegistry: registry);
      final store = _OutOfOrderStyleStore(context: context);
      final adapter = StyleToolbarAdapter(store: store);

      addTearDown(adapter.dispose);
      addTearDown(store.dispose);

      store.holdNextStyleUpdate();

      const firstColor = Color(0xFF00AA55);
      const secondColor = Color(0xFFAA0055);

      final first = adapter.applyStyleUpdate(
        color: firstColor,
        toolType: ToolType.rectangle,
      );
      await store.waitUntilHeldStyleUpdateReached();

      final second = adapter.applyStyleUpdate(
        color: secondColor,
        toolType: ToolType.rectangle,
      );

      store.releaseHeldStyleUpdate();
      await Future.wait([first, second]);
      await pumpEventQueue();

      final updatedData = store.state.domain.document
          .getElementById('r1')
          ?.data;
      expect(updatedData, isA<RectangleData>());
      expect((updatedData! as RectangleData).color, secondColor);
      expect(store.config.rectangleStyle.color, secondColor);
    },
  );
}

class _OutOfOrderStyleStore implements DrawStore {
  _OutOfOrderStyleStore({required this.context})
    : _config = DrawConfig(),
      _state = DrawState(
        domain: DomainState(
          document: DocumentState(elements: const [_rectangle]),
          selection: const SelectionState(selectedIds: {'r1'}),
        ),
      );

  static const _rectangle = ElementState(
    id: 'r1',
    rect: DrawRect(maxX: 120, maxY: 80),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(),
  );

  @override
  final DrawContext context;

  DrawConfig _config;
  DrawState _state;
  final _configController = StreamController<DrawConfig>.broadcast();
  final _eventController = StreamController<DrawEvent>.broadcast();
  final _stateListeners = <_StateListenerEntry>[];

  Completer<void>? _heldStyleUpdateGate;
  Completer<void>? _heldStyleUpdateReached;
  var _heldStyleUpdateConsumed = false;

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
  Future<void> dispatch(DrawAction action) async {
    if (action is UpdateConfig) {
      _config = action.config;
      _configController.add(_config);
      return;
    }
    if (action is UpdateElementsStyle) {
      await _applyElementsStyle(action);
      return;
    }
    throw UnsupportedError('Action not supported in test store: $action');
  }

  Future<void> _applyElementsStyle(UpdateElementsStyle action) async {
    if (_heldStyleUpdateGate != null && !_heldStyleUpdateConsumed) {
      _heldStyleUpdateConsumed = true;
      _heldStyleUpdateReached?.complete();
      await _heldStyleUpdateGate!.future;
    }

    final selectedIds = action.elementIds.toSet();
    final updatedElements = <ElementState>[];
    for (final element in _state.domain.document.elements) {
      if (!selectedIds.contains(element.id)) {
        updatedElements.add(element);
        continue;
      }
      final data = element.data;
      if (data is RectangleData) {
        updatedElements.add(
          element.copyWith(data: data.copyWith(color: action.color)),
        );
        continue;
      }
      updatedElements.add(element);
    }

    _state = _state.copyWith(
      domain: _state.domain.copyWith(
        document: _state.domain.document.copyWith(elements: updatedElements),
      ),
    );
    _notifyState(const {DrawStateChange.document});
  }

  @override
  VoidCallback listen(
    StateChangeListener<DrawState> listener, {
    Set<DrawStateChange>? changeTypes,
  }) {
    final entry = _StateListenerEntry(
      listener: listener,
      changeTypes: changeTypes,
    );
    _stateListeners.add(entry);
    return () => _stateListeners.remove(entry);
  }

  @override
  void unsubscribe(StateChangeListener<DrawState> listener) {
    _stateListeners.removeWhere((entry) => entry.listener == listener);
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

  void holdNextStyleUpdate() {
    _heldStyleUpdateGate = Completer<void>();
    _heldStyleUpdateReached = Completer<void>();
    _heldStyleUpdateConsumed = false;
  }

  Future<void> waitUntilHeldStyleUpdateReached() {
    final reached = _heldStyleUpdateReached;
    if (reached == null) {
      throw StateError('holdNextStyleUpdate must be called first.');
    }
    return reached.future;
  }

  void releaseHeldStyleUpdate() {
    _heldStyleUpdateGate?.complete();
    _heldStyleUpdateGate = null;
    _heldStyleUpdateReached = null;
    _heldStyleUpdateConsumed = false;
  }

  Future<void> dispose() async {
    releaseHeldStyleUpdate();
    await _configController.close();
    await _eventController.close();
  }

  void _notifyState(Set<DrawStateChange> changes) {
    final listeners = List<_StateListenerEntry>.from(_stateListeners);
    for (final entry in listeners) {
      final subscribed = entry.changeTypes;
      if (subscribed != null && subscribed.intersection(changes).isEmpty) {
        continue;
      }
      entry.listener(_state);
    }
  }
}

class _StateListenerEntry {
  _StateListenerEntry({required this.listener, this.changeTypes});

  final StateChangeListener<DrawState> listener;
  final Set<DrawStateChange>? changeTypes;
}
