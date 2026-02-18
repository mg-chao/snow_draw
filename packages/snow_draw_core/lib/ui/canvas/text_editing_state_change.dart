import '../../draw/models/draw_state.dart';
import '../../draw/models/interaction_state.dart';

/// Returns true when only an in-progress text editing draft payload changed.
///
/// This fast-path intentionally excludes document/view/selection updates so
/// callers can skip expensive cursor hit-testing work on high-frequency
/// keystroke updates.
bool isTextEditingDraftMutationOnly({
  required DrawState previous,
  required DrawState next,
}) {
  if (identical(previous, next)) {
    return false;
  }
  if (!identical(previous.domain, next.domain)) {
    return false;
  }

  final previousApplication = previous.application;
  final nextApplication = next.application;
  if (previousApplication.view != nextApplication.view ||
      previousApplication.selectionOverlay !=
          nextApplication.selectionOverlay) {
    return false;
  }

  final previousInteraction = previousApplication.interaction;
  final nextInteraction = nextApplication.interaction;
  if (previousInteraction is! TextEditingState ||
      nextInteraction is! TextEditingState) {
    return false;
  }
  if (!_isSameTextEditingSession(previousInteraction, nextInteraction)) {
    return false;
  }

  return !identical(previousInteraction.draftData, nextInteraction.draftData) ||
      previousInteraction.rect != nextInteraction.rect;
}

/// Returns true when a text draft mutation should refresh dynamic canvas state.
///
/// Text glyphs are rendered by a dedicated editor overlay, but selection
/// outlines and serial-number connectors depend on preview rect changes in the
/// dynamic painter. Refresh is limited to existing text edits whose rect
/// changed to preserve the text-draft fast path for all other cases.
bool shouldRefreshDynamicLayerForTextEditingDraftMutation({
  required DrawState previous,
  required DrawState next,
}) {
  if (!isTextEditingDraftMutationOnly(previous: previous, next: next)) {
    return false;
  }

  final previousInteraction = previous.application.interaction;
  final nextInteraction = next.application.interaction;
  if (previousInteraction is! TextEditingState ||
      nextInteraction is! TextEditingState) {
    return false;
  }
  if (nextInteraction.isNew) {
    return false;
  }
  return previousInteraction.rect != nextInteraction.rect;
}

bool _isSameTextEditingSession(
  TextEditingState previous,
  TextEditingState next,
) =>
    previous.elementId == next.elementId &&
    previous.isNew == next.isNew &&
    previous.opacity == next.opacity &&
    previous.rotation == next.rotation &&
    previous.initialCursorPosition == next.initialCursorPosition;
