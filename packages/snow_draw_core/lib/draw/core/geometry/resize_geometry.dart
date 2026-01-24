import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';

/// Pure resize geometry helpers.
class ResizeGeometry {
  const ResizeGeometry._();

  static ({double scaleX, double scaleY}) calculateScale({
    required DrawRect original,
    required DrawRect scaled,
    bool flipX = false,
    bool flipY = false,
  }) {
    if (original.width == 0 || original.height == 0) {
      return (scaleX: 1.0, scaleY: 1.0);
    }

    return (
      scaleX: (scaled.width / original.width) * (flipX ? -1.0 : 1.0),
      scaleY: (scaled.height / original.height) * (flipY ? -1.0 : 1.0),
    );
  }

  static DrawRect scaleRectFromAnchor({
    required DrawRect rect,
    required DrawPoint anchor,
    required double scaleX,
    required double scaleY,
  }) {
    final relMinX = rect.minX - anchor.x;
    final relMinY = rect.minY - anchor.y;
    final relMaxX = rect.maxX - anchor.x;
    final relMaxY = rect.maxY - anchor.y;

    return DrawRect(
      minX: anchor.x + relMinX * scaleX,
      minY: anchor.y + relMinY * scaleY,
      maxX: anchor.x + relMaxX * scaleX,
      maxY: anchor.y + relMaxY * scaleY,
    );
  }

  static DrawPoint getOppositeAnchor(DrawRect rect, ResizeHandle handle) =>
      switch (handle) {
        ResizeHandle.topLeft => DrawPoint(x: rect.maxX, y: rect.maxY),
        ResizeHandle.topRight => DrawPoint(x: rect.minX, y: rect.maxY),
        ResizeHandle.bottomLeft => DrawPoint(x: rect.maxX, y: rect.minY),
        ResizeHandle.bottomRight => DrawPoint(x: rect.minX, y: rect.minY),
        ResizeHandle.top => DrawPoint(x: rect.center.x, y: rect.maxY),
        ResizeHandle.bottom => DrawPoint(x: rect.center.x, y: rect.minY),
        ResizeHandle.left => DrawPoint(x: rect.maxX, y: rect.center.y),
        ResizeHandle.right => DrawPoint(x: rect.minX, y: rect.center.y),
      };
}

enum ResizeHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}
