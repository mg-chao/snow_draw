import '../models/edit_enums.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';

/// Selection handle geometry calculator.
///
/// Centralizes:
/// - resize handle positions (corners + edges midpoints)
/// - rotate handle position
/// - hit testing for handle points
class HandleCalculator {
  HandleCalculator._();

  static const _resizeHitTestOrder = <ResizeMode>[
    ResizeMode.topLeft,
    ResizeMode.topRight,
    ResizeMode.bottomRight,
    ResizeMode.bottomLeft,
    ResizeMode.top,
    ResizeMode.right,
    ResizeMode.bottom,
    ResizeMode.left,
  ];

  // ===== Resize handles =====

  static DrawPoint getResizeHandlePosition({
    required DrawRect bounds,
    required ResizeMode mode,
    double padding = 0.0,
  }) {
    final minX = bounds.minX - padding;
    final minY = bounds.minY - padding;
    final maxX = bounds.maxX + padding;
    final maxY = bounds.maxY + padding;
    final centerX = bounds.centerX;
    final centerY = bounds.centerY;

    return switch (mode) {
      ResizeMode.topLeft => DrawPoint(x: minX, y: minY),
      ResizeMode.top => DrawPoint(x: centerX, y: minY),
      ResizeMode.topRight => DrawPoint(x: maxX, y: minY),
      ResizeMode.right => DrawPoint(x: maxX, y: centerY),
      ResizeMode.bottomRight => DrawPoint(x: maxX, y: maxY),
      ResizeMode.bottom => DrawPoint(x: centerX, y: maxY),
      ResizeMode.bottomLeft => DrawPoint(x: minX, y: maxY),
      ResizeMode.left => DrawPoint(x: minX, y: centerY),
    };
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
  }) => testPoint.distanceSquared(handleCenter) <= (tolerance * tolerance);

  /// Hit-tests all resize handles (corners + edge midpoints) in local space.
  static ResizeMode? hitTestResizeHandles({
    required DrawPoint testPoint,
    required DrawRect bounds,
    required double tolerance,
    double padding = 0.0,
  }) {
    for (final mode in _resizeHitTestOrder) {
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
