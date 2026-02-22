import 'package:snow_draw_core/snow_draw_core.dart';

import 'interaction_state_change_common.dart';

/// Returns true when only an in-progress arrow interaction changed.
///
/// This fast path intentionally excludes document/view/selection updates so
/// callers can repaint only the dynamic layer without rebuilding static-scene
/// snapshots.
bool isArrowInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) => isTypedInteractionMutationOnly(
  previous: previous,
  next: next,
  supportsCreating: (interaction) => interaction.elementData is ArrowData,
  supportsEditing: (interaction, document) =>
      _isArrowEditContext(context: interaction.context, document: document),
);

bool _isArrowEditContext({
  required EditContext context,
  required DocumentState document,
}) => selectionMatchesElements(
  context: context,
  document: document,
  predicate: (element) => element.data is ArrowData,
);
