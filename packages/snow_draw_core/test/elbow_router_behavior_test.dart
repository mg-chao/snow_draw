import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

const double _dedupThreshold = 1;
const _intersectionEpsilon = 1e-6;

void main() {
  test('elbow routing fallback uses a midpoint elbow for unbound endpoints', () {
    const start = DrawPoint(x: 0, y: 0);
    const end = DrawPoint(x: 100, y: 50);

    final result = routeElbowArrow(
      start: start,
      end: end,
      elementsById: const {},
    );

    expect(result.points.length, 4);
    expect(result.points.first, start);
    expect(result.points.last, end);
    expect(result.points[1], const DrawPoint(x: 50, y: 0));
    expect(result.points[2], const DrawPoint(x: 50, y: 50));
    expect(_pathIsOrthogonal(result.points), isTrue);
  });

  test('elbow routing fallback is direct when aligned', () {
    const start = DrawPoint(x: 10, y: 10);
    const end = DrawPoint(x: 10, y: 110);

    final result = routeElbowArrow(
      start: start,
      end: end,
      elementsById: const {},
    );

    expect(result.points, [start, end]);
    expect(_pathIsOrthogonal(result.points), isTrue);
  });

  test('elbow routing respects a bound start heading', () {
    const rect = DrawRect(minX: 100, minY: 100, maxX: 300, maxY: 200);
    final element = _rectangleElement(id: 'rect-1', rect: rect);

    final result = routeElbowArrow(
      start: const DrawPoint(x: 0, y: 0),
      end: DrawPoint(x: rect.centerX, y: rect.maxY + 200),
      startBinding: const ArrowBinding(
        elementId: 'rect-1',
        anchor: DrawPoint(x: 0.5, y: 0),
      ),
      elementsById: {'rect-1': element},
      startArrowhead: ArrowheadStyle.triangle,
    );

    expect(_pathIntersectsBounds(result.points, rect), isFalse);
    expect(_pathIsOrthogonal(result.points), isTrue);

    final startPoint = result.points.first;
    final nextPoint = result.points[1];
    expect(
      (startPoint.x - nextPoint.x).abs() <= _intersectionEpsilon,
      isTrue,
      reason: 'Top binding should depart vertically.',
    );
    expect(
      nextPoint.y < startPoint.y,
      isTrue,
      reason: 'Top binding should depart upward.',
    );
  });

  test('elbow routing avoids multiple bound rectangles', () {
    const rectA = DrawRect(minX: 100, minY: 100, maxX: 240, maxY: 220);
    const rectB = DrawRect(minX: 340, minY: 140, maxX: 480, maxY: 260);
    final elementA = _rectangleElement(id: 'rect-a', rect: rectA);
    final elementB = _rectangleElement(id: 'rect-b', rect: rectB);

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
      elementsById: {
        'rect-a': elementA,
        'rect-b': elementB,
      },
      startArrowhead: ArrowheadStyle.triangle,
      endArrowhead: ArrowheadStyle.triangle,
    );

    expect(_pathIntersectsBounds(result.points, rectA), isFalse);
    expect(_pathIntersectsBounds(result.points, rectB), isFalse);
    expect(_pathIsOrthogonal(result.points), isTrue);
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
    if (dx > _intersectionEpsilon && dy > _intersectionEpsilon) {
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
  if (dx <= _dedupThreshold) {
    final x = (start.x + end.x) / 2;
    if (x < bounds.minX - _dedupThreshold ||
        x > bounds.maxX + _dedupThreshold) {
      return false;
    }
    final minY = math.min(start.y, end.y);
    final maxY = math.max(start.y, end.y);
    final overlapStart = math.max(minY, bounds.minY);
    final overlapEnd = math.min(maxY, bounds.maxY);
    return overlapEnd - overlapStart > _intersectionEpsilon;
  }
  if (dy <= _dedupThreshold) {
    final y = (start.y + end.y) / 2;
    if (y < bounds.minY - _dedupThreshold ||
        y > bounds.maxY + _dedupThreshold) {
      return false;
    }
    final minX = math.min(start.x, end.x);
    final maxX = math.max(start.x, end.x);
    final overlapStart = math.max(minX, bounds.minX);
    final overlapEnd = math.min(maxX, bounds.maxX);
    return overlapEnd - overlapStart > _intersectionEpsilon;
  }

  final minX = math.min(start.x, end.x);
  final maxX = math.max(start.x, end.x);
  final minY = math.min(start.y, end.y);
  final maxY = math.max(start.y, end.y);
  if (maxX < bounds.minX - _dedupThreshold ||
      minX > bounds.maxX + _dedupThreshold ||
      maxY < bounds.minY - _dedupThreshold ||
      minY > bounds.maxY + _dedupThreshold) {
    return false;
  }
  return true;
}
