import '../../types/draw_point.dart';

/// Returns whether movement from [from] to [to] reaches [threshold].
///
/// Non-positive thresholds are treated as immediate drag start.
bool hasReachedDragThreshold({
  required DrawPoint from,
  required DrawPoint to,
  required double threshold,
}) {
  if (threshold <= 0) {
    return true;
  }
  final thresholdSquared = threshold * threshold;
  return from.distanceSquared(to) >= thresholdSquared;
}
