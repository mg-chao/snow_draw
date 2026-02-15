import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/listener_registry.dart';

void main() {
  late ListenerRegistry registry;

  DrawState nextState() => DrawState(
    domain: DomainState(
      document: DocumentState(),
      selection: const SelectionState(selectedIds: {'a'}, selectionVersion: 1),
    ),
  );

  group('onError callback', () {
    setUp(() {
      registry = ListenerRegistry();
    });

    test('onError is invoked when a listener throws', () {
      final errors = <Object>[];
      registry =
          ListenerRegistry(onError: (error, stackTrace) => errors.add(error))
            ..register((_) => throw StateError('boom'))
            ..notify(DrawState(), nextState());

      expect(errors, hasLength(1));
      expect(errors.first, isA<StateError>());
    });

    test('onError receives the stack trace', () {
      StackTrace? captured;
      registry =
          ListenerRegistry(
              onError: (error, stackTrace) => captured = stackTrace,
            )
            ..register((_) => throw StateError('boom'))
            ..notify(DrawState(), nextState());

      expect(captured, isNotNull);
    });

    test('subsequent listeners still fire after an error '
        'even with onError', () {
      final states = <DrawState>[];
      registry = ListenerRegistry(onError: (_, _) {})
        ..register((_) => throw Exception('first'))
        ..register(states.add);

      final next = nextState();
      registry.notify(DrawState(), next);

      expect(states, hasLength(1));
      expect(states.first, next);
    });

    test('without onError, errors are still swallowed', () {
      final states = <DrawState>[];
      registry = ListenerRegistry()
        ..register((_) => throw Exception('boom'))
        ..register(states.add);

      final next = nextState();
      registry.notify(DrawState(), next);

      expect(states, hasLength(1));
    });
  });
}
