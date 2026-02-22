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
}) {
  if (!isInteractionMutationOnly(previous: previous, next: next)) {
    return false;
  }

  final previousInteraction = previous.application.interaction;
  final nextInteraction = next.application.interaction;
  return switch ((previousInteraction, nextInteraction)) {
    (final CreatingState previousCreating, final CreatingState nextCreating) =>
      _isFilterCreatingMutationOnly(
        previous: previousCreating,
        next: nextCreating,
      ),
    (final EditingState previousEditing, final EditingState nextEditing) =>
      _isFilterEditingMutationOnly(
        previous: previousEditing,
        next: nextEditing,
        document: next.domain.document,
      ),
    _ => false,
  };
}

bool _isFilterCreatingMutationOnly({
  required CreatingState previous,
  required CreatingState next,
}) {
  if (previous.elementData is! FilterData ||
      next.elementData is! FilterData ||
      !isSameCreationSession(previous, next)) {
    return false;
  }
  return didCreatingInteractionPreviewChange(previous, next);
}

bool _isFilterEditingMutationOnly({
  required EditingState previous,
  required EditingState next,
  required DocumentState document,
}) {
  if (!isSameEditSession(previous, next)) {
    return false;
  }
  if (!_isFilterEditContext(context: next.context, document: document)) {
    return false;
  }
  return didEditingInteractionPreviewChange(previous, next);
}

bool _isFilterEditContext({
  required EditContext context,
  required DocumentState document,
}) {
  final selectedIds = context.selectedIdsAtStart;
  if (selectedIds.isEmpty) {
    return false;
  }
  return selectedIds.every(
    (elementId) => document.getElementById(elementId)?.data is FilterData,
  );
}
