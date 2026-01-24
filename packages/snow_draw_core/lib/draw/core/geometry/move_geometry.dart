import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';

/// Pure move geometry helpers.
class MoveGeometry {
  const MoveGeometry._();

  static DrawPoint translatePoint(DrawPoint point, double dx, double dy) =>
      DrawPoint(x: point.x + dx, y: point.y + dy);

  static DrawRect translateRect(DrawRect rect, double dx, double dy) =>
      DrawRect(
        minX: rect.minX + dx,
        minY: rect.minY + dy,
        maxX: rect.maxX + dx,
        maxY: rect.maxY + dy,
      );

  static ({double dx, double dy}) calculateDisplacement(
    DrawPoint start,
    DrawPoint current,
  ) => (dx: current.x - start.x, dy: current.y - start.y);
}
