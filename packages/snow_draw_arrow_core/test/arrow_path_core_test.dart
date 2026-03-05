import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_path_core arrowhead metrics', () {
    test('resolves canonical arrowhead length', () {
      expect(resolveArrowheadLength(2), 20);
      expect(resolveArrowheadLength(0), 12);
    });

    test('computes inset and direction offsets by arrowhead style', () {
      expect(
        calculateArrowheadInset(arrowhead: 'triangle', strokeWidth: 2),
        20,
      );
      expect(calculateArrowheadInset(arrowhead: 'arrow', strokeWidth: 2), 0);
      expect(
        calculateArrowheadDirectionOffset(arrowhead: 'bar', strokeWidth: 2),
        12,
      );
      expect(
        calculateArrowheadDirectionOffset(
          arrowhead: 'crowfoot_many',
          strokeWidth: 2,
        ),
        20,
      );
    });
  });

  group('arrow_path_core path geometry', () {
    test('applies endpoint insets along polyline', () {
      final result = applyArrowEndpointInsets(
        points: const <Point>[
          <double>[0, 0],
          <double>[10, 0],
          <double>[10, 10],
        ],
        startInset: 2,
        endInset: 3,
      );

      expect(result, const <Point>[
        <double>[2, 0],
        <double>[10, 0],
        <double>[10, 7],
      ]);
    });

    test('resolves start and end direction vectors for straight path', () {
      const points = <Point>[
        <double>[0, 0],
        <double>[10, 0],
      ];
      final start = resolveArrowStartDirection(points: points, curved: false);
      final end = resolveArrowEndDirection(points: points, curved: false);

      expect(start, isNotNull);
      expect(end, isNotNull);
      expect(start![0], closeTo(-1, 1e-9));
      expect(start[1], closeTo(0, 1e-9));
      expect(end![0], closeTo(1, 1e-9));
      expect(end[1], closeTo(0, 1e-9));
    });

    test('calculates curved bounds that include control bulge', () {
      final bounds = calculateArrowPathBounds(
        points: const <Point>[
          <double>[0, 0],
          <double>[10, 10],
          <double>[20, 0],
        ],
        curved: true,
      );

      expect(bounds[0], lessThanOrEqualTo(0));
      expect(bounds[2], greaterThanOrEqualTo(20));
      expect(bounds[3], greaterThanOrEqualTo(10));
    });
  });
}
