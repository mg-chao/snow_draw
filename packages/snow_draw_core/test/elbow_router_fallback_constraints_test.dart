import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:test/test.dart';

import 'elbow_test_utils.dart';

void main() {
  test('fallback routing respects end heading when start is unbound', () {
    const endRect = DrawRect(minX: 200, minY: 100, maxX: 300, maxY: 200);
    final endElement = elbowRectangleElement(id: 'end', rect: endRect);

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

    _expectOrthogonalFallbackPath(result.points);
    _expectApproachFromRight(result.points);
  });

  test('fallback routing respects both endpoint headings', () {
    const startRect = DrawRect(minX: 300, minY: 300, maxX: 400, maxY: 400);
    const endRect = DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200);
    final startElement = elbowRectangleElement(id: 'start', rect: startRect);
    final endElement = elbowRectangleElement(id: 'end', rect: endRect);

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

    _expectOrthogonalFallbackPath(result.points);
    _expectDepartureUpward(result.points);
    _expectApproachFromRight(result.points);
  });
}

void _expectOrthogonalFallbackPath(List<DrawPoint> points) {
  expect(elbowPathIsOrthogonal(points), isTrue);
  expect(points.length, greaterThan(2));
}

void _expectDepartureUpward(List<DrawPoint> points) {
  final startPoint = points.first;
  final nextPoint = points[1];

  expect(
    (startPoint.x - nextPoint.x).abs() <= ElbowConstants.intersectionEpsilon,
    isTrue,
    reason: 'Top binding should depart vertically.',
  );
  expect(
    nextPoint.y < startPoint.y,
    isTrue,
    reason: 'Top binding should depart upward.',
  );
}

void _expectApproachFromRight(List<DrawPoint> points) {
  final penultimate = points[points.length - 2];
  final endPoint = points.last;

  expect(
    (penultimate.y - endPoint.y).abs() <= ElbowConstants.intersectionEpsilon,
    isTrue,
    reason: 'Right binding should approach horizontally.',
  );
  expect(
    penultimate.x > endPoint.x,
    isTrue,
    reason: 'Right binding should approach from the right.',
  );
}
