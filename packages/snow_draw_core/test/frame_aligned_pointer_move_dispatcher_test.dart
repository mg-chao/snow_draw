import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/input/input_event.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/ui/canvas/frame_aligned_pointer_move_dispatcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FrameAlignedPointerMoveDispatcher', () {
    testWidgets('coalesces move events to the latest event per frame', (
      tester,
    ) async {
      final dispatched = <PointerMoveInputEvent>[];
      final dispatcher = FrameAlignedPointerMoveDispatcher(
        dispatchMove: (event) async {
          dispatched.add(event);
        },
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
      tester,
    ) async {
      final dispatched = <PointerMoveInputEvent>[];
      final dispatcher = FrameAlignedPointerMoveDispatcher(
        dispatchMove: (event) async {
          dispatched.add(event);
        },
        shouldCoalesce: () => true,
      );

      _dispatchMoves(dispatcher, const [5, 9]);

      await dispatcher.flush();
      await tester.pump();

      expect(dispatched, hasLength(1));
      expect(dispatched.single.position.x, 9);
      await dispatcher.dispose();
    });

    testWidgets('merge callback keeps coalesced move samples', (tester) async {
      final dispatched = <PointerMoveInputEvent>[];
      final dispatcher = FrameAlignedPointerMoveDispatcher(
        dispatchMove: (event) async {
          dispatched.add(event);
        },
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
      tester,
    ) async {
      final dispatched = <PointerMoveInputEvent>[];
      final dispatcher = FrameAlignedPointerMoveDispatcher(
        dispatchMove: (event) async {
          dispatched.add(event);
        },
        shouldCoalesce: () => false,
      );

      _dispatchMoves(dispatcher, const [1, 2]);

      await dispatcher.flush();
      await tester.pump();

      expect(dispatched, hasLength(2));
      expect(dispatched[0].position.x, 1);
      expect(dispatched[1].position.x, 2);
      await dispatcher.dispose();
    });

    testWidgets('flush waits for queued non-coalesced moves', (tester) async {
      final dispatched = <PointerMoveInputEvent>[];
      final firstMoveGate = Completer<void>();
      final secondMoveGate = Completer<void>();
      var moveCount = 0;
      final dispatcher = FrameAlignedPointerMoveDispatcher(
        dispatchMove: (event) async {
          dispatched.add(event);
          moveCount += 1;
          if (moveCount == 1) {
            await firstMoveGate.future;
            return;
          }
          if (moveCount == 2) {
            await secondMoveGate.future;
          }
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
      (tester) async {
        final dispatched = <PointerMoveInputEvent>[];
        var shouldCoalesce = true;
        final dispatcher = FrameAlignedPointerMoveDispatcher(
          dispatchMove: (event) async {
            dispatched.add(event);
          },
          shouldCoalesce: () => shouldCoalesce,
        );

        final dispatch = dispatcher.dispatch;
        dispatch(_moveEvent(x: 4));
        shouldCoalesce = false;
        dispatch(_moveEvent(x: 7));

        await dispatcher.flush();
        await tester.pump();

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
