import 'package:snow_draw_core/draw/input/double_tap_tracker.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:test/test.dart';

void main() {
  group('DoubleTapTracker', () {
    test('matches same target within threshold and tolerance', () {
      final tracker = DoubleTapTracker<String>(
        threshold: const Duration(milliseconds: 400),
      );
      final now = DateTime(2026, 6, 1, 10);

      tracker.recordTap(
        target: 'arrow',
        position: const DrawPoint(x: 10, y: 10),
        now: now,
      );

      final isDoubleTap = tracker.isDoubleTap(
        target: 'arrow',
        position: const DrawPoint(x: 11, y: 11),
        now: now.add(const Duration(milliseconds: 150)),
        baseTolerance: 2,
      );

      expect(isDoubleTap, isTrue);
    });

    test('rejects tap when target differs', () {
      final tracker = DoubleTapTracker<String>();
      final now = DateTime(2026, 6, 1, 10);

      tracker.recordTap(
        target: 'arrow-a',
        position: const DrawPoint(x: 10, y: 10),
        now: now,
      );

      final isDoubleTap = tracker.isDoubleTap(
        target: 'arrow-b',
        position: const DrawPoint(x: 10, y: 10),
        now: now.add(const Duration(milliseconds: 100)),
        baseTolerance: 3,
      );

      expect(isDoubleTap, isFalse);
    });

    test('rejects tap when too late', () {
      final tracker = DoubleTapTracker<String>(
        threshold: const Duration(milliseconds: 200),
      );
      final now = DateTime(2026, 6, 1, 10);

      tracker.recordTap(
        target: 'arrow',
        position: const DrawPoint(x: 10, y: 10),
        now: now,
      );

      final isDoubleTap = tracker.isDoubleTap(
        target: 'arrow',
        position: const DrawPoint(x: 10, y: 10),
        now: now.add(const Duration(milliseconds: 300)),
        baseTolerance: 3,
      );

      expect(isDoubleTap, isFalse);
    });

    test('rejects tap when position exceeds tolerance', () {
      final tracker = DoubleTapTracker<String>();
      final now = DateTime(2026, 6, 1, 10);

      tracker.recordTap(
        target: 'arrow',
        position: const DrawPoint(x: 10, y: 10),
        now: now,
      );

      final isDoubleTap = tracker.isDoubleTap(
        target: 'arrow',
        position: const DrawPoint(x: 30, y: 30),
        now: now.add(const Duration(milliseconds: 100)),
        baseTolerance: 4,
      );

      expect(isDoubleTap, isFalse);
    });

    test('clear resets tracker state', () {
      final tracker = DoubleTapTracker<String>();
      final now = DateTime(2026, 6, 1, 10);

      tracker
        ..recordTap(
          target: 'arrow',
          position: const DrawPoint(x: 10, y: 10),
          now: now,
        )
        ..clear();

      final isDoubleTap = tracker.isDoubleTap(
        target: 'arrow',
        position: const DrawPoint(x: 10, y: 10),
        now: now.add(const Duration(milliseconds: 100)),
        baseTolerance: 4,
      );

      expect(isDoubleTap, isFalse);
    });
  });
}
