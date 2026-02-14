import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';
import 'package:snow_draw_core/draw/store/listener_registry.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  late ListenerRegistry registry;

  setUp(() {
    registry = ListenerRegistry();
  });

  test('register adds a listener', () {
    registry.register((_) {});
    expect(registry.count, 1);
  });

  test('unregister removes a listener', () {
    void listener(DrawState _) {}
    registry.register(listener);
    expect(registry.count, 1);
    registry.unregister(listener);
    expect(registry.count, 0);
  });

  test('returned callback unregisters', () {
    final unsub = registry.register((_) {});
    expect(registry.count, 1);
    unsub();
    expect(registry.count, 0);
  });

  test('notify calls listener when state changes', () {
    final states = <DrawState>[];
    registry.register(states.add);

    final prev = DrawState();
    final next = DrawState(
      domain: DomainState(
        document: DocumentState(),
        selection: const SelectionState(
          selectedIds: {'a'},
          selectionVersion: 1,
        ),
      ),
    );

    registry.notify(prev, next);
    expect(states, hasLength(1));
    expect(states.first, next);
  });

  test('notify skips listener when no relevant changes', () {
    final states = <DrawState>[];
    registry.register(states.add, changeTypes: {DrawStateChange.view});

    final prev = DrawState();
    final next = DrawState(
      domain: DomainState(
        document: DocumentState(),
        selection: const SelectionState(
          selectedIds: {'a'},
          selectionVersion: 1,
        ),
      ),
    );

    registry.notify(prev, next);
    expect(states, isEmpty);
  });

  test('notify with matching changeType calls listener', () {
    final states = <DrawState>[];
    registry.register(states.add, changeTypes: {DrawStateChange.selection});

    final prev = DrawState();
    final next = DrawState(
      domain: DomainState(
        document: DocumentState(),
        selection: const SelectionState(
          selectedIds: {'a'},
          selectionVersion: 1,
        ),
      ),
    );

    registry.notify(prev, next);
    expect(states, hasLength(1));
  });

  test('clear removes all listeners', () {
    registry
      ..register((_) {})
      ..register((_) {});
    expect(registry.count, 2);
    registry.clear();
    expect(registry.count, 0);
  });

  test('throwing listener does not prevent other listeners from '
      'being notified', () {
    final states = <DrawState>[];

    registry
      ..register((_) => throw Exception('boom'))
      ..register(states.add);

    final prev = DrawState();
    final next = DrawState(
      domain: DomainState(
        document: DocumentState(),
        selection: const SelectionState(
          selectedIds: {'a'},
          selectionVersion: 1,
        ),
      ),
    );

    registry.notify(prev, next);
    expect(
      states,
      hasLength(1),
      reason:
          'Second listener should still be called '
          'even when the first throws',
    );
  });

  test('listener unregistered before its turn is skipped in '
      'unfiltered notify path', () {
    var calls = 0;

    late StateChangeListener<DrawState> removableListener;
    removableListener = (_) => calls += 1;

    registry
      ..register((_) => registry.unregister(removableListener))
      ..register(removableListener);

    final previous = DrawState();
    final next = DrawState(
      domain: DomainState(
        document: DocumentState(),
        selection: const SelectionState(
          selectedIds: {'a'},
          selectionVersion: 1,
        ),
      ),
    );

    registry.notify(previous, next);
    expect(calls, 0);
  });

  test('listener unregistered before its turn is skipped in filtered '
      'notify path', () {
    var calls = 0;

    late StateChangeListener<DrawState> removableListener;
    removableListener = (_) => calls += 1;

    registry
      ..register((_) => registry.unregister(removableListener))
      ..register(removableListener)
      ..register((_) {}, changeTypes: {DrawStateChange.selection});

    final previous = DrawState();
    final next = DrawState(
      domain: DomainState(
        document: DocumentState(),
        selection: const SelectionState(
          selectedIds: {'a'},
          selectionVersion: 1,
        ),
      ),
    );

    registry.notify(previous, next);
    expect(calls, 0);
  });

  test(
    'listener filter update during notify is honored for later listeners',
    () {
      var targetCalls = 0;
      void target(DrawState _) => targetCalls += 1;

      var filterUpdated = false;
      registry
        ..register((_) {
          if (filterUpdated) {
            return;
          }
          filterUpdated = true;
          registry.register(target, changeTypes: {DrawStateChange.view});
        })
        ..register(target, changeTypes: {DrawStateChange.selection});

      final previous = DrawState();
      final selectionChanged = DrawState(
        domain: DomainState(
          document: DocumentState(),
          selection: const SelectionState(
            selectedIds: {'a'},
            selectionVersion: 1,
          ),
        ),
      );

      registry.notify(previous, selectionChanged);
      expect(targetCalls, 0);

      final viewChanged = DrawState(
        application: previous.application.copyWith(
          view: previous.application.view.copyWith(
            camera: previous.application.view.camera.translated(10, 0),
          ),
        ),
      );
      registry.notify(previous, viewChanged);
      expect(targetCalls, 1);
    },
  );

  test('listener re-registered during notify is deferred until next cycle', () {
    var targetCalls = 0;
    void target(DrawState _) => targetCalls += 1;

    var reRegistered = false;
    registry
      ..register((_) {
        if (reRegistered) {
          return;
        }
        reRegistered = true;
        registry
          ..unregister(target)
          ..register(target);
      })
      ..register(target);

    final previous = DrawState();
    final next = DrawState(
      domain: DomainState(
        document: DocumentState(),
        selection: const SelectionState(
          selectedIds: {'a'},
          selectionVersion: 1,
        ),
      ),
    );

    registry.notify(previous, next);
    expect(targetCalls, 0);

    registry.notify(previous, next);
    expect(targetCalls, 1);
  });

  test('duplicate register updates changeTypes', () {
    final states = <DrawState>[];
    void listener(DrawState s) => states.add(s);

    registry
      ..register(listener, changeTypes: {DrawStateChange.view})
      ..register(listener, changeTypes: {DrawStateChange.selection});

    expect(registry.count, 1);

    final prev = DrawState();
    final next = DrawState(
      domain: DomainState(
        document: DocumentState(),
        selection: const SelectionState(
          selectedIds: {'a'},
          selectionVersion: 1,
        ),
      ),
    );

    registry.notify(prev, next);
    expect(states, hasLength(1));
  });

  test(
    'duplicate register can switch a listener from filtered to unfiltered',
    () {
      var calls = 0;
      void listener(DrawState _) => calls += 1;

      registry
        ..register(listener, changeTypes: {DrawStateChange.selection})
        ..register(listener);

      final previous = DrawState();
      final moved = DrawState(
        application: previous.application.copyWith(
          view: previous.application.view.copyWith(
            camera: previous.application.view.camera.translated(12, 0),
          ),
        ),
      );

      registry.notify(previous, moved);
      expect(calls, 1);
    },
  );

  test(
    'mixed filtered and unfiltered listeners preserve notification rules',
    () {
      final filteredStates = <DrawState>[];
      final unfilteredStates = <DrawState>[];

      registry
        ..register(filteredStates.add, changeTypes: {DrawStateChange.selection})
        ..register(unfilteredStates.add);

      final previous = DrawState();
      final moved = DrawState(
        application: previous.application.copyWith(
          view: previous.application.view.copyWith(
            camera: previous.application.view.camera.translated(10, 0),
          ),
        ),
      );

      registry.notify(previous, moved);

      expect(filteredStates, isEmpty);
      expect(unfilteredStates, hasLength(1));
    },
  );

  test('empty changeTypes behaves as an unfiltered listener', () {
    final states = <DrawState>[];
    registry.register(states.add, changeTypes: <DrawStateChange>{});

    final prev = DrawState();
    final next = DrawState(
      domain: DomainState(
        document: DocumentState(),
        selection: const SelectionState(
          selectedIds: {'a'},
          selectionVersion: 1,
        ),
      ),
    );

    registry.notify(prev, next);
    expect(states, hasLength(1));
  });

  test('listener keeps a stable changeTypes snapshot at registration', () {
    final states = <DrawState>[];
    final mutableChangeTypes = <DrawStateChange>{DrawStateChange.selection};
    registry.register(states.add, changeTypes: mutableChangeTypes);

    mutableChangeTypes
      ..clear()
      ..add(DrawStateChange.view);

    final prev = DrawState();
    final next = DrawState(
      domain: DomainState(
        document: DocumentState(),
        selection: const SelectionState(
          selectedIds: {'a'},
          selectionVersion: 1,
        ),
      ),
    );

    registry.notify(prev, next);
    expect(states, hasLength(1));
  });

  test(
    'unfiltered notifications short-circuit once a tracked change is found',
    () {
      final previousSelectedIds = _CountingSet<String>({'a'});
      final nextSelectedIds = _CountingSet<String>({'a'});
      final states = <DrawState>[];

      registry.register(states.add);

      final previous = DrawState(
        domain: DomainState(
          document: DocumentState(),
          selection: SelectionState(selectedIds: previousSelectedIds),
        ),
      );
      final next = DrawState(
        domain: DomainState(
          document: DocumentState(elementsVersion: 1),
          selection: SelectionState(selectedIds: nextSelectedIds),
        ),
      );

      registry.notify(previous, next);

      expect(states, hasLength(1));
      expect(previousSelectedIds.iterationCount, 0);
      expect(nextSelectedIds.containsCount, 0);
    },
  );

  test(
    'selection listeners still detect changed ids when versions are stale',
    () {
      final states = <DrawState>[];
      registry.register(states.add, changeTypes: {DrawStateChange.selection});

      final previous = DrawState(
        domain: DomainState(
          document: DocumentState(),
          selection: const SelectionState(
            selectedIds: {'a'},
            selectionVersion: 7,
          ),
        ),
      );
      final next = DrawState(
        domain: DomainState(
          document: DocumentState(),
          selection: const SelectionState(
            selectedIds: {'b'},
            selectionVersion: 7,
          ),
        ),
      );

      registry.notify(previous, next);
      expect(states, hasLength(1));
    },
  );

  test(
    'document listeners still detect changed elements when versions are stale',
    () {
      final states = <DrawState>[];
      registry.register(states.add, changeTypes: {DrawStateChange.document});

      final previous = DrawState(
        domain: DomainState(
          document: DocumentState(
            elements: const [
              ElementState(
                id: 'a',
                rect: DrawRect(maxX: 10, maxY: 10),
                rotation: 0,
                opacity: 1,
                zIndex: 0,
                data: RectangleData(),
              ),
            ],
            elementsVersion: 5,
          ),
        ),
      );
      final next = DrawState(
        domain: DomainState(
          document: DocumentState(
            elements: const [
              ElementState(
                id: 'b',
                rect: DrawRect(maxX: 10, maxY: 10),
                rotation: 0,
                opacity: 1,
                zIndex: 0,
                data: RectangleData(),
              ),
            ],
            elementsVersion: 5,
          ),
        ),
      );

      registry.notify(previous, next);
      expect(states, hasLength(1));
    },
  );
}

class _CountingSet<E> extends SetBase<E> {
  _CountingSet(Iterable<E> values) : _delegate = values.toSet();

  final Set<E> _delegate;
  var iterationCount = 0;
  var containsCount = 0;

  @override
  bool add(E value) => _delegate.add(value);

  @override
  bool contains(Object? element) {
    containsCount += 1;
    return _delegate.contains(element);
  }

  @override
  E? lookup(Object? element) => _delegate.lookup(element);

  @override
  bool remove(Object? value) => _delegate.remove(value);

  @override
  Iterator<E> get iterator {
    iterationCount += 1;
    return _delegate.iterator;
  }

  @override
  int get length => _delegate.length;

  @override
  Set<E> toSet() => _delegate.toSet();
}
