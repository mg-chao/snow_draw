import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';

/// Cached layout payload for 2-point arrow-like elements.
///
/// The rect is in world space and [normalizedPoints] are rect-normalized.
class ArrowTwoPointLayout {
  const ArrowTwoPointLayout({
    required this.rect,
    required this.normalizedPoints,
  });

  final DrawRect rect;
  final List<DrawPoint> normalizedPoints;
}

/// Computes rect + normalized points for a 2-point arrow fast path.
///
/// This avoids the generic multi-point path bounds/normalization pipeline
/// during high-frequency create/edit updates.
ArrowTwoPointLayout computeArrowTwoPointLayout({
  required DrawPoint first,
  required DrawPoint second,
}) {
  final rect = first.toRect(second);
  final width = rect.width;
  final height = rect.height;

  double normalizeX(double x) => width == 0 ? 0.0 : (x - rect.minX) / width;
  double normalizeY(double y) => height == 0 ? 0.0 : (y - rect.minY) / height;

  return ArrowTwoPointLayout(
    rect: rect,
    normalizedPoints: List<DrawPoint>.unmodifiable([
      DrawPoint(
        x: normalizeX(first.x),
        y: normalizeY(first.y),
        pressure: first.pressure,
      ),
      DrawPoint(
        x: normalizeX(second.x),
        y: normalizeY(second.y),
        pressure: second.pressure,
      ),
    ]),
  );
}
