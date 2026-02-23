import 'package:snow_draw_core/snow_draw_core.dart';

/// Returns true when only an in-progress text editing draft payload changed.
///
/// This fast-path intentionally excludes document/view/selection updates so
/// callers can skip expensive cursor hit-testing work on high-frequency
/// keystroke updates.
bool isTextEditingDraftMutationOnly({
  required DrawState previous,
  required DrawState next,
}) {
  final previousApplication = previous.application;
  final nextApplication = next.application;
  final previousInteraction = previousApplication.interaction;
  final nextInteraction = nextApplication.interaction;
  if (!identical(previous.domain, next.domain) ||
      previousApplication.view != nextApplication.view ||
      previousApplication.selectionOverlay !=
          nextApplication.selectionOverlay ||
      previousInteraction is! TextEditingState ||
      nextInteraction is! TextEditingState ||
      !_isSameTextEditingSession(previousInteraction, nextInteraction)) {
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

  final previousInteraction =
      previous.application.interaction as TextEditingState;
  final nextInteraction = next.application.interaction as TextEditingState;
  return !nextInteraction.isNew &&
      previousInteraction.rect != nextInteraction.rect;
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
