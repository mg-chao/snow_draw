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
}) {
  if (!isInteractionMutationOnly(previous: previous, next: next)) {
    return false;
  }

  final previousInteraction = previous.application.interaction;
  final nextInteraction = next.application.interaction;
  return switch ((previousInteraction, nextInteraction)) {
    (final CreatingState previousCreating, final CreatingState nextCreating) =>
      _isRectangleCreatingMutationOnly(
        previous: previousCreating,
        next: nextCreating,
      ),
    (final EditingState previousEditing, final EditingState nextEditing) =>
      _isRectangleEditingMutationOnly(
        previous: previousEditing,
        next: nextEditing,
        document: next.domain.document,
      ),
    _ => false,
  };
}

bool _isRectangleCreatingMutationOnly({
  required CreatingState previous,
  required CreatingState next,
}) {
  if (previous.elementData is! RectangleData ||
      next.elementData is! RectangleData ||
      !isSameCreationSession(previous, next)) {
    return false;
  }
  return didCreatingInteractionPreviewChange(previous, next);
}

bool _isRectangleEditingMutationOnly({
  required EditingState previous,
  required EditingState next,
  required DocumentState document,
}) {
  if (!isSameEditSession(previous, next) ||
      !_isRectangleEditContext(context: next.context, document: document)) {
    return false;
  }
  return didEditingInteractionPreviewChange(previous, next);
}

bool _isRectangleEditContext({
  required EditContext context,
  required DocumentState document,
}) {
  final selectedIds = context.selectedIdsAtStart;
  if (selectedIds.isEmpty || document.hasArrowBoundToAny(selectedIds)) {
    return false;
  }
  return selectedIds.every(
    (elementId) => document.getElementById(elementId)?.data is RectangleData,
  );
}
