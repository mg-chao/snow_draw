import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('grid routing avoids obstacles and stays orthogonal', () {
    const rectA = DrawRect(minX: 100, minY: 100, maxX: 240, maxY: 240);
    const rectB = DrawRect(minX: 360, minY: 160, maxX: 500, maxY: 300);
    final elementA = _rectangleElement(id: 'rect-a', rect: rectA);
    final elementB = _rectangleElement(id: 'rect-b', rect: rectB);

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
    expect(_pathIsOrthogonal(result.points), isTrue);
    expect(_pathIntersectsBounds(result.points, rectA), isFalse);
    expect(_pathIntersectsBounds(result.points, rectB), isFalse);
  });

  test('grid routing honors constrained start/end headings', () {
    const startRect = DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 220);
    const endRect = DrawRect(minX: 360, minY: 160, maxX: 480, maxY: 280);
    final startElement = _rectangleElement(id: 'start', rect: startRect);
    final endElement = _rectangleElement(id: 'end', rect: endRect);

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
    expect(_pathIsOrthogonal(result.points), isTrue);
    expect(_pathIntersectsBounds(result.points, startRect), isFalse);
    expect(_pathIntersectsBounds(result.points, endRect), isFalse);

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

ElementState _rectangleElement({
  required String id,
  required DrawRect rect,
  double strokeWidth = 2,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: RectangleData(strokeWidth: strokeWidth),
);

bool _pathIsOrthogonal(List<DrawPoint> points) {
  for (var i = 0; i < points.length - 1; i++) {
    final dx = (points[i].x - points[i + 1].x).abs();
    final dy = (points[i].y - points[i + 1].y).abs();
    if (dx > ElbowConstants.intersectionEpsilon && dy > ElbowConstants.intersectionEpsilon) {
      return false;
    }
  }
  return true;
}

bool _pathIntersectsBounds(List<DrawPoint> points, DrawRect bounds) {
  for (var i = 0; i < points.length - 1; i++) {
    if (_segmentIntersectsBounds(points[i], points[i + 1], bounds)) {
      return true;
    }
  }
  return false;
}

bool _segmentIntersectsBounds(DrawPoint start, DrawPoint end, DrawRect bounds) {
  final dx = (start.x - end.x).abs();
  final dy = (start.y - end.y).abs();
  if (dx <= ElbowConstants.dedupThreshold) {
    final x = (start.x + end.x) / 2;
    if (x < bounds.minX - ElbowConstants.dedupThreshold ||
        x > bounds.maxX + ElbowConstants.dedupThreshold) {
      return false;
    }
    final minY = math.min(start.y, end.y);
    final maxY = math.max(start.y, end.y);
    final overlapStart = math.max(minY, bounds.minY);
    final overlapEnd = math.min(maxY, bounds.maxY);
    return overlapEnd - overlapStart > ElbowConstants.intersectionEpsilon;
  }
  if (dy <= ElbowConstants.dedupThreshold) {
    final y = (start.y + end.y) / 2;
    if (y < bounds.minY - ElbowConstants.dedupThreshold ||
        y > bounds.maxY + ElbowConstants.dedupThreshold) {
      return false;
    }
    final minX = math.min(start.x, end.x);
    final maxX = math.max(start.x, end.x);
    final overlapStart = math.max(minX, bounds.minX);
    final overlapEnd = math.min(maxX, bounds.maxX);
    return overlapEnd - overlapStart > ElbowConstants.intersectionEpsilon;
  }

  final minX = math.min(start.x, end.x);
  final maxX = math.max(start.x, end.x);
  final minY = math.min(start.y, end.y);
  final maxY = math.max(start.y, end.y);
  if (maxX < bounds.minX - ElbowConstants.dedupThreshold ||
      minX > bounds.maxX + ElbowConstants.dedupThreshold ||
      maxY < bounds.minY - ElbowConstants.dedupThreshold ||
      minY > bounds.maxY + ElbowConstants.dedupThreshold) {
    return false;
  }
  return true;
}
