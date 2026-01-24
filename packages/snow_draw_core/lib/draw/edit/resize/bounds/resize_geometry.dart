import '../../../models/edit_enums.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';

/// Returns the opposite anchor point for a given resize handle [mode].
///
/// The returned point is in the same coordinate space as [rect] (typically the
/// selection overlay's un-rotated local frame).
DrawPoint oppositeBoundPointLocal(DrawRect rect, ResizeMode mode) {
  switch (mode) {
    case ResizeMode.topLeft:
      return DrawPoint(x: rect.maxX, y: rect.maxY);
    case ResizeMode.topRight:
      return DrawPoint(x: rect.minX, y: rect.maxY);
    case ResizeMode.bottomRight:
      return DrawPoint(x: rect.minX, y: rect.minY);
    case ResizeMode.bottomLeft:
      return DrawPoint(x: rect.maxX, y: rect.minY);
    case ResizeMode.top:
      return DrawPoint(x: rect.centerX, y: rect.maxY);
    case ResizeMode.bottom:
      return DrawPoint(x: rect.centerX, y: rect.minY);
    case ResizeMode.left:
      return DrawPoint(x: rect.maxX, y: rect.centerY);
    case ResizeMode.right:
      return DrawPoint(x: rect.minX, y: rect.centerY);
  }
}
