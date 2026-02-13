import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store_interface.dart';
import 'package:snow_draw_core/draw/store/listener_registry.dart';

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
}
