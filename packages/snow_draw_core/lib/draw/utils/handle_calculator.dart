import '../models/edit_enums.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';

/// Selection handle geometry calculator.
///
/// Centralizes:
/// - resize handle positions (corners + edges midpoints)
/// - rotate handle position
/// - coordinate transforms for rotated selections (world <-> local)
/// - hit testing for handle points
class HandleCalculator {
  HandleCalculator._();

  // ===== Resize handles =====

  static DrawPoint getResizeHandlePosition({
    required DrawRect bounds,
    required ResizeMode mode,
    double padding = 0.0,
  }) {
    final paddedMinX = bounds.minX - padding;
    final paddedMinY = bounds.minY - padding;
    final paddedMaxX = bounds.maxX + padding;
    final paddedMaxY = bounds.maxY + padding;

    switch (mode) {
      case ResizeMode.topLeft:
        return DrawPoint(x: paddedMinX, y: paddedMinY);
      case ResizeMode.top:
        return DrawPoint(x: bounds.centerX, y: paddedMinY);
      case ResizeMode.topRight:
        return DrawPoint(x: paddedMaxX, y: paddedMinY);
      case ResizeMode.right:
        return DrawPoint(x: paddedMaxX, y: bounds.centerY);
      case ResizeMode.bottomRight:
        return DrawPoint(x: paddedMaxX, y: paddedMaxY);
      case ResizeMode.bottom:
        return DrawPoint(x: bounds.centerX, y: paddedMaxY);
      case ResizeMode.bottomLeft:
        return DrawPoint(x: paddedMinX, y: paddedMaxY);
      case ResizeMode.left:
        return DrawPoint(x: paddedMinX, y: bounds.centerY);
    }
  }

  static Map<ResizeMode, DrawPoint> getAllResizeHandlePositions({
    required DrawRect bounds,
    double padding = 0.0,
  }) => {
    for (final mode in ResizeMode.values)
      mode: getResizeHandlePosition(
        bounds: bounds,
        mode: mode,
        padding: padding,
      ),
  };

  // ===== Rotate handle =====

  static DrawPoint getRotateHandlePosition({
    required DrawRect bounds,
    required double margin,
    double padding = 0.0,
  }) => DrawPoint(x: bounds.centerX, y: bounds.minY - padding - margin);

  // ===== Hit testing =====

  static bool isPointInHandle({
    required DrawPoint testPoint,
    required DrawPoint handleCenter,
    required double tolerance,
  }) {
    final dx = testPoint.x - handleCenter.x;
    final dy = testPoint.y - handleCenter.y;
    return (dx * dx + dy * dy) <= (tolerance * tolerance);
  }

  /// Hit-tests all resize handles (corners + edge midpoints) in local space.
  static ResizeMode? hitTestResizeHandles({
    required DrawPoint testPoint,
    required DrawRect bounds,
    required double tolerance,
    double padding = 0.0,
  }) {
    // Prefer corners first (more precise targets).
    const cornerOrder = <ResizeMode>[
      ResizeMode.topLeft,
      ResizeMode.topRight,
      ResizeMode.bottomRight,
      ResizeMode.bottomLeft,
    ];
    for (final mode in cornerOrder) {
      final handle = getResizeHandlePosition(
        bounds: bounds,
        mode: mode,
        padding: padding,
      );
      if (isPointInHandle(
        testPoint: testPoint,
        handleCenter: handle,
        tolerance: tolerance,
      )) {
        return mode;
      }
    }

    // Then edge midpoints.
    const edgeOrder = <ResizeMode>[
      ResizeMode.top,
      ResizeMode.right,
      ResizeMode.bottom,
      ResizeMode.left,
    ];
    for (final mode in edgeOrder) {
      final handle = getResizeHandlePosition(
        bounds: bounds,
        mode: mode,
        padding: padding,
      );
      if (isPointInHandle(
        testPoint: testPoint,
        handleCenter: handle,
        tolerance: tolerance,
      )) {
        return mode;
      }
    }

    return null;
  }
}
