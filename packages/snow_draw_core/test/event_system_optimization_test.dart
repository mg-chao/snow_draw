import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/events/error_events.dart';
import 'package:snow_draw_core/draw/events/event_bus.dart';
import 'package:snow_draw_core/draw/events/state_events.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('Event emission optimization', () {
    test('skips state events when no listeners are registered', () async {
      final eventBus = _RecordingEventBus(hasListeners: false);
      addTearDown(eventBus.dispose);
      final store = _createStore(
        eventBus: eventBus,
        initialState: _stateWithOneSelectedElement(),
      );
      addTearDown(store.dispose);

      await store.dispatch(
        UpdateElementsStyle(elementIds: ['target'], opacity: 0.4),
      );

      expect(eventBus.emittedEvents, isEmpty);
    });

    test('emits state events when listeners are registered', () async {
      final eventBus = _RecordingEventBus(hasListeners: true);
      addTearDown(eventBus.dispose);
      final store = _createStore(
        eventBus: eventBus,
        initialState: _stateWithOneSelectedElement(),
      );
      addTearDown(store.dispose);

      await store.dispatch(
        UpdateElementsStyle(elementIds: ['target'], opacity: 0.4),
      );

      expect(
        eventBus.emittedEvents.whereType<DocumentChangedEvent>(),
        hasLength(1),
      );
      expect(
        eventBus.emittedEvents.whereType<HistoryAvailabilityChangedEvent>(),
        hasLength(1),
      );
    });

    test('skips validation events when no listeners are registered', () async {
      final eventBus = _RecordingEventBus(hasListeners: false);
      addTearDown(eventBus.dispose);
      final store = _createStore(eventBus: eventBus);
      addTearDown(store.dispose);

      await store.dispatch(DeleteElements(elementIds: []));

      expect(eventBus.emittedEvents, isEmpty);
    });

    test('emits validation events when listeners are registered', () async {
      final eventBus = _RecordingEventBus(hasListeners: true);
      addTearDown(eventBus.dispose);
      final store = _createStore(eventBus: eventBus);
      addTearDown(store.dispose);

      await store.dispatch(DeleteElements(elementIds: []));

      final validationEvents = eventBus.emittedEvents
          .whereType<ValidationFailedEvent>()
          .toList();
      expect(validationEvents, hasLength(1));
      expect(validationEvents.single.action, equals('DeleteElements'));
    });
  });

  group('EventBus ownership', () {
    test(
      'disposing store does not dispose an externally provided event bus',
      () async {
        final eventBus = EventBus();
        final store = _createStore(eventBus: eventBus);
        final received = <DocumentChangedEvent>[];
        final subscription = eventBus.on<DocumentChangedEvent>(received.add);

        addTearDown(() async {
          await subscription.cancel();
          await eventBus.dispose();
        });

        store.dispose();

        expect(eventBus.isDisposed, isFalse);

        eventBus.emit(
          const DocumentChangedEvent(elementsVersion: 7, elementCount: 3),
        );
        await Future<void>.delayed(Duration.zero);

        expect(received, hasLength(1));
        expect(received.single.elementsVersion, equals(7));
      },
    );

    test(
      'disposing store does not dispose event bus passed via constructor',
      () async {
        final eventBus = EventBus();
        final registry = DefaultElementRegistry();
        registerBuiltInElements(registry);
        final context = DrawContext.withDefaults(elementRegistry: registry);
        final store = DefaultDrawStore(context: context, eventBus: eventBus);
        final received = <DocumentChangedEvent>[];
        final subscription = eventBus.on<DocumentChangedEvent>(received.add);

        addTearDown(() async {
          await subscription.cancel();
          await eventBus.dispose();
        });

        store.dispose();

        expect(eventBus.isDisposed, isFalse);

        eventBus.emit(
          const DocumentChangedEvent(elementsVersion: 9, elementCount: 1),
        );
        await Future<void>.delayed(Duration.zero);

        expect(received, hasLength(1));
        expect(received.single.elementsVersion, equals(9));
      },
    );

    test('disposing store disposes internally owned event bus', () {
      final store = _createStore();
      final internalBus = store.eventBus;
      addTearDown(store.dispose);

      store.dispose();

      expect(internalBus.isDisposed, isTrue);
    });
  });
}

DefaultDrawStore _createStore({EventBus? eventBus, DrawState? initialState}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(
    elementRegistry: registry,
    eventBus: eventBus,
  );
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

class _RecordingEventBus extends EventBus {
  _RecordingEventBus({required bool hasListeners})
    : _hasListeners = hasListeners;

  final emittedEvents = <DrawEvent>[];
  final bool _hasListeners;

  @override
  bool get hasListeners => _hasListeners;

  @override
  bool hasListenersFor<T extends DrawEvent>() => _hasListeners;

  @override
  void emit(DrawEvent event) {
    if (!_hasListeners) {
      return;
    }
    emittedEvents.add(event);
  }

  @override
  bool emitLazy<T extends DrawEvent>(T Function() eventFactory) {
    if (!_hasListeners) {
      return false;
    }
    emittedEvents.add(eventFactory());
    return true;
  }
}
