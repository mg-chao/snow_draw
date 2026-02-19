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
  final rect = DrawRect(
    minX: first.x <= second.x ? first.x : second.x,
    minY: first.y <= second.y ? first.y : second.y,
    maxX: first.x >= second.x ? first.x : second.x,
    maxY: first.y >= second.y ? first.y : second.y,
  );
  final width = rect.width;
  final height = rect.height;

  DrawPoint normalize(DrawPoint point) {
    final normalizedX = width == 0
        ? 0.0
        : _clamp01((point.x - rect.minX) / width);
    final normalizedY = height == 0
        ? 0.0
        : _clamp01((point.y - rect.minY) / height);
    return DrawPoint(x: normalizedX, y: normalizedY, pressure: point.pressure);
  }

  return ArrowTwoPointLayout(
    rect: rect,
    normalizedPoints: List<DrawPoint>.unmodifiable([
      normalize(first),
      normalize(second),
    ]),
  );
}

double _clamp01(double value) {
  if (!value.isFinite) {
    return 0;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}
