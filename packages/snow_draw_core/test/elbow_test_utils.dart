import 'dart:math' as math;

import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

ElementState elbowRectangleElement({
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

DrawRect elbowRectForPoints(List<DrawPoint> points) {
  var minX = points.first.x;
  var maxX = points.first.x;
  var minY = points.first.y;
  var maxY = points.first.y;
  for (final point in points.skip(1)) {
    minX = math.min(minX, point.x);
    maxX = math.max(maxX, point.x);
    minY = math.min(minY, point.y);
    maxY = math.max(maxY, point.y);
  }
  if (minX == maxX) {
    maxX = minX + 1;
  }
  if (minY == maxY) {
    maxY = minY + 1;
  }
  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

bool elbowPointsClose(
  DrawPoint a,
  DrawPoint b, {
  double epsilon = 1e-3,
}) =>
    (a.x - b.x).abs() <= epsilon && (a.y - b.y).abs() <= epsilon;

bool elbowPathIsOrthogonal(
  List<DrawPoint> points, {
  double epsilon = ElbowConstants.intersectionEpsilon,
}) {
  for (var i = 0; i < points.length - 1; i++) {
    final dx = (points[i].x - points[i + 1].x).abs();
    final dy = (points[i].y - points[i + 1].y).abs();
    if (dx > epsilon && dy > epsilon) {
      return false;
    }
  }
  return true;
}

bool elbowPathIntersectsBounds(
  List<DrawPoint> points,
  DrawRect bounds, {
  double epsilon = ElbowConstants.intersectionEpsilon,
  double dedupThreshold = ElbowConstants.dedupThreshold,
}) {
  for (var i = 0; i < points.length - 1; i++) {
    if (elbowSegmentIntersectsBounds(
      points[i],
      points[i + 1],
      bounds,
      epsilon: epsilon,
      dedupThreshold: dedupThreshold,
    )) {
      return true;
    }
  }
  return false;
}

bool elbowSegmentIntersectsBounds(
  DrawPoint start,
  DrawPoint end,
  DrawRect bounds, {
  double epsilon = ElbowConstants.intersectionEpsilon,
  double dedupThreshold = ElbowConstants.dedupThreshold,
}) {
  final dx = (start.x - end.x).abs();
  final dy = (start.y - end.y).abs();
  if (dx <= dedupThreshold) {
    final x = (start.x + end.x) / 2;
    if (x < bounds.minX - dedupThreshold ||
        x > bounds.maxX + dedupThreshold) {
      return false;
    }
    final minY = math.min(start.y, end.y);
    final maxY = math.max(start.y, end.y);
    final overlapStart = math.max(minY, bounds.minY);
    final overlapEnd = math.min(maxY, bounds.maxY);
    return overlapEnd - overlapStart > epsilon;
  }
  if (dy <= dedupThreshold) {
    final y = (start.y + end.y) / 2;
    if (y < bounds.minY - dedupThreshold ||
        y > bounds.maxY + dedupThreshold) {
      return false;
    }
    final minX = math.min(start.x, end.x);
    final maxX = math.max(start.x, end.x);
    final overlapStart = math.max(minX, bounds.minX);
    final overlapEnd = math.min(maxX, bounds.maxX);
    return overlapEnd - overlapStart > epsilon;
  }

  final minX = math.min(start.x, end.x);
  final maxX = math.max(start.x, end.x);
  final minY = math.min(start.y, end.y);
  final maxY = math.max(start.y, end.y);
  if (maxX < bounds.minX - dedupThreshold ||
      minX > bounds.maxX + dedupThreshold ||
      maxY < bounds.minY - dedupThreshold ||
      minY > bounds.maxY + dedupThreshold) {
    return false;
  }
  return true;
}
