import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/input/input_event.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';

void main() {
  group('PointerMoveInputEvent', () {
    test('keeps an immutable snapshot of sampled points', () {
      final sampledPoints = <DrawPoint>[
        const DrawPoint(x: 1, y: 2),
        const DrawPoint(x: 3, y: 4),
      ];

      final event = PointerMoveInputEvent(
        position: const DrawPoint(x: 3, y: 4),
        modifiers: KeyModifiers.none,
        sampledPoints: sampledPoints,
      );

      sampledPoints.add(const DrawPoint(x: 5, y: 6));

      expect(event.sampledPoints, hasLength(2));
      expect(
        () => event.sampledPoints.add(const DrawPoint(x: 7, y: 8)),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('ensures sampled points include the event position', () {
      final event = PointerMoveInputEvent(
        position: const DrawPoint(x: 10, y: 12),
        modifiers: KeyModifiers.none,
        sampledPoints: const [DrawPoint(x: 2, y: 4)],
      );

      expect(event.sampleCount, 2);
      expect(
        event.samples().toList(growable: false),
        equals(const [DrawPoint(x: 2, y: 4), DrawPoint(x: 10, y: 12)]),
      );
    });

    test('mergeWith preserves draw order and removes adjacent duplicates', () {
      final pending = PointerMoveInputEvent(
        position: const DrawPoint(x: 3, y: 3),
        modifiers: KeyModifiers.none,
        sampledPoints: const [DrawPoint(x: 1, y: 1), DrawPoint(x: 3, y: 3)],
      );
      final incoming = PointerMoveInputEvent(
        position: const DrawPoint(x: 6, y: 6),
        modifiers: KeyModifiers.none,
        sampledPoints: const [DrawPoint(x: 3, y: 3), DrawPoint(x: 6, y: 6)],
      );

      final merged = pending.mergeWith(incoming);

      expect(
        merged.samples().toList(growable: false),
        equals(const [
          DrawPoint(x: 1, y: 1),
          DrawPoint(x: 3, y: 3),
          DrawPoint(x: 6, y: 6),
        ]),
      );
      expect(merged.position, const DrawPoint(x: 6, y: 6));
      expect(merged.sampleCount, 3);
    });
  });
}
