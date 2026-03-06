import 'arrow_types.dart';

ResizeArrowDirection getResizeArrowDirection(
  ResizeHandleDirection transformHandleType,
  List<Point> points,
) {
  final secondPoint = points.length > 1 ? points[1] : null;
  if (secondPoint == null) {
    return 'origin';
  }

  final px = secondPoint[0];
  final py = secondPoint[1];
  final handle = transformHandleType;
  final isResizeEnd =
      (handle == 'nw' && (px < 0 || py < 0)) ||
      (handle == 'ne' && px >= 0) ||
      (handle == 'sw' && px <= 0) ||
      (handle == 'se' && (px > 0 || py > 0));

  return isResizeEnd ? 'end' : 'origin';
}
