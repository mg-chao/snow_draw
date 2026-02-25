import 'dart:math' as math;

import 'package:snow_draw_engine/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';

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

bool elbowPointsClose(DrawPoint a, DrawPoint b, {double epsilon = 1e-3}) =>
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

/// Returns true when each interior point represents a direction change.
bool elbowPathHasOnlyCorners(
  List<DrawPoint> points, {
  double epsilon = ElbowConstants.dedupThreshold,
}) {
  if (points.length <= 2) {
    return true;
  }
  for (var i = 1; i < points.length - 1; i++) {
    final prev = points[i - 1];
    final current = points[i];
    final next = points[i + 1];
    final prevHorizontal = (prev.y - current.y).abs() <= epsilon;
    final nextHorizontal = (current.y - next.y).abs() <= epsilon;
    if (prevHorizontal == nextHorizontal) {
      return false;
    }
  }
  return true;
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
    if (x < bounds.minX - dedupThreshold || x > bounds.maxX + dedupThreshold) {
      return false;
    }

    return _rangesOverlap(
      segmentMin: math.min(start.y, end.y),
      segmentMax: math.max(start.y, end.y),
      boundsMin: bounds.minY,
      boundsMax: bounds.maxY,
      epsilon: epsilon,
    );
  }

  if (dy <= dedupThreshold) {
    final y = (start.y + end.y) / 2;
    if (y < bounds.minY - dedupThreshold || y > bounds.maxY + dedupThreshold) {
      return false;
    }

    return _rangesOverlap(
      segmentMin: math.min(start.x, end.x),
      segmentMax: math.max(start.x, end.x),
      boundsMin: bounds.minX,
      boundsMax: bounds.maxX,
      epsilon: epsilon,
    );
  }

  return false;
}

bool _rangesOverlap({
  required double segmentMin,
  required double segmentMax,
  required double boundsMin,
  required double boundsMax,
  required double epsilon,
}) {
  final overlapStart = math.max(segmentMin, boundsMin);
  final overlapEnd = math.min(segmentMax, boundsMax);
  return overlapEnd - overlapStart > epsilon;
}
