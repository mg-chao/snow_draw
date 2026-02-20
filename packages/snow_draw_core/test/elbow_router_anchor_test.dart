import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'elbow_test_utils.dart';

const _rect = DrawRect(minX: 100, minY: 100, maxX: 500, maxY: 260);
const _elementId = 'rect-1';

ElbowRouteResult _routeToEndAnchor({
  required DrawPoint start,
  required DrawPoint end,
  required DrawPoint anchor,
}) {
  final element = elbowRectangleElement(id: _elementId, rect: _rect);
  return routeElbowArrow(
    start: start,
    end: end,
    endBinding: ArrowBinding(elementId: _elementId, anchor: anchor),
    elementsById: {_elementId: element},
    endArrowhead: ArrowheadStyle.triangle,
  );
}

void _expectValidRoute(ElbowRouteResult result) {
  expect(
    elbowPathIntersectsBounds(result.points, _rect),
    isFalse,
    reason: 'Route should not pass through the bound rectangle.',
  );
  expect(
    elbowPathIsOrthogonal(result.points),
    isTrue,
    reason: 'Elbow paths should remain orthogonal.',
  );
}

DrawPoint _penultimatePoint(ElbowRouteResult result) =>
    result.points[result.points.length - 2];

void main() {
  test('elbow routing avoids a bound rectangle when start aligns above', () {
    final result = _routeToEndAnchor(
      start: DrawPoint(x: _rect.centerX, y: _rect.minY - 40),
      end: DrawPoint(x: _rect.centerX, y: _rect.maxY + 200),
      anchor: const DrawPoint(x: 0.5, y: 1),
    );

    _expectValidRoute(result);
    expect(
      result.points.length,
      greaterThan(2),
      reason: 'Expected at least one bend to route around the rectangle.',
    );

    final penultimate = _penultimatePoint(result);
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
    final result = _routeToEndAnchor(
      start: DrawPoint(x: _rect.centerX, y: _rect.maxY + 60),
      end: DrawPoint(x: _rect.centerX, y: _rect.minY - 200),
      anchor: const DrawPoint(x: 0.5, y: 0),
    );

    _expectValidRoute(result);

    final penultimate = _penultimatePoint(result);
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
    final result = _routeToEndAnchor(
      start: DrawPoint(x: _rect.maxX + 200, y: _rect.centerY),
      end: DrawPoint(x: _rect.minX - 200, y: _rect.centerY),
      anchor: const DrawPoint(x: 0, y: 0.5),
    );

    _expectValidRoute(result);

    final penultimate = _penultimatePoint(result);
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
    final result = _routeToEndAnchor(
      start: DrawPoint(x: _rect.minX - 200, y: _rect.centerY),
      end: DrawPoint(x: _rect.maxX + 200, y: _rect.centerY),
      anchor: const DrawPoint(x: 1, y: 0.5),
    );

    _expectValidRoute(result);

    final penultimate = _penultimatePoint(result);
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
