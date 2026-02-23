import 'package:snow_draw_core/snow_draw_core.dart';

import 'interaction_state_change_common.dart';

/// Returns true when only an in-progress lightweight line interaction changed.
///
/// Lightweight line edits are edit sessions where every selected element is
/// either a [LineData] or [FreeDrawData]. These element types are not arrow
/// binding targets, so transform-only updates can repaint the dynamic layer
/// without rebuilding static-scene snapshots.
///
/// This fast path also covers [LineData] creation updates, where only the
/// in-progress creating interaction changes and the persistent document stays
/// unchanged.
bool isLightweightLineInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) => isTypedInteractionMutationOnly(
  previous: previous,
  next: next,
  supportsCreating: (interaction) => interaction.elementData is LineData,
  supportsEditing: (interaction, document) => isLightweightLineEditContext(
    context: interaction.context,
    document: document,
  ),
);

/// Returns true when [interaction] is an editing session limited to
/// lightweight line-compatible element types.
///
/// Lightweight line contexts include only [LineData] and [FreeDrawData]
/// selections, which can use the dynamic-layer fast path safely.
bool isLightweightLineEditingInteraction({
  required InteractionState interaction,
  required DocumentState document,
}) =>
    interaction is EditingState &&
    isLightweightLineEditContext(
      context: interaction.context,
      document: document,
    );

/// Returns true when [context] selects only lightweight line-compatible
/// element types in [document].
bool isLightweightLineEditContext({
  required EditContext context,
  required DocumentState document,
}) => selectionMatchesElements(
  context: context,
  document: document,
  predicate: (element) {
    final data = element.data;
    return data is LineData || data is FreeDrawData;
  },
);
