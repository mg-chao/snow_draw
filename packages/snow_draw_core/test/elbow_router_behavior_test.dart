import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'elbow_test_utils.dart';

const _rectId = 'rect-1';

ElbowRouteResult _routeFallback({
  required DrawPoint start,
  required DrawPoint end,
}) => routeElbowArrow(start: start, end: end, elementsById: const {});

void _expectOrthogonal(ElbowRouteResult result) {
  expect(elbowPathIsOrthogonal(result.points), isTrue);
}

void _expectTopBindingDepartsUp(ElbowRouteResult result) {
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
}

void _expectLeftBindingDepartsLeft(ElbowRouteResult result) {
  final startPoint = result.points.first;
  final nextPoint = result.points[1];
  expect(
    (startPoint.y - nextPoint.y).abs() <= ElbowConstants.intersectionEpsilon,
    isTrue,
    reason: 'Left binding should depart horizontally.',
  );
  expect(
    nextPoint.x < startPoint.x,
    isTrue,
    reason: 'Left binding should depart to the left.',
  );
}

void _expectRightBindingApproachesFromRight(ElbowRouteResult result) {
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
}

void main() {
  test(
    'elbow routing fallback uses a midpoint elbow for unbound endpoints',
    () {
      const start = DrawPoint.zero;
      const end = DrawPoint(x: 100, y: 50);

      final result = _routeFallback(start: start, end: end);

      expect(result.points, [
        start,
        const DrawPoint(x: 50, y: 0),
        const DrawPoint(x: 50, y: 50),
        end,
      ]);
      _expectOrthogonal(result);
    },
  );

  test('elbow routing fallback uses a stable midpoint for short arrows', () {
    const start = DrawPoint.zero;
    const end = DrawPoint(x: 4, y: 3);

    final result = _routeFallback(start: start, end: end);

    expect(result.points, [
      start,
      const DrawPoint(x: 0, y: 1.5),
      const DrawPoint(x: 4, y: 1.5),
      end,
    ]);
    _expectOrthogonal(result);
  });

  test('elbow routing fallback is direct when aligned', () {
    const start = DrawPoint(x: 10, y: 10);
    const end = DrawPoint(x: 10, y: 110);

    final result = _routeFallback(start: start, end: end);

    expect(result.points, [start, end]);
    _expectOrthogonal(result);
  });

  test('aligned endpoints with incompatible headings route with an elbow', () {
    const rect = DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200);
    final element = elbowRectangleElement(id: _rectId, rect: rect);
    const binding = ArrowBinding(
      elementId: _rectId,
      anchor: DrawPoint(x: 0.5, y: 0),
    );

    final boundStart = ArrowBindingUtils.resolveElbowBoundPoint(
      binding: binding,
      target: element,
      hasArrowhead: true,
    )!;

    final result = routeElbowArrow(
      start: boundStart,
      end: DrawPoint(x: boundStart.x + 160, y: boundStart.y),
      startBinding: binding,
      elementsById: {_rectId: element},
      startArrowhead: ArrowheadStyle.triangle,
    );

    expect(result.points.length, greaterThan(2));
    _expectOrthogonal(result);
    _expectTopBindingDepartsUp(result);
  });

  test('elbow routing respects a bound start heading', () {
    const rect = DrawRect(minX: 100, minY: 100, maxX: 300, maxY: 200);
    final element = elbowRectangleElement(id: _rectId, rect: rect);

    final result = routeElbowArrow(
      start: DrawPoint.zero,
      end: DrawPoint(x: rect.centerX, y: rect.maxY + 200),
      startBinding: const ArrowBinding(
        elementId: _rectId,
        anchor: DrawPoint(x: 0.5, y: 0),
      ),
      elementsById: {_rectId: element},
      startArrowhead: ArrowheadStyle.triangle,
    );

    expect(elbowPathIntersectsBounds(result.points, rect), isFalse);
    _expectOrthogonal(result);
    _expectTopBindingDepartsUp(result);
  });

  test('elbow routing avoids multiple bound rectangles', () {
    const rectA = DrawRect(minX: 100, minY: 100, maxX: 240, maxY: 220);
    const rectB = DrawRect(minX: 340, minY: 140, maxX: 480, maxY: 260);
    final elementA = elbowRectangleElement(id: 'rect-a', rect: rectA);
    final elementB = elbowRectangleElement(id: 'rect-b', rect: rectB);

    final result = routeElbowArrow(
      start: DrawPoint(x: rectA.minX - 120, y: rectA.centerY),
      end: DrawPoint(x: rectB.maxX + 120, y: rectB.centerY),
      startBinding: const ArrowBinding(
        elementId: 'rect-a',
        anchor: DrawPoint(x: 0, y: 0.5),
      ),
      endBinding: const ArrowBinding(
        elementId: 'rect-b',
        anchor: DrawPoint(x: 1, y: 0.5),
      ),
      elementsById: {'rect-a': elementA, 'rect-b': elementB},
      startArrowhead: ArrowheadStyle.triangle,
      endArrowhead: ArrowheadStyle.triangle,
    );

    expect(elbowPathIntersectsBounds(result.points, rectA), isFalse);
    expect(elbowPathIntersectsBounds(result.points, rectB), isFalse);
    _expectOrthogonal(result);
  });

  test('elbow routing handles overlapping bound obstacles', () {
    const rectA = DrawRect(minX: 100, minY: 120, maxX: 240, maxY: 260);
    const rectB = DrawRect(minX: 200, minY: 160, maxX: 340, maxY: 300);
    final elementA = elbowRectangleElement(id: 'rect-a', rect: rectA);
    final elementB = elbowRectangleElement(id: 'rect-b', rect: rectB);

    final result = routeElbowArrow(
      start: DrawPoint(x: rectA.minX - 140, y: rectA.centerY),
      end: DrawPoint(x: rectB.maxX + 140, y: rectB.centerY),
      startBinding: const ArrowBinding(
        elementId: 'rect-a',
        anchor: DrawPoint(x: 0, y: 0.5),
      ),
      endBinding: const ArrowBinding(
        elementId: 'rect-b',
        anchor: DrawPoint(x: 1, y: 0.5),
      ),
      elementsById: {'rect-a': elementA, 'rect-b': elementB},
      startArrowhead: ArrowheadStyle.triangle,
      endArrowhead: ArrowheadStyle.triangle,
    );

    expect(result.points.length, greaterThan(2));
    _expectOrthogonal(result);
    _expectLeftBindingDepartsLeft(result);
    _expectRightBindingApproachesFromRight(result);
  });
}
