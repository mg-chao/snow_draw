import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'elbow_test_utils.dart';

void main() {
  test('elbow routing avoids a bound rectangle when start aligns above', () {
    const rect = DrawRect(minX: 100, minY: 100, maxX: 500, maxY: 260);
    final element = elbowRectangleElement(id: 'rect-1', rect: rect);
    final start = DrawPoint(x: rect.centerX, y: rect.minY - 40);

    final result = routeElbowArrow(
      start: start,
      end: DrawPoint(x: rect.centerX, y: rect.maxY + 200),
      endBinding: const ArrowBinding(
        elementId: 'rect-1',
        anchor: DrawPoint(x: 0.5, y: 1),
      ),
      elementsById: {'rect-1': element},
      endArrowhead: ArrowheadStyle.triangle,
    );

    expect(
      elbowPathIntersectsBounds(result.points, rect),
      isFalse,
      reason: 'Route should not pass through the bound rectangle.',
    );
    expect(
      result.points.length,
      greaterThan(2),
      reason: 'Expected at least one bend to route around the rectangle.',
    );
    expect(
      elbowPathIsOrthogonal(result.points),
      isTrue,
      reason: 'Elbow paths should remain orthogonal.',
    );

    final penultimate = result.points[result.points.length - 2];
    final endPoint = result.points.last;
    expect(
      (penultimate.x - endPoint.x).abs() <= ElbowConstants.intersectionEpsilon,
      isTrue,
      reason: 'Bottom binding should approach vertically.',
    );
    expect(
      penultimate.y > endPoint.y,
      isTrue,
      reason: 'Bottom binding should approach from below.',
    );
  });

  test('elbow routing approaches a top binding from above', () {
    const rect = DrawRect(minX: 100, minY: 100, maxX: 500, maxY: 260);
    final element = elbowRectangleElement(id: 'rect-1', rect: rect);
    final start = DrawPoint(x: rect.centerX, y: rect.maxY + 60);

    final result = routeElbowArrow(
      start: start,
      end: DrawPoint(x: rect.centerX, y: rect.minY - 200),
      endBinding: const ArrowBinding(
        elementId: 'rect-1',
        anchor: DrawPoint(x: 0.5, y: 0),
      ),
      elementsById: {'rect-1': element},
      endArrowhead: ArrowheadStyle.triangle,
    );

    expect(
      elbowPathIntersectsBounds(result.points, rect),
      isFalse,
      reason: 'Route should not pass through the bound rectangle.',
    );
    expect(
      elbowPathIsOrthogonal(result.points),
      isTrue,
      reason: 'Elbow paths should remain orthogonal.',
    );

    final penultimate = result.points[result.points.length - 2];
    final endPoint = result.points.last;
    expect(
      (penultimate.x - endPoint.x).abs() <= ElbowConstants.intersectionEpsilon,
      isTrue,
      reason: 'Top binding should approach vertically.',
    );
    expect(
      penultimate.y < endPoint.y,
      isTrue,
      reason: 'Top binding should approach from above.',
    );
  });

  test('elbow routing approaches a left binding from left side', () {
    const rect = DrawRect(minX: 100, minY: 100, maxX: 500, maxY: 260);
    final element = elbowRectangleElement(id: 'rect-1', rect: rect);
    final start = DrawPoint(x: rect.maxX + 200, y: rect.centerY);

    final result = routeElbowArrow(
      start: start,
      end: DrawPoint(x: rect.minX - 200, y: rect.centerY),
      endBinding: const ArrowBinding(
        elementId: 'rect-1',
        anchor: DrawPoint(x: 0, y: 0.5),
      ),
      elementsById: {'rect-1': element},
      endArrowhead: ArrowheadStyle.triangle,
    );

    expect(
      elbowPathIntersectsBounds(result.points, rect),
      isFalse,
      reason: 'Route should not pass through the bound rectangle.',
    );
    expect(
      elbowPathIsOrthogonal(result.points),
      isTrue,
      reason: 'Elbow paths should remain orthogonal.',
    );

    final penultimate = result.points[result.points.length - 2];
    final endPoint = result.points.last;
    expect(
      (penultimate.y - endPoint.y).abs() <= ElbowConstants.intersectionEpsilon,
      isTrue,
      reason: 'Left binding should approach horizontally.',
    );
    expect(
      penultimate.x < endPoint.x,
      isTrue,
      reason: 'Left binding should approach from the left.',
    );
  });

  test('elbow routing approaches a right binding from right side', () {
    const rect = DrawRect(minX: 100, minY: 100, maxX: 500, maxY: 260);
    final element = elbowRectangleElement(id: 'rect-1', rect: rect);
    final start = DrawPoint(x: rect.minX - 200, y: rect.centerY);

    final result = routeElbowArrow(
      start: start,
      end: DrawPoint(x: rect.maxX + 200, y: rect.centerY),
      endBinding: const ArrowBinding(
        elementId: 'rect-1',
        anchor: DrawPoint(x: 1, y: 0.5),
      ),
      elementsById: {'rect-1': element},
      endArrowhead: ArrowheadStyle.triangle,
    );

    expect(
      elbowPathIntersectsBounds(result.points, rect),
      isFalse,
      reason: 'Route should not pass through the bound rectangle.',
    );
    expect(
      elbowPathIsOrthogonal(result.points),
      isTrue,
      reason: 'Elbow paths should remain orthogonal.',
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
