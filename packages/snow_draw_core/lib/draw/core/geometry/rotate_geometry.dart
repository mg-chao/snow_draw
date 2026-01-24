import 'dart:math' as math;

import '../../types/draw_point.dart';

/// Pure rotate geometry helpers.
class RotateGeometry {
  const RotateGeometry._();

  static double angleFromCenter(DrawPoint point, DrawPoint center) =>
      math.atan2(point.y - center.y, point.x - center.x);

  static double normalizeDelta(double delta) =>
      math.atan2(math.sin(delta), math.cos(delta));

  static double applyDiscreteSnap({
    required double delta,
    required double baseAngle,
    required double snapInterval,
  }) {
    if (snapInterval <= 0) {
      return delta;
    }
    final total = baseAngle + delta;
    final snappedTotal = (total / snapInterval).round() * snapInterval;
    return snappedTotal - baseAngle;
  }

  static DrawPoint rotatePoint({
    required DrawPoint point,
    required DrawPoint center,
    required double angle,
  }) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final dx = point.x - center.x;
    final dy = point.y - center.y;
    return DrawPoint(
      x: center.x + dx * cos - dy * sin,
      y: center.y + dx * sin + dy * cos,
    );
  }
}
