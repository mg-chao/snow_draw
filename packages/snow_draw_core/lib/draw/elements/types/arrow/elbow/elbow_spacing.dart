import 'dart:math' as math;

import '../arrow_binding.dart';
import 'elbow_constants.dart';

/// Shared spacing calculations for elbow routing and editing.
final class ElbowSpacing {
  const ElbowSpacing._();

  /// Gap between a bound anchor and the routed elbow point.
  static double bindingGap({required bool hasArrowhead}) =>
      ArrowBindingUtils.elbowBindingGapBase *
      (hasArrowhead
          ? ArrowBindingUtils.elbowArrowheadGapMultiplier
          : ElbowConstants.elbowNoArrowheadGapMultiplier);

  /// Padding used when inflating obstacle bounds near the arrowhead side.
  static double headPadding({required bool hasArrowhead}) {
    final padding =
        ElbowConstants.basePadding - bindingGap(hasArrowhead: hasArrowhead);
    return math.max(0, padding);
  }

  /// Minimum padding when aligning fixed neighbors during editing.
  static double fixedNeighborPadding({required bool hasArrowhead}) {
    final padding = headPadding(hasArrowhead: hasArrowhead);
    if (!padding.isFinite || padding <= ElbowConstants.dedupThreshold) {
      return ElbowConstants.directionFixPadding;
    }
    return math.max(ElbowConstants.directionFixPadding, padding);
  }
}
