import 'package:meta/meta.dart';

import 'package:snow_draw_core/snow_draw_core.dart';
import 'arrow_interaction_state_change.dart';
import 'filter_interaction_state_change.dart';
import 'highlight_interaction_state_change.dart';
import 'lightweight_line_edit_state_change.dart';
import 'rectangle_interaction_state_change.dart';
import 'serial_number_interaction_state_change.dart';

/// Interaction category resolved for a fast-path mutation.
enum InteractionMutationKind {
  /// Serial-number create/edit interaction.
  serialNumber,

  /// Lightweight line create/edit interaction.
  lightweightLine,

  /// Rectangle create/edit interaction.
  rectangle,

  /// Highlight create/edit interaction.
  highlight,

  /// Filter create/edit interaction.
  filter,

  /// Arrow create/edit interaction.
  arrow,
}

/// Canvas refresh plan for interaction-only mutations.
@immutable
class InteractionMutationRefreshPlan {
  const InteractionMutationRefreshPlan({required this.kind});

  /// Category of interaction the plan applies to.
  final InteractionMutationKind kind;

  /// Returns `true` when cursor/hover visuals should be recomputed now.
  bool shouldRefreshPointerVisuals({required bool hasActivePointer}) =>
      !hasActivePointer;

  static const serialNumber = InteractionMutationRefreshPlan(
    kind: InteractionMutationKind.serialNumber,
  );

  static const lightweightLine = InteractionMutationRefreshPlan(
    kind: InteractionMutationKind.lightweightLine,
  );

  static const rectangle = InteractionMutationRefreshPlan(
    kind: InteractionMutationKind.rectangle,
  );

  static const highlight = InteractionMutationRefreshPlan(
    kind: InteractionMutationKind.highlight,
  );

  static const filter = InteractionMutationRefreshPlan(
    kind: InteractionMutationKind.filter,
  );

  static const arrow = InteractionMutationRefreshPlan(
    kind: InteractionMutationKind.arrow,
  );
}

/// Resolves fast-path refresh behavior for interaction-only state mutations.
InteractionMutationRefreshPlan? resolveInteractionMutationRefreshPlan({
  required DrawState previous,
  required DrawState next,
}) {
  if (isArrowInteractionMutationOnly(previous: previous, next: next)) {
    return InteractionMutationRefreshPlan.arrow;
  }
  if (isSerialNumberInteractionMutationOnly(previous: previous, next: next)) {
    return InteractionMutationRefreshPlan.serialNumber;
  }
  if (isLightweightLineInteractionMutationOnly(
    previous: previous,
    next: next,
  )) {
    return InteractionMutationRefreshPlan.lightweightLine;
  }
  if (isRectangleInteractionMutationOnly(previous: previous, next: next)) {
    return InteractionMutationRefreshPlan.rectangle;
  }
  if (isHighlightInteractionMutationOnly(previous: previous, next: next)) {
    return InteractionMutationRefreshPlan.highlight;
  }
  if (isFilterInteractionMutationOnly(previous: previous, next: next)) {
    return InteractionMutationRefreshPlan.filter;
  }
  return null;
}
