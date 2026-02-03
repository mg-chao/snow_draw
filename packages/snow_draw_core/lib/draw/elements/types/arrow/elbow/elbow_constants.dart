/// Centralized constants for elbow routing + editing.
///
/// These values are intentionally shared so routing and editing maintain the
/// same geometric tolerances and padding behavior.
final class ElbowConstants {
  const ElbowConstants._();

  /// Threshold for treating coordinates as aligned or duplicate.
  static const double dedupThreshold = 1;

  /// Epsilon used when testing segment intersections with obstacle bounds.
  static const intersectionEpsilon = 1e-6;

  /// Minimum Manhattan distance before a stable midpoint elbow is used.
  static const double minArrowLength = 8;

  /// Clamp for route coordinates to prevent runaway values.
  static const double maxPosition = 1000000;

  /// Base padding applied around obstacle bounds.
  static const double basePadding = 42;

  /// Padding used for degenerate obstacle overlaps (creates a small exit box).
  static const double exitPointPadding = 2;

  /// Gap multiplier when no arrowhead is present at a bound endpoint.
  static const double elbowNoArrowheadGapMultiplier = 2;

  /// Side padding to keep routes away from bound element edges.
  static const double elementSidePadding = 8;

  /// Minimum padding when correcting bound endpoint directions during edits.
  static const double directionFixPadding = 12;
}
