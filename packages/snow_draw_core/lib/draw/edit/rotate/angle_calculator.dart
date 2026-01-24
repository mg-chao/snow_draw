import '../../core/geometry/rotate_geometry.dart';
import '../../types/draw_point.dart';

class AngleCalculator {
  AngleCalculator._();

  static double rawAngle({
    required DrawPoint currentPosition,
    required DrawPoint center,
  }) => RotateGeometry.angleFromCenter(currentPosition, center);

  /// Normalizes an angle delta to [-pi, pi].
  static double normalizeDelta(double delta) =>
      RotateGeometry.normalizeDelta(delta);

  /// Snaps a total angle (base + delta) to the nearest interval and returns
  /// the snapped delta.
  static double applyDiscreteSnap({
    required double delta,
    required double baseAngle,
    required double snapInterval,
  }) => RotateGeometry.applyDiscreteSnap(
    delta: delta,
    baseAngle: baseAngle,
    snapInterval: snapInterval,
  );
}
