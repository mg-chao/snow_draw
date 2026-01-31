import 'package:meta/meta.dart';

import '../../../../types/draw_point.dart';
import '../../../../types/draw_rect.dart';
import 'elbow_heading.dart';

/// Shared geometry helpers for elbow routing and editing.
@internal
final class ElbowGeometry {
  const ElbowGeometry._();

  static const double _headingEpsilon = 1e-6;

  /// Determines which side of the bounds a point belongs to, using
  /// a scaled-triangle quadrant test around the center.
  static ElbowHeading headingForPointOnBounds(
    DrawRect bounds,
    DrawPoint point,
  ) {
    final center = bounds.center;
    const scale = 2.0;
    final topLeft = _scalePointFromOrigin(
      DrawPoint(x: bounds.minX, y: bounds.minY),
      center,
      scale,
    );
    final topRight = _scalePointFromOrigin(
      DrawPoint(x: bounds.maxX, y: bounds.minY),
      center,
      scale,
    );
    final bottomLeft = _scalePointFromOrigin(
      DrawPoint(x: bounds.minX, y: bounds.maxY),
      center,
      scale,
    );
    final bottomRight = _scalePointFromOrigin(
      DrawPoint(x: bounds.maxX, y: bounds.maxY),
      center,
      scale,
    );

    if (_triangleContainsPoint(topLeft, topRight, center, point)) {
      return ElbowHeading.up;
    }
    if (_triangleContainsPoint(topRight, bottomRight, center, point)) {
      return ElbowHeading.right;
    }
    if (_triangleContainsPoint(bottomRight, bottomLeft, center, point)) {
      return ElbowHeading.down;
    }
    return ElbowHeading.left;
  }

  static DrawPoint _scalePointFromOrigin(
    DrawPoint point,
    DrawPoint origin,
    double scale,
  ) => DrawPoint(
    x: origin.x + (point.x - origin.x) * scale,
    y: origin.y + (point.y - origin.y) * scale,
  );

  static DrawPoint _vectorFromPoints(DrawPoint to, DrawPoint from) =>
      DrawPoint(x: to.x - from.x, y: to.y - from.y);

  static double _dotProduct(DrawPoint a, DrawPoint b) => a.x * b.x + a.y * b.y;

  static bool _triangleContainsPoint(
    DrawPoint a,
    DrawPoint b,
    DrawPoint c,
    DrawPoint point,
  ) {
    final v0 = _vectorFromPoints(c, a);
    final v1 = _vectorFromPoints(b, a);
    final v2 = _vectorFromPoints(point, a);

    final dot00 = _dotProduct(v0, v0);
    final dot01 = _dotProduct(v0, v1);
    final dot02 = _dotProduct(v0, v2);
    final dot11 = _dotProduct(v1, v1);
    final dot12 = _dotProduct(v1, v2);

    final denom = dot00 * dot11 - dot01 * dot01;
    if (denom.abs() <= _headingEpsilon) {
      return false;
    }
    final invDenom = 1 / denom;
    final u = (dot11 * dot02 - dot01 * dot12) * invDenom;
    final v = (dot00 * dot12 - dot01 * dot02) * invDenom;

    return u >= -_headingEpsilon &&
        v >= -_headingEpsilon &&
        u + v <= 1 + _headingEpsilon;
  }
}
