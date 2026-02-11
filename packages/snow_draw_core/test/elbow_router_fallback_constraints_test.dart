import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'elbow_test_utils.dart';

void main() {
  test('grid fallback respects end heading when start is unbound', () {
    const endRect = DrawRect(minX: 200, minY: 100, maxX: 300, maxY: 200);
    final endElement = elbowRectangleElement(id: 'end', rect: endRect);

    elbowForceGridFailure = true;
    try {
      final result = routeElbowArrow(
        start: DrawPoint.zero,
        end: DrawPoint(x: endRect.centerX, y: endRect.centerY),
        endBinding: const ArrowBinding(
          elementId: 'end',
          anchor: DrawPoint(x: 1, y: 0.5),
        ),
        elementsById: {'end': endElement},
        endArrowhead: ArrowheadStyle.triangle,
      );

      expect(elbowPathIsOrthogonal(result.points), isTrue);
      expect(result.points.length, greaterThan(2));

      final penultimate = result.points[result.points.length - 2];
      final endPoint = result.points.last;
      expect(
        (penultimate.y - endPoint.y).abs() <=
            ElbowConstants.intersectionEpsilon,
        isTrue,
        reason: 'Right binding should approach horizontally.',
      );
      expect(
        penultimate.x > endPoint.x,
        isTrue,
        reason: 'Right binding should approach from the right.',
      );
    } finally {
      elbowForceGridFailure = false;
    }
  });

  test(
    'grid fallback respects both endpoint headings when grid routing fails',
    () {
      const startRect = DrawRect(minX: 300, minY: 300, maxX: 400, maxY: 400);
      const endRect = DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200);
      final startElement = elbowRectangleElement(id: 'start', rect: startRect);
      final endElement = elbowRectangleElement(id: 'end', rect: endRect);

      elbowForceGridFailure = true;
      try {
        final result = routeElbowArrow(
          start: DrawPoint(x: startRect.centerX, y: startRect.centerY),
          end: DrawPoint(x: endRect.centerX, y: endRect.centerY),
          startBinding: const ArrowBinding(
            elementId: 'start',
            anchor: DrawPoint(x: 0.5, y: 0),
          ),
          endBinding: const ArrowBinding(
            elementId: 'end',
            anchor: DrawPoint(x: 1, y: 0.5),
          ),
          elementsById: {'start': startElement, 'end': endElement},
          startArrowhead: ArrowheadStyle.triangle,
          endArrowhead: ArrowheadStyle.triangle,
        );

        expect(elbowPathIsOrthogonal(result.points), isTrue);
        expect(result.points.length, greaterThan(2));

        final startPoint = result.points.first;
        final nextPoint = result.points[1];
        expect(
          (startPoint.x - nextPoint.x).abs() <=
              ElbowConstants.intersectionEpsilon,
          isTrue,
          reason: 'Top binding should depart vertically.',
        );
        expect(
          nextPoint.y < startPoint.y,
          isTrue,
          reason: 'Top binding should depart upward.',
        );

        final penultimate = result.points[result.points.length - 2];
        final endPoint = result.points.last;
        expect(
          (penultimate.y - endPoint.y).abs() <=
              ElbowConstants.intersectionEpsilon,
          isTrue,
          reason: 'Right binding should approach horizontally.',
        );
        expect(
          penultimate.x > endPoint.x,
          isTrue,
          reason: 'Right binding should approach from the right.',
        );
      } finally {
        elbowForceGridFailure = false;
      }
    },
  );
}
