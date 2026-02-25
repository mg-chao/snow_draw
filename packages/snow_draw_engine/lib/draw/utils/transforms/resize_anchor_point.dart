import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/resize_mode.dart';

/// Returns the opposite anchor point for a given resize handle [mode].
///
/// The returned point is in the same coordinate space as [rect] (typically the
/// selection overlay's un-rotated local frame).
DrawPoint oppositeBoundPointLocal(DrawRect rect, ResizeMode mode) =>
    switch (mode) {
      ResizeMode.topLeft => DrawPoint(x: rect.maxX, y: rect.maxY),
      ResizeMode.topRight => DrawPoint(x: rect.minX, y: rect.maxY),
      ResizeMode.bottomRight => DrawPoint(x: rect.minX, y: rect.minY),
      ResizeMode.bottomLeft => DrawPoint(x: rect.maxX, y: rect.minY),
      ResizeMode.top => DrawPoint(x: rect.centerX, y: rect.maxY),
      ResizeMode.bottom => DrawPoint(x: rect.centerX, y: rect.minY),
      ResizeMode.left => DrawPoint(x: rect.maxX, y: rect.centerY),
      ResizeMode.right => DrawPoint(x: rect.minX, y: rect.centerY),
    };
