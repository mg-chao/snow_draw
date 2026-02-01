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
  test('elbow routing avoids a bound rectangle when start aligns above', () {
    const rect = DrawRect(minX: 100, minY: 100, maxX: 500, maxY: 260);
    final element = _rectangleElement(id: 'rect-1', rect: rect);
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
      _pathIntersectsBounds(result.points, rect),
      isFalse,
      reason: 'Route should not pass through the bound rectangle.',
    );
    expect(
      result.points.length,
      greaterThan(2),
      reason: 'Expected at least one bend to route around the rectangle.',
    );
    expect(
      _pathIsOrthogonal(result.points),
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
    final element = _rectangleElement(id: 'rect-1', rect: rect);
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
      _pathIntersectsBounds(result.points, rect),
      isFalse,
      reason: 'Route should not pass through the bound rectangle.',
    );
    expect(
      _pathIsOrthogonal(result.points),
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
    final element = _rectangleElement(id: 'rect-1', rect: rect);
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
      _pathIntersectsBounds(result.points, rect),
      isFalse,
      reason: 'Route should not pass through the bound rectangle.',
    );
    expect(
      _pathIsOrthogonal(result.points),
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
    final element = _rectangleElement(id: 'rect-1', rect: rect);
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
      _pathIntersectsBounds(result.points, rect),
      isFalse,
      reason: 'Route should not pass through the bound rectangle.',
    );
    expect(
      _pathIsOrthogonal(result.points),
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
