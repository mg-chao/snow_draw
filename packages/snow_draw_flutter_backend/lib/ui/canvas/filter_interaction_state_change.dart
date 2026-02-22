import 'package:snow_draw_core/snow_draw_core.dart';

import 'interaction_state_change_common.dart';

/// Returns true when only an in-progress filter interaction changed.
///
/// This fast path intentionally excludes document/view/selection updates so
/// callers can repaint only the dynamic layer without rebuilding static-scene
/// snapshots.
bool isFilterInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) => isTypedInteractionMutationOnly(
  previous: previous,
  next: next,
  supportsCreating: (interaction) => interaction.elementData is FilterData,
  supportsEditing: (interaction, document) =>
      _isFilterEditContext(context: interaction.context, document: document),
);

bool _isFilterEditContext({
  required EditContext context,
  required DocumentState document,
}) => selectionMatchesElements(
  context: context,
  document: document,
  predicate: (element) => element.data is FilterData,
);
