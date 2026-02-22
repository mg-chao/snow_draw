import 'package:snow_draw_core/snow_draw_core.dart';

import 'interaction_state_change_common.dart';

/// Returns true when only an in-progress rectangle interaction changed.
///
/// This fast path intentionally excludes document/view/selection updates so
/// callers can repaint only the dynamic layer without rebuilding static-scene
/// snapshots.
///
/// Rectangle edit sessions are treated as dynamic-only only when:
/// - every selected element is a rectangle, and
/// - none of those rectangles currently drive bound arrow endpoints.
///
/// If arrows are bound to edited rectangles, static layer updates may be
/// required to keep lower z-order bound arrows in sync; in that case this
/// function returns false and callers should use the full refresh path.
bool isRectangleInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) => isTypedInteractionMutationOnly(
  previous: previous,
  next: next,
  supportsCreating: (interaction) => interaction.elementData is RectangleData,
  supportsEditing: (interaction, document) =>
      _isRectangleEditContext(context: interaction.context, document: document),
);

bool _isRectangleEditContext({
  required EditContext context,
  required DocumentState document,
}) {
  final selectedIds = context.selectedIdsAtStart;
  if (document.hasArrowBoundToAny(selectedIds)) {
    return false;
  }
  return selectionMatchesElements(
    context: context,
    document: document,
    predicate: (element) => element.data is RectangleData,
  );
}
