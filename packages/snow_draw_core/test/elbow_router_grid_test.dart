import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'elbow_test_utils.dart';

void main() {
  test('grid routing avoids obstacles and stays orthogonal', () {
    const rectA = DrawRect(minX: 100, minY: 100, maxX: 240, maxY: 240);
    const rectB = DrawRect(minX: 360, minY: 160, maxX: 500, maxY: 300);
    final elementA = elbowRectangleElement(id: 'rect-a', rect: rectA);
    final elementB = elbowRectangleElement(id: 'rect-b', rect: rectB);

    final result = routeElbowArrow(
      start: DrawPoint(x: rectA.minX - 140, y: rectA.minY - 80),
      end: DrawPoint(x: rectB.maxX + 160, y: rectB.maxY + 120),
      startBinding: const ArrowBinding(
        elementId: 'rect-a',
        anchor: DrawPoint(x: 0, y: 0.5),
      ),
      endBinding: const ArrowBinding(
        elementId: 'rect-b',
        anchor: DrawPoint(x: 1, y: 0.5),
      ),
      elementsById: {
        'rect-a': elementA,
        'rect-b': elementB,
      },
      startArrowhead: ArrowheadStyle.triangle,
      endArrowhead: ArrowheadStyle.triangle,
    );

    expect(result.points.length, greaterThan(2));
    expect(elbowPathIsOrthogonal(result.points), isTrue);
    expect(elbowPathHasOnlyCorners(result.points), isTrue);
    expect(elbowPathIntersectsBounds(result.points, rectA), isFalse);
    expect(elbowPathIntersectsBounds(result.points, rectB), isFalse);
  });

  test('grid routing honors constrained start/end headings', () {
    const startRect = DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 220);
    const endRect = DrawRect(minX: 360, minY: 160, maxX: 480, maxY: 280);
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
      elementsById: {
        'start': startElement,
        'end': endElement,
      },
      startArrowhead: ArrowheadStyle.triangle,
      endArrowhead: ArrowheadStyle.triangle,
    );

    expect(result.points.length, greaterThan(2));
    expect(elbowPathIsOrthogonal(result.points), isTrue);
    expect(elbowPathIntersectsBounds(result.points, startRect), isFalse);
    expect(elbowPathIntersectsBounds(result.points, endRect), isFalse);

    final startPoint = result.points.first;
    final nextPoint = result.points[1];
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

    final penultimate = result.points[result.points.length - 2];
    final endPoint = result.points.last;
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
  });
}

