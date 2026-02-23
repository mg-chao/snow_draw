import 'package:snow_draw_core/snow_draw_core.dart';
import 'interaction_state_change_common.dart';
import 'lightweight_line_edit_state_change.dart';
import 'serial_number_interaction_classifier.dart';

/// Canvas refresh plan for interaction-only mutations.
enum InteractionMutationRefreshPlan {
  /// Generic interaction fast-path; dynamic layer refresh is sufficient.
  dynamicOnly,

  /// Lightweight-line specific fast-path with tighter preview-id tracking.
  lightweightLineDynamicOnly,
}

/// Resolves fast-path refresh behavior for interaction-only state mutations.
InteractionMutationRefreshPlan? resolveInteractionMutationRefreshPlan({
  required DrawState previous,
  required DrawState next,
}) {
  if (isLightweightLineInteractionMutationOnly(
    previous: previous,
    next: next,
  )) {
    return InteractionMutationRefreshPlan.lightweightLineDynamicOnly;
  }
  if (_isArrowInteractionMutationOnly(previous: previous, next: next) ||
      _isSerialNumberInteractionMutationOnly(previous: previous, next: next) ||
      _isRectangleInteractionMutationOnly(previous: previous, next: next) ||
      _isHighlightInteractionMutationOnly(previous: previous, next: next) ||
      _isFilterInteractionMutationOnly(previous: previous, next: next)) {
    return InteractionMutationRefreshPlan.dynamicOnly;
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
