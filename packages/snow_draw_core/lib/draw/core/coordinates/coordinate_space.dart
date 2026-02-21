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
    return _rotate(localVector.x, localVector.y, rotation);
  }

  DrawPoint rotateVectorToLocal(DrawPoint worldVector) {
    if (rotation == 0) {
      return worldVector;
    }
    return _rotate(worldVector.x, worldVector.y, -rotation);
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
    final rotated = _rotate(point.x - center.x, point.y - center.y, angle);
    return DrawPoint(x: center.x + rotated.x, y: center.y + rotated.y);
  }

  DrawPoint _rotate(double x, double y, double angle) {
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    return DrawPoint(x: x * cosA - y * sinA, y: x * sinA + y * cosA);
  }
}
