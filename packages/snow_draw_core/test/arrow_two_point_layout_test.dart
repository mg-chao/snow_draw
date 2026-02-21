import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_two_point_layout.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  group('computeArrowTwoPointLayout', () {
    test('matches generic two-point rect + normalization', () {
      const samples = <(DrawPoint, DrawPoint)>[
        (DrawPoint.zero, DrawPoint(x: 100, y: 50)),
        (DrawPoint(x: 100, y: 50), DrawPoint.zero),
        (DrawPoint(x: 10, y: 20), DrawPoint(x: 10, y: 90)),
        (DrawPoint(x: 30, y: 40), DrawPoint(x: 130, y: 40)),
      ];

      for (final (first, second) in samples) {
        final fast = computeArrowTwoPointLayout(first: first, second: second);
        final rect = ArrowGeometry.calculatePathBounds(
          worldPoints: [first, second],
          arrowType: ArrowType.straight,
        );
        final normalizedPoints = ArrowGeometry.normalizePoints(
          worldPoints: [first, second],
          rect: rect,
        );

        expect(fast.rect, rect);
        expect(fast.normalizedPoints, normalizedPoints);
      }
    });

    test('preserves point pressure values', () {
      const first = DrawPoint(x: 12, y: 24, pressure: 0.3);
      const second = DrawPoint(x: 48, y: 72, pressure: 0.8);

      final layout = computeArrowTwoPointLayout(first: first, second: second);
      final points = layout.normalizedPoints;

      expect(points.first.pressure, first.pressure);
      expect(points.last.pressure, second.pressure);
    });
  });
}
