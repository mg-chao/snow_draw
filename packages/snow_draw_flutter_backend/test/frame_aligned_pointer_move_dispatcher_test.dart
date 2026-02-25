import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_engine.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/frame_aligned_pointer_move_dispatcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FrameAlignedPointerMoveDispatcher', () {
    testWidgets('coalesces move events to the latest event per frame', (
      tester,
    ) async {
      final dispatched = <PointerMoveInputEvent>[];
      final dispatcher = _createDispatcher(
        dispatchMove: (event) async => dispatched.add(event),
        shouldCoalesce: () => true,
      );

      _dispatchMoves(dispatcher, const [1, 2, 3]);

      expect(dispatched, isEmpty);

      await tester.pump();

      expect(dispatched, hasLength(1));
      expect(dispatched.single.position.x, 3);
      await dispatcher.dispose();
    });

    testWidgets('flush dispatches the latest pending move immediately', (
      _,
    ) async {
      final dispatched = <PointerMoveInputEvent>[];
      final dispatcher = _createDispatcher(
        dispatchMove: (event) async => dispatched.add(event),
        shouldCoalesce: () => true,
      );

      _dispatchMoves(dispatcher, const [5, 9]);

      await dispatcher.flush();

      expect(dispatched, hasLength(1));
      expect(dispatched.single.position.x, 9);
      await dispatcher.dispose();
    });

    testWidgets('merge callback keeps coalesced move samples', (tester) async {
      final dispatched = <PointerMoveInputEvent>[];
      final dispatcher = _createDispatcher(
        dispatchMove: (event) async => dispatched.add(event),
        shouldCoalesce: () => true,
        mergeCoalescedEvents: (pending, incoming) =>
            pending.mergeWith(incoming),
      );

      _dispatchMoves(dispatcher, const [1, 2, 3]);

      await tester.pump();

      expect(dispatched, hasLength(1));
      final event = dispatched.single;
      expect(event.sampleCount, 3);
      expect(
        event.samples().map((point) => point.x).toList(growable: false),
        equals(const [1.0, 2.0, 3.0]),
      );
      await dispatcher.dispose();
    });

    testWidgets('dispatches every move immediately when coalescing is off', (
      _,
    ) async {
      final dispatched = <PointerMoveInputEvent>[];
      final dispatcher = _createDispatcher(
        dispatchMove: (event) async => dispatched.add(event),
        shouldCoalesce: () => false,
      );

      _dispatchMoves(dispatcher, const [1, 2]);

      await dispatcher.flush();

      expect(dispatched, hasLength(2));
      expect(dispatched[0].position.x, 1);
      expect(dispatched[1].position.x, 2);
      await dispatcher.dispose();
    });

    testWidgets('flush waits for queued non-coalesced moves', (tester) async {
      final dispatched = <PointerMoveInputEvent>[];
      final firstMoveGate = Completer<void>();
      final secondMoveGate = Completer<void>();
      final moveGates = [firstMoveGate, secondMoveGate];
      var moveGateIndex = 0;
      final dispatcher = _createDispatcher(
        dispatchMove: (event) async {
          dispatched.add(event);
          await moveGates[moveGateIndex++].future;
        },
        shouldCoalesce: () => false,
      );

      _dispatchMoves(dispatcher, const [1, 2]);

      final flushFuture = dispatcher.flush();

      await tester.pump();
      expect(dispatched, hasLength(1));

      firstMoveGate.complete();
      await tester.pump();
      expect(dispatched, hasLength(2));

      var flushCompleted = false;
      unawaited(
        flushFuture.then((_) {
          flushCompleted = true;
        }),
      );
      await tester.pump();
      expect(flushCompleted, isFalse);

      secondMoveGate.complete();
      await flushFuture;
      expect(flushCompleted, isTrue);
      await dispatcher.dispose();
    });

    testWidgets(
      'preserves pending coalesced move before immediate dispatch mode',
      (_) async {
        final dispatched = <PointerMoveInputEvent>[];
        var shouldCoalesce = true;
        final dispatcher = _createDispatcher(
          dispatchMove: (event) async => dispatched.add(event),
          shouldCoalesce: () => shouldCoalesce,
        );

        final dispatch = dispatcher.dispatch;
        dispatch(_moveEvent(x: 4));
        shouldCoalesce = false;
        dispatch(_moveEvent(x: 7));

        await dispatcher.flush();

        expect(dispatched, hasLength(2));
        expect(dispatched[0].position.x, 4);
        expect(dispatched[1].position.x, 7);
        await dispatcher.dispose();
      },
    );
  });
}

PointerMoveInputEvent _moveEvent({required double x}) => PointerMoveInputEvent(
  position: DrawPoint(x: x, y: 0),
  modifiers: KeyModifiers.none,
);

void _dispatchMoves(
  FrameAlignedPointerMoveDispatcher dispatcher,
  List<double> xs,
) {
  for (final x in xs) {
    dispatcher.dispatch(_moveEvent(x: x));
  }
}

FrameAlignedPointerMoveDispatcher _createDispatcher({
  required PointerMoveEventSink dispatchMove,
  required bool Function() shouldCoalesce,
  PointerMoveInputEvent Function(
    PointerMoveInputEvent pending,
    PointerMoveInputEvent incoming,
  )?
  mergeCoalescedEvents,
}) => FrameAlignedPointerMoveDispatcher(
  dispatchMove: dispatchMove,
  shouldCoalesce: shouldCoalesce,
  mergeCoalescedEvents: mergeCoalescedEvents,
);
