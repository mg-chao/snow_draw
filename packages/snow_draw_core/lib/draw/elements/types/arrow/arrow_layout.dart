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
}) {
  // For non-rotated elements, no transformation is needed.
  if (rotation == 0) {
    final rect = _calculatePathBounds(
      points: localPoints,
      arrowType: arrowType,
    );
    return ArrowRectAndPoints(rect: rect, localPoints: localPoints);
  }

  // Transform local-space points to world space using the old center.
  final oldSpace = ElementSpace(rotation: rotation, origin: oldRect.center);
  final worldPoints = localPoints.map(oldSpace.toWorld).toList(growable: false);

  // Rotate world points by -theta around the origin.
  final cosTheta = math.cos(rotation);
  final sinTheta = math.sin(rotation);
  final rotatedBounds = _calculatePathBounds(
    points: worldPoints
        .map(
          (point) => DrawPoint(
            x: point.x * cosTheta + point.y * sinTheta,
            y: -point.x * sinTheta + point.y * cosTheta,
          ),
        )
        .toList(growable: false),
    arrowType: arrowType,
  );
  final rotatedCenter = rotatedBounds.center;

  // Rotate the center back by theta to get the new local center.
  final newCenter = DrawPoint(
    x: rotatedCenter.x * cosTheta - rotatedCenter.y * sinTheta,
    y: rotatedCenter.x * sinTheta + rotatedCenter.y * cosTheta,
  );

  // Transform world points to local space using the new center.
  final newSpace = ElementSpace(rotation: rotation, origin: newCenter);
  final newLocalPoints = worldPoints
      .map(newSpace.fromWorld)
      .toList(growable: false);

  final newRect = _calculatePathBounds(
    points: newLocalPoints,
    arrowType: arrowType,
  );

  return ArrowRectAndPoints(rect: newRect, localPoints: newLocalPoints);
}

DrawRect _calculatePathBounds({
  required List<DrawPoint> points,
  required ArrowType arrowType,
}) => ArrowGeometry.calculatePathBounds(
  worldPoints: points,
  arrowType: arrowType,
);
