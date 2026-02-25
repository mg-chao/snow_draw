import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:test/test.dart';

import 'elbow_test_utils.dart';

const double _epsilon = ElbowConstants.intersectionEpsilon;
const ArrowheadStyle _boundArrowhead = ArrowheadStyle.triangle;

bool _closeTo(double a, double b) => (a - b).abs() <= _epsilon;

ElbowRouteResult _routeBoundToBound({
  required String startId,
  required DrawRect startRect,
  required DrawPoint startAnchor,
  required String endId,
  required DrawRect endRect,
  required DrawPoint endAnchor,
}) {
  final startElement = elbowRectangleElement(id: startId, rect: startRect);
  final endElement = elbowRectangleElement(id: endId, rect: endRect);

  return routeElbowArrow(
    start: DrawPoint(x: startRect.centerX, y: startRect.centerY),
    end: DrawPoint(x: endRect.centerX, y: endRect.centerY),
    startBinding: ArrowBinding(elementId: startId, anchor: startAnchor),
    endBinding: ArrowBinding(elementId: endId, anchor: endAnchor),
    elementsById: {startId: startElement, endId: endElement},
    startArrowhead: _boundArrowhead,
    endArrowhead: _boundArrowhead,
  );
}

void main() {
  test('grid routing avoids obstacles and stays orthogonal', () {
    const rectA = DrawRect(minX: 100, minY: 100, maxX: 240, maxY: 240);
    const rectB = DrawRect(minX: 360, minY: 160, maxX: 500, maxY: 300);

    final result = _routeBoundToBound(
      startId: 'rect-a',
      startRect: rectA,
      startAnchor: const DrawPoint(x: 0, y: 0.5),
      endId: 'rect-b',
      endRect: rectB,
      endAnchor: const DrawPoint(x: 1, y: 0.5),
    );
    final points = result.points;

    expect(points.length, greaterThan(2));
    expect(elbowPathIsOrthogonal(points), isTrue);
    expect(elbowPathHasOnlyCorners(points), isTrue);
    expect(elbowPathIntersectsBounds(points, rectA), isFalse);
    expect(elbowPathIntersectsBounds(points, rectB), isFalse);
  });

  test('grid routing honors constrained start/end headings', () {
    const startRect = DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 220);
    const endRect = DrawRect(minX: 360, minY: 160, maxX: 480, maxY: 280);

    final result = _routeBoundToBound(
      startId: 'start',
      startRect: startRect,
      startAnchor: const DrawPoint(x: 0.5, y: 0),
      endId: 'end',
      endRect: endRect,
      endAnchor: const DrawPoint(x: 1, y: 0.5),
    );
    final points = result.points;

    expect(points.length, greaterThan(2));
    expect(elbowPathIsOrthogonal(points), isTrue);
    expect(elbowPathIntersectsBounds(points, startRect), isFalse);
    expect(elbowPathIntersectsBounds(points, endRect), isFalse);

    final startPoint = points.first;
    final nextPoint = points[1];
    expect(
      _closeTo(startPoint.x, nextPoint.x),
      isTrue,
      reason: 'Top binding should depart vertically.',
    );
    expect(
      nextPoint.y < startPoint.y,
      isTrue,
      reason: 'Top binding should depart upward.',
    );

    final penultimate = points[points.length - 2];
    final endPoint = points.last;
    expect(
      _closeTo(penultimate.y, endPoint.y),
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
