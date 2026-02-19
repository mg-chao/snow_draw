import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_two_point_layout.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  group('computeArrowTwoPointLayout', () {
    test('matches generic two-point rect + normalization', () {
      final samples = <(DrawPoint, DrawPoint)>[
        (DrawPoint.zero, const DrawPoint(x: 100, y: 50)),
        (const DrawPoint(x: 100, y: 50), DrawPoint.zero),
        (const DrawPoint(x: 10, y: 20), const DrawPoint(x: 10, y: 90)),
        (const DrawPoint(x: 30, y: 40), const DrawPoint(x: 130, y: 40)),
      ];

      for (final sample in samples) {
        final first = sample.$1;
        final second = sample.$2;
        final fast = computeArrowTwoPointLayout(first: first, second: second);
        final genericRect = ArrowGeometry.calculatePathBounds(
          worldPoints: [first, second],
          arrowType: ArrowType.straight,
        );
        final genericPoints = ArrowGeometry.normalizePoints(
          worldPoints: [first, second],
          rect: genericRect,
        );

        expect(fast.rect, genericRect);
        expect(fast.normalizedPoints, genericPoints);
      }
    });

    test('preserves point pressure values', () {
      const first = DrawPoint(x: 12, y: 24, pressure: 0.3);
      const second = DrawPoint(x: 48, y: 72, pressure: 0.8);

      final layout = computeArrowTwoPointLayout(first: first, second: second);

      expect(layout.normalizedPoints[0].pressure, first.pressure);
      expect(layout.normalizedPoints[1].pressure, second.pressure);
    });
  });
}
