import 'package:meta/meta.dart';

import 'package:snow_draw_core/snow_draw_core.dart';
import 'interaction_state_change_common.dart';
import 'lightweight_line_edit_state_change.dart';
import 'serial_number_interaction_classifier.dart';

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
  if (_isArrowInteractionMutationOnly(previous: previous, next: next)) {
    return InteractionMutationRefreshPlan.arrow;
  }
  if (_isSerialNumberInteractionMutationOnly(previous: previous, next: next)) {
    return InteractionMutationRefreshPlan.serialNumber;
  }
  if (isLightweightLineInteractionMutationOnly(
    previous: previous,
    next: next,
  )) {
    return InteractionMutationRefreshPlan.lightweightLine;
  }
  if (_isRectangleInteractionMutationOnly(previous: previous, next: next)) {
    return InteractionMutationRefreshPlan.rectangle;
  }
  if (_isHighlightInteractionMutationOnly(previous: previous, next: next)) {
    return InteractionMutationRefreshPlan.highlight;
  }
  if (_isFilterInteractionMutationOnly(previous: previous, next: next)) {
    return InteractionMutationRefreshPlan.filter;
  }
  return null;
}

bool _isArrowInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) => _isElementInteractionMutationOnly<ArrowData>(
  previous: previous,
  next: next,
);

bool _isFilterInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) => _isElementInteractionMutationOnly<FilterData>(
  previous: previous,
  next: next,
);

bool _isHighlightInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) => _isElementInteractionMutationOnly<HighlightData>(
  previous: previous,
  next: next,
);

bool _isRectangleInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) => _isElementInteractionMutationOnly<RectangleData>(
  previous: previous,
  next: next,
  supportsEditing: (context, document) =>
      !document.hasArrowBoundToAny(context.selectedIdsAtStart) &&
      _isSelectionOfType<RectangleData>(context, document),
);

bool _isSerialNumberInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) => isTypedInteractionMutationOnly(
  previous: previous,
  next: next,
  supportsCreating: SerialNumberInteractionClassifier.isSerialNumberCreation,
  supportsEditing: (interaction, document) =>
      SerialNumberInteractionClassifier.isSingleSerialNumberEdit(
        interaction: interaction,
        document: document,
      ),
);

bool _isElementInteractionMutationOnly<T extends ElementData>({
  required DrawState previous,
  required DrawState next,
  bool Function(EditContext context, DocumentState document)? supportsEditing,
}) => isTypedInteractionMutationOnly(
  previous: previous,
  next: next,
  supportsCreating: (interaction) => interaction.elementData is T,
  supportsEditing: (interaction, document) =>
      (supportsEditing ?? _isSelectionOfType<T>)(interaction.context, document),
);

bool _isSelectionOfType<T extends ElementData>(
  EditContext context,
  DocumentState document,
) => selectionMatchesElements(
  context: context,
  document: document,
  predicate: (element) => element.data is T,
);
