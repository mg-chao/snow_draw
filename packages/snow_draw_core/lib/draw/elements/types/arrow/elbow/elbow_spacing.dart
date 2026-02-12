import 'dart:math' as math;

import '../../../../types/draw_rect.dart';
import '../arrow_binding.dart';
import 'elbow_constants.dart';
import 'elbow_heading.dart';

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

  /// Minimum spacing between a bound element edge and the routed path.
  ///
  /// This is the base binding gap, scaled by the arrowhead multiplier
  /// when an arrowhead is present.
  static double minBindingSpacing({required bool hasArrowhead}) {
    const base = ArrowBindingUtils.elbowBindingGapBase;
    if (!hasArrowhead) {
      return base;
    }
    return base * ArrowBindingUtils.elbowArrowheadGapMultiplier;
  }

  /// Reads the current spacing between [elementBounds] and [obstacle]
  /// along the exit axis defined by [heading].
  ///
  /// Returns `null` when the spacing is non-finite or below epsilon.
  static double? resolveObstacleSpacing({
    required DrawRect elementBounds,
    required DrawRect obstacle,
    required ElbowHeading heading,
  }) {
    final spacing = switch (heading) {
      ElbowHeading.up => elementBounds.minY - obstacle.minY,
      ElbowHeading.right => obstacle.maxX - elementBounds.maxX,
      ElbowHeading.down => obstacle.maxY - elementBounds.maxY,
      ElbowHeading.left => elementBounds.minX - obstacle.minX,
    };
    if (!spacing.isFinite || spacing <= ElbowConstants.intersectionEpsilon) {
      return null;
    }
    return spacing;
  }

  /// Adjusts [obstacle] so that the exit edge along [heading] sits
  /// exactly [spacing] away from [elementBounds].
  static DrawRect applyObstacleSpacing({
    required DrawRect obstacle,
    required DrawRect elementBounds,
    required ElbowHeading heading,
    required double spacing,
  }) => switch (heading) {
    ElbowHeading.up => obstacle.copyWith(minY: elementBounds.minY - spacing),
    ElbowHeading.right => obstacle.copyWith(maxX: elementBounds.maxX + spacing),
    ElbowHeading.down => obstacle.copyWith(maxY: elementBounds.maxY + spacing),
    ElbowHeading.left => obstacle.copyWith(minX: elementBounds.minX - spacing),
  };

  /// Resolves a shared spacing value from two endpoint spacings.
  ///
  /// Takes the minimum of the two spacings and clamps it to the
  /// minimum allowed binding spacing for either endpoint. Returns
  /// `null` when either spacing is `null` or the result is non-finite.
  static double? resolveSharedSpacing({
    required double? startSpacing,
    required double? endSpacing,
    required bool startHasArrowhead,
    required bool endHasArrowhead,
  }) {
    if (startSpacing == null || endSpacing == null) {
      return null;
    }
    final shared = math.min(startSpacing, endSpacing);
    if (!shared.isFinite) {
      return null;
    }
    final minAllowed = math.max(
      minBindingSpacing(hasArrowhead: startHasArrowhead),
      minBindingSpacing(hasArrowhead: endHasArrowhead),
    );
    return math.max(shared, minAllowed);
  }
}
