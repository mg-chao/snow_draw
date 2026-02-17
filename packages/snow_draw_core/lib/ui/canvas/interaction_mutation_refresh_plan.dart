import 'package:meta/meta.dart';

import '../../draw/models/draw_state.dart';
import 'arrow_interaction_state_change.dart';
import 'highlight_interaction_state_change.dart';
import 'lightweight_line_edit_state_change.dart';
import 'rectangle_interaction_state_change.dart';
import 'serial_number_interaction_state_change.dart';

/// Refresh mode for an interaction-only canvas mutation fast path.
enum InteractionMutationRefreshMode {
  /// Repaint only dynamic overlays and previews.
  dynamicOnly,

  /// Rebuild both static and dynamic layer snapshots.
  canvasLayers,
}

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

  /// Arrow create/edit interaction.
  arrow,
}

/// Canvas refresh plan for interaction-only mutations.
@immutable
class InteractionMutationRefreshPlan {
  const InteractionMutationRefreshPlan({
    required this.kind,
    required this.refreshMode,
  });

  /// Category of interaction the plan applies to.
  final InteractionMutationKind kind;

  /// Layer refresh strategy for this interaction mutation.
  final InteractionMutationRefreshMode refreshMode;

  static const serialNumber = InteractionMutationRefreshPlan(
    kind: InteractionMutationKind.serialNumber,
    refreshMode: InteractionMutationRefreshMode.dynamicOnly,
  );

  static const lightweightLine = InteractionMutationRefreshPlan(
    kind: InteractionMutationKind.lightweightLine,
    refreshMode: InteractionMutationRefreshMode.dynamicOnly,
  );

  static const rectangle = InteractionMutationRefreshPlan(
    kind: InteractionMutationKind.rectangle,
    refreshMode: InteractionMutationRefreshMode.dynamicOnly,
  );

  static const highlight = InteractionMutationRefreshPlan(
    kind: InteractionMutationKind.highlight,
    refreshMode: InteractionMutationRefreshMode.dynamicOnly,
  );

  static const arrow = InteractionMutationRefreshPlan(
    kind: InteractionMutationKind.arrow,
    refreshMode: InteractionMutationRefreshMode.dynamicOnly,
  );
}

/// Resolves fast-path refresh behavior for interaction-only state mutations.
InteractionMutationRefreshPlan? resolveInteractionMutationRefreshPlan({
  required DrawState previous,
  required DrawState next,
}) {
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
  if (isArrowInteractionMutationOnly(previous: previous, next: next)) {
    return InteractionMutationRefreshPlan.arrow;
  }
  return null;
}
