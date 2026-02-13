import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:snow_draw_core/draw/events/error_events.dart';
import 'package:snow_draw_core/draw/events/event_bus.dart';
import 'package:snow_draw_core/draw/events/log_events.dart';
import 'package:snow_draw_core/draw/events/state_events.dart';

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

      await Future<void>.delayed(Duration.zero);

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

    test('GeneralLogEvent keeps an immutable snapshot of data', () {
      final data = <String, dynamic>{'step': 'init'};
      final event = GeneralLogEvent(
        level: Level.info,
        module: 'Pipeline',
        message: 'Initialized',
        timestamp: DateTime(2026),
        data: data,
      );

      data['step'] = 'mutated';

      expect(event.data?['step'], equals('init'));
      expect(
        () => event.data?['extra'] = true,
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
