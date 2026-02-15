import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
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

  late _LaggingStateStore store;
  late StyleToolbarAdapter adapter;

  setUp(() {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    store = _LaggingStateStore(
      context: context,
      initialState: _buildInitialState(),
    );
    adapter = StyleToolbarAdapter(store: store);
  });

  tearDown(() async {
    adapter.dispose();
    await store.dispose();
  });

  test(
    'applyStyleUpdate uses latest store selection when state delivery lags',
    () async {
      store.setSelectionSilently(const {'r2'});

      await adapter.applyStyleUpdate(
        color: const Color(0xFF0088FF),
        toolType: ToolType.rectangle,
      );

      final updateAction = store.singleActionOfType<UpdateElementsStyle>();
      expect(updateAction.elementIds, const ['r2']);
    },
  );

  test(
    'copySelection uses latest store selection when state delivery lags',
    () async {
      store.setSelectionSilently(const {'r2'});

      await adapter.copySelection();

      final duplicateAction = store.singleActionOfType<DuplicateElements>();
      expect(duplicateAction.elementIds, const ['r2']);
    },
  );

  test(
    'deleteSelection uses latest store selection when state delivery lags',
    () async {
      store.setSelectionSilently(const {'r2'});

      await adapter.deleteSelection();

      final deleteAction = store.singleActionOfType<DeleteElements>();
      expect(deleteAction.elementIds, const ['r2']);
    },
  );

  test(
    'changeZOrder uses latest store selection when state delivery lags',
    () async {
      store.setSelectionSilently(const {'r2'});

      await adapter.changeZOrder(ZIndexOperation.bringToFront);

      final zOrderAction = store.singleActionOfType<ChangeElementsZIndex>();
      expect(zOrderAction.elementIds, const ['r2']);
    },
  );

  test('createSerialNumberTextElements uses latest store selection'
      ' when state delivery lags', () async {
    store.setSelectionSilently(const {'s1'});

    await adapter.createSerialNumberTextElements();

    final createTextAction = store
        .singleActionOfType<CreateSerialNumberTextElements>();
    expect(createTextAction.elementIds, const ['s1']);
  });
}

DrawState _buildInitialState() {
  const rectangleOne = ElementState(
    id: 'r1',
    rect: DrawRect(maxX: 80, maxY: 60),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(),
  );
  const rectangleTwo = ElementState(
    id: 'r2',
    rect: DrawRect(minX: 100, maxX: 180, maxY: 60),
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: RectangleData(),
  );
  const serialNumber = ElementState(
    id: 's1',
    rect: DrawRect(minX: 200, maxX: 260, maxY: 60),
    rotation: 0,
    opacity: 1,
    zIndex: 2,
    data: SerialNumberData(),
  );

  return DrawState(
    domain: DomainState(
      document: DocumentState(
        elements: const [rectangleOne, rectangleTwo, serialNumber],
      ),
      selection: const SelectionState(selectedIds: {'r1'}),
    ),
  );
}

class _LaggingStateStore implements DrawStore {
  _LaggingStateStore({required this.context, required DrawState initialState})
    : _state = initialState,
      _config = DrawConfig();

  @override
  final DrawContext context;

  DrawState _state;
  DrawConfig _config;
  final actions = <DrawAction>[];
  final _configController = StreamController<DrawConfig>.broadcast();
  final _eventController = StreamController<DrawEvent>.broadcast();
  final _listeners = <_StateListenerEntry>[];

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
    actions.add(action);
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
    final entry = _StateListenerEntry(
      listener: listener,
      changeTypes: changeTypes,
    );
    _listeners.add(entry);
    return () => _listeners.remove(entry);
  }

  @override
  void unsubscribe(StateChangeListener<DrawState> listener) {
    _listeners.removeWhere((entry) => entry.listener == listener);
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

  void setSelectionSilently(Set<String> selectedIds) {
    _state = _state.copyWith(
      domain: _state.domain.copyWith(
        selection: _state.domain.selection.copyWith(selectedIds: selectedIds),
      ),
    );
  }

  T singleActionOfType<T extends DrawAction>() {
    final matches = actions.whereType<T>().toList(growable: false);
    expect(matches, hasLength(1));
    return matches.single;
  }

  Future<void> dispose() async {
    await _configController.close();
    await _eventController.close();
  }
}

class _StateListenerEntry {
  _StateListenerEntry({required this.listener, this.changeTypes});

  final StateChangeListener<DrawState> listener;
  final Set<DrawStateChange>? changeTypes;
}
