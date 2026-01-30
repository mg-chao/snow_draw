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
const double _intersectionEpsilon = 1e-6;

void main() {
  test('elbow routing avoids a bound rectangle when start aligns above', () {
    final rect = DrawRect(minX: 100, minY: 100, maxX: 500, maxY: 260);
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
      (penultimate.x - endPoint.x).abs() <= _intersectionEpsilon,
      isTrue,
      reason: 'Bottom binding should approach vertically.',
    );
    expect(
      penultimate.y > endPoint.y,
      isTrue,
      reason: 'Bottom binding should approach from below.',
    );
  });
}

ElementState _rectangleElement({
  required String id,
  required DrawRect rect,
  double strokeWidth = 2,
}) {
  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(strokeWidth: strokeWidth),
  );
}

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

bool _segmentIntersectsBounds(
  DrawPoint start,
  DrawPoint end,
  DrawRect bounds,
) {
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
