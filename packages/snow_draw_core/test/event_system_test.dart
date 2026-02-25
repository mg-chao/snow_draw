import 'dart:async';

import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/events/error_events.dart';
import 'package:snow_draw_core/draw/events/event_bus.dart';
import 'package:snow_draw_core/draw/events/event_payload_freezer.dart';
import 'package:snow_draw_core/draw/events/state_events.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('EventBus', () {
    test('dispatches typed subscriptions in emission order', () async {
      final bus = EventBus();
      final received = <String>[];

      final docSub = bus.on<DocumentChangedEvent>((event) {
        received.add('doc:${event.elementsVersion}');
      });
      final validationSub = bus.on<ValidationFailedEvent>((event) {
        received.add('validation:${event.reason}');
      });

      bus
        ..emit(const DocumentChangedEvent(elementsVersion: 1, elementCount: 2))
        ..emit(ValidationFailedEvent(action: 'CreateElement', reason: 'bad'))
        ..emit(
          const HistoryAvailabilityChangedEvent(canUndo: true, canRedo: false),
        );

      await _flushEventQueue();

      expect(received, equals(['doc:1', 'validation:bad']));

      await docSub.cancel();
      await validationSub.cancel();
      await bus.dispose();
    });

    test('ignores emit after dispose', () async {
      final bus = EventBus();
      await bus.dispose();

      expect(
        () => bus.emit(
          const DocumentChangedEvent(elementsVersion: 1, elementCount: 1),
        ),
        returnsNormally,
      );
    });

    test('tracks listener compatibility by event type', () async {
      final bus = EventBus();

      final stateSub = bus.on<StateChangeEvent>((_) {});

      expect(bus.hasListenersFor<DocumentChangedEvent>(), isTrue);
      expect(bus.hasListenersFor<HistoryAvailabilityChangedEvent>(), isTrue);
      expect(bus.hasListenersFor<ValidationFailedEvent>(), isFalse);

      await stateSub.cancel();

      expect(bus.hasListenersFor<DocumentChangedEvent>(), isFalse);

      final rawSub = bus.stream.listen((_) {});

      expect(bus.hasListenersFor<ValidationFailedEvent>(), isTrue);

      await rawSub.cancel();
      await bus.dispose();
    });

    test('emitLazy only builds events for compatible listeners', () async {
      final bus = EventBus();
      final received = <DocumentChangedEvent>[];
      final docSub = bus.on<DocumentChangedEvent>(received.add);

      var builtValidation = false;
      final validationDispatched = bus.emitLazy<ValidationFailedEvent>(() {
        builtValidation = true;
        return ValidationFailedEvent(
          action: 'CreateElement',
          reason: 'invalid',
        );
      });
      expect(validationDispatched, isFalse);
      expect(builtValidation, isFalse);

      var builtDocument = false;
      final documentDispatched = bus.emitLazy<DocumentChangedEvent>(() {
        builtDocument = true;
        return const DocumentChangedEvent(elementsVersion: 3, elementCount: 2);
      });
      expect(documentDispatched, isTrue);
      expect(builtDocument, isTrue);

      await _flushEventQueue();

      expect(received, hasLength(1));
      expect(received.single.elementsVersion, equals(3));

      await docSub.cancel();
      await bus.dispose();
    });

    test(
      'emitLazy supports DrawEvent-typed factories for concrete listeners',
      () async {
        final bus = EventBus();
        final received = <ValidationFailedEvent>[];
        final validationSub = bus.on<ValidationFailedEvent>(received.add);

        DrawEvent createEvent() =>
            ValidationFailedEvent(action: 'CreateElement', reason: 'invalid');

        final dispatched = bus.emitLazy<DrawEvent>(createEvent);
        await _flushEventQueue();

        expect(dispatched, isTrue);
        expect(received, hasLength(1));
        expect(received.single.reason, equals('invalid'));

        await validationSub.cancel();
        await bus.dispose();
      },
    );

    test(
      'emitLazy supports supertype factories for subtype listeners',
      () async {
        final bus = EventBus();
        final received = <DocumentChangedEvent>[];
        final documentSub = bus.on<DocumentChangedEvent>(received.add);

        StateChangeEvent createEvent() =>
            const DocumentChangedEvent(elementsVersion: 4, elementCount: 2);

        final dispatched = bus.emitLazy<StateChangeEvent>(createEvent);
        await _flushEventQueue();

        expect(dispatched, isTrue);
        expect(received, hasLength(1));
        expect(received.single.elementsVersion, equals(4));

        await documentSub.cancel();
        await bus.dispose();
      },
    );

    test('streamOf remains reusable after listener churn', () async {
      final bus = EventBus();
      final stream = bus.streamOf<DocumentChangedEvent>();
      final received = <int>[];

      final firstSub = stream.listen(
        (event) => received.add(event.elementsVersion),
      );
      bus.emit(const DocumentChangedEvent(elementsVersion: 1, elementCount: 1));
      await _flushEventQueue();
      await firstSub.cancel();

      final secondSub = stream.listen(
        (event) => received.add(event.elementsVersion),
      );
      bus.emit(const DocumentChangedEvent(elementsVersion: 2, elementCount: 1));
      await _flushEventQueue();

      expect(received, equals([1, 2]));

      await secondSub.cancel();
      await bus.dispose();
    });

    test('streamOf remains broadcast after dispose', () async {
      final bus = EventBus();
      await bus.dispose();

      final stream = bus.streamOf<DocumentChangedEvent>();
      expect(stream.isBroadcast, isTrue);

      await _expectDoneOnListen(stream);
      await _expectDoneOnListen(stream);
    });
  });

  group('Event payload immutability', () {
    test('ValidationFailedEvent keeps an immutable snapshot of details', () {
      final details = <String, dynamic>{'traceId': 't1'};
      final event = ValidationFailedEvent(
        action: 'UpdateElementsStyle',
        reason: 'invalid',
        details: details,
      );

      details['traceId'] = 'mutated';

      expect(event.details['traceId'], equals('t1'));
      expect(
        () => event.details['next'] = 'x',
        throwsA(isA<UnsupportedError>()),
      );
    });

    test(
      'SelectionChangedEvent keeps an immutable snapshot of selectedIds',
      () {
        final selectedIds = <String>{'a'};
        final event = SelectionChangedEvent(
          selectedIds: selectedIds,
          selectionVersion: 1,
        );

        selectedIds.add('b');

        expect(event.selectedIds, equals({'a'}));
        expect(
          () => event.selectedIds.add('c'),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );

    test('ValidationFailedEvent deeply freezes nested details', () {
      final nested = <String, dynamic>{
        'path': <String>['root'],
        'meta': <String, dynamic>{'attempt': 1},
        'flags': <String>{'alpha'},
      };
      final event = ValidationFailedEvent(
        action: 'UpdateElementsStyle',
        reason: 'invalid',
        details: {'payload': nested},
      );

      (nested['path'] as List<String>).add('mutated');
      (nested['meta'] as Map<String, dynamic>)['attempt'] = 2;
      (nested['flags'] as Set<String>).add('beta');

      final payload = event.details['payload'] as Map<Object?, Object?>;
      final frozenPath = payload['path']! as List<Object?>;
      final frozenMeta = payload['meta']! as Map<Object?, Object?>;
      final frozenFlags = payload['flags']! as Set<Object?>;

      expect(frozenPath, equals(['root']));
      expect(frozenMeta['attempt'], equals(1));
      expect(frozenFlags, equals({'alpha'}));

      expect(() => frozenPath.add('x'), throwsA(isA<UnsupportedError>()));
      expect(() => frozenMeta['next'] = true, throwsA(isA<UnsupportedError>()));
      expect(() => frozenFlags.add('x'), throwsA(isA<UnsupportedError>()));
    });

    test('ValidationFailedEvent rejects cyclic details payloads', () {
      final details = <String, dynamic>{};
      details['self'] = details;

      expect(
        () => ValidationFailedEvent(
          action: 'UpdateElementsStyle',
          reason: 'invalid',
          details: details,
        ),
        throwsArgumentError,
      );
    });

    test('freezeEventPayloadMap preserves shared nested references', () {
      final sharedList = <String>['alpha'];
      final sharedMap = <String, dynamic>{'items': sharedList};
      final payload = <String, dynamic>{
        'first': sharedMap,
        'second': sharedMap,
      };

      final frozen = freezeEventPayloadMap(payload);
      final first = frozen['first'] as Map<Object?, Object?>;
      final second = frozen['second'] as Map<Object?, Object?>;
      final firstItems = first['items']! as List<Object?>;
      final secondItems = second['items']! as List<Object?>;

      expect(identical(first, second), isTrue);
      expect(identical(firstItems, secondItems), isTrue);
      expect(firstItems, equals(['alpha']));
      expect(() => firstItems.add('beta'), throwsUnsupportedError);
    });
  });

  group('History availability events', () {
    test('restoreHistory emits history availability '
        'and keeps baseline synchronized', () async {
      final source = _createStore(initialState: _stateWithOneSelectedElement());
      addTearDown(source.dispose);

      await source.dispatch(
        UpdateElementsStyle(elementIds: ['target'], opacity: 0.4),
      );
      expect(source.canUndo, isTrue);
      expect(source.canRedo, isFalse);
      final snapshot = source.exportHistory();

      final target = _createStore();
      addTearDown(target.dispose);

      final events = <HistoryAvailabilityChangedEvent>[];
      final subscription = _listenToHistoryAvailability(target, events.add);
      addTearDown(subscription.cancel);

      target.restoreHistory(snapshot);
      await _flushEventQueue();

      expect(target.canUndo, isTrue);
      expect(target.canRedo, isFalse);
      expect(events, hasLength(1));
      expect(events.single.canUndo, isTrue);
      expect(events.single.canRedo, isFalse);

      events.clear();
      await target.dispatch(const MoveCamera(dx: 4, dy: 0));
      await _flushEventQueue();

      expect(events, isEmpty);
    });
  });

  group('DrawStore typed event subscriptions', () {
    test('store exposes typed event streams and subscriptions', () async {
      final store = _createStore(initialState: _stateWithOneSelectedElement());
      addTearDown(store.dispose);

      final documentEvents = <DocumentChangedEvent>[];
      final historyEvents = <HistoryAvailabilityChangedEvent>[];
      final documentSub = store.onEvent<DocumentChangedEvent>(
        documentEvents.add,
      );
      final historySub = store
          .eventStreamOf<HistoryAvailabilityChangedEvent>()
          .listen(historyEvents.add);

      addTearDown(() async {
        await documentSub.cancel();
        await historySub.cancel();
      });

      await store.dispatch(
        UpdateElementsStyle(elementIds: ['target'], opacity: 0.4),
      );
      await _flushEventQueue();

      expect(documentEvents, hasLength(1));
      expect(historyEvents, hasLength(1));
    });
  });
}

Future<void> _flushEventQueue() => Future<void>.delayed(Duration.zero);

Future<void> _expectDoneOnListen<T>(Stream<T> stream) async {
  final subscription = stream.listen((_) {});
  try {
    await subscription.asFuture<void>();
  } finally {
    await subscription.cancel();
  }
}

StreamSubscription<HistoryAvailabilityChangedEvent>
_listenToHistoryAvailability(
  DefaultDrawStore store,
  void Function(HistoryAvailabilityChangedEvent event) onEvent,
) => store.eventStream
    .where((event) => event is HistoryAvailabilityChangedEvent)
    .cast<HistoryAvailabilityChangedEvent>()
    .listen(onEvent);

DefaultDrawStore _createStore({DrawState? initialState}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(context: context, initialState: initialState);
}

DrawState _stateWithOneSelectedElement() => DrawState(
  domain: DomainState(
    document: DocumentState(
      elements: const [
        ElementState(
          id: 'target',
          rect: DrawRect(maxX: 40, maxY: 40),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: FilterData(),
        ),
      ],
    ),
    selection: const SelectionState(selectedIds: {'target'}),
  ),
);
