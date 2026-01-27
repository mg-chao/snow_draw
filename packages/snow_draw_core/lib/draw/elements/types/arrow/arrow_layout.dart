import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../core/coordinates/element_space.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import 'arrow_geometry.dart';

/// Result of computing the new rect and adjusted local points.
@immutable
final class ArrowRectAndPoints {
  const ArrowRectAndPoints({required this.rect, required this.localPoints});

  final DrawRect rect;
  final List<DrawPoint> localPoints;
}

/// Computes the new rect and transforms points to preserve world-space
/// positions.
///
/// When a control point is dragged outside the current bounding rect, the rect
/// must be recalculated. If the element is rotated, simply recalculating the
/// rect would change the rotation pivot (rect center), causing other points to
/// shift in world space.
///
/// This function finds the optimal rect center C such that when world points
/// are transformed to local space using C, the bounding box of local points has
/// center C. This ensures all points maintain their world-space positions.
ArrowRectAndPoints computeArrowRectAndPoints({
  required List<DrawPoint> localPoints,
  required DrawRect oldRect,
  required double rotation,
  required ArrowType arrowType,
  required double strokeWidth,
}) {
  // For non-rotated elements, no transformation needed.
  if (rotation == 0) {
    final rect = _calculateArrowRect(
      points: localPoints,
      arrowType: arrowType,
      strokeWidth: strokeWidth,
    );
    return ArrowRectAndPoints(rect: rect, localPoints: localPoints);
  }

  // Step 1: Transform local-space points to world space using the old rect
  // center.
  final oldSpace = ElementSpace(rotation: rotation, origin: oldRect.center);
  final worldPoints = localPoints.map(oldSpace.toWorld).toList(growable: false);

  // Step 2: Rotate world points by -theta around the origin.
  final cosTheta = math.cos(rotation);
  final sinTheta = math.sin(rotation);
  final rotatedPoints = worldPoints
      .map(
        (w) => DrawPoint(
          x: w.x * cosTheta + w.y * sinTheta,
          y: -w.x * sinTheta + w.y * cosTheta,
        ),
      )
      .toList(growable: false);

  // Step 3: Calculate the bounding box of rotated points.
  var minX = rotatedPoints.first.x;
  var maxX = rotatedPoints.first.x;
  var minY = rotatedPoints.first.y;
  var maxY = rotatedPoints.first.y;
  for (final p in rotatedPoints.skip(1)) {
    if (p.x < minX) {
      minX = p.x;
    }
    if (p.x > maxX) {
      maxX = p.x;
    }
    if (p.y < minY) {
      minY = p.y;
    }
    if (p.y > maxY) {
      maxY = p.y;
    }
  }
  final rotatedCenterX = (minX + maxX) / 2;
  final rotatedCenterY = (minY + maxY) / 2;

  // Step 4: The new rect center is the rotated center rotated back by theta.
  final newCenterX = rotatedCenterX * cosTheta - rotatedCenterY * sinTheta;
  final newCenterY = rotatedCenterX * sinTheta + rotatedCenterY * cosTheta;
  final newCenter = DrawPoint(x: newCenterX, y: newCenterY);

  // Step 5: Transform world points to local space using the new center.
  final newSpace = ElementSpace(rotation: rotation, origin: newCenter);
  final newLocalPoints = worldPoints
      .map(newSpace.fromWorld)
      .toList(growable: false);

  // Step 6: Calculate the rect from local points.
  final rect = _calculateArrowRect(
    points: newLocalPoints,
    arrowType: arrowType,
    strokeWidth: strokeWidth,
  );

  return ArrowRectAndPoints(rect: rect, localPoints: newLocalPoints);
}

DrawRect _calculateArrowRect({
  required List<DrawPoint> points,
  required ArrowType arrowType,
  required double strokeWidth,
}) => ArrowGeometry.calculatePathBounds(
  worldPoints: points,
  arrowType: arrowType,
);
