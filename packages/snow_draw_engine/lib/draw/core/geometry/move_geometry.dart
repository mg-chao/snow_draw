import '../../types/draw_point.dart';

/// Pure move geometry helpers.
class MoveGeometry {
  const MoveGeometry._();

  static ({double dx, double dy}) calculateDisplacement(
    DrawPoint start,
    DrawPoint current,
  ) => (dx: current.x - start.x, dy: current.y - start.y);
}
