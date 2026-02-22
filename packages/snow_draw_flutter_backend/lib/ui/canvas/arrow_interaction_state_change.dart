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
}) {
  if (!isInteractionMutationOnly(previous: previous, next: next)) {
    return false;
  }

  final previousInteraction = previous.application.interaction;
  final nextInteraction = next.application.interaction;
  return switch ((previousInteraction, nextInteraction)) {
    (final CreatingState previousCreating, final CreatingState nextCreating) =>
      _isArrowCreatingMutationOnly(
        previous: previousCreating,
        next: nextCreating,
      ),
    (final EditingState previousEditing, final EditingState nextEditing) =>
      _isArrowEditingMutationOnly(
        previous: previousEditing,
        next: nextEditing,
        document: next.domain.document,
      ),
    _ => false,
  };
}

bool _isArrowCreatingMutationOnly({
  required CreatingState previous,
  required CreatingState next,
}) {
  if (previous.elementData is! ArrowData || next.elementData is! ArrowData) {
    return false;
  }
  if (!isSameCreationSession(previous, next)) {
    return false;
  }

  return didCreatingInteractionPreviewChange(previous, next);
}

bool _isArrowEditingMutationOnly({
  required EditingState previous,
  required EditingState next,
  required DocumentState document,
}) {
  if (!isSameEditSession(previous, next)) {
    return false;
  }
  if (!_isArrowEditContext(context: next.context, document: document)) {
    return false;
  }

  return didEditingInteractionPreviewChange(previous, next);
}

bool _isArrowEditContext({
  required EditContext context,
  required DocumentState document,
}) {
  final selectedIds = context.selectedIdsAtStart;
  if (selectedIds.isEmpty) {
    return false;
  }
  return selectedIds.every(
    (elementId) => document.getElementById(elementId)?.data is ArrowData,
  );
}
