import 'dart:math' as math;

import '../../types/draw_point.dart';

/// A coordinate space that can convert points to/from world coordinates.
///
/// This is primarily used for edit operations where we need to reason about a
/// rotated overlay (multi-select) or a rotated element.
abstract class CoordinateSpace {
  const CoordinateSpace();

  double get rotation;
  DrawPoint get origin;

  DrawPoint fromWorld(DrawPoint worldPoint);
  DrawPoint toWorld(DrawPoint localPoint);

  DrawPoint rotateVectorToWorld(DrawPoint localVector) {
    if (rotation == 0) {
      return localVector;
    }
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);
    return DrawPoint(
      x: localVector.x * cosR - localVector.y * sinR,
      y: localVector.x * sinR + localVector.y * cosR,
    );
  }

  DrawPoint rotateVectorToLocal(DrawPoint worldVector) {
    if (rotation == 0) {
      return worldVector;
    }
    final cosR = math.cos(-rotation);
    final sinR = math.sin(-rotation);
    return DrawPoint(
      x: worldVector.x * cosR - worldVector.y * sinR,
      y: worldVector.x * sinR + worldVector.y * cosR,
    );
  }

  /// Rotates [point] around [center] by [angle].
  DrawPoint rotatePoint({
    required DrawPoint point,
    required DrawPoint center,
    required double angle,
  }) {
    if (angle == 0) {
      return point;
    }

    final cosA = math.cos(angle);
    final sinA = math.sin(angle);

    final dx = point.x - center.x;
    final dy = point.y - center.y;

    return DrawPoint(
      x: center.x + dx * cosA - dy * sinA,
      y: center.y + dx * sinA + dy * cosA,
    );
  }
}
