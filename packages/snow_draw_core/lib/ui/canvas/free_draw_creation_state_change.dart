import '../../draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import '../../draw/elements/types/free_draw/free_draw_data.dart';
import '../../draw/models/draw_state.dart';
import '../../draw/models/interaction_state.dart';

/// Returns true when only an in-progress free-draw preview payload changed.
///
/// This fast path intentionally excludes document/view/selection updates so
/// callers can repaint only the dedicated free-draw preview layer without
/// rebuilding the full canvas widget tree.
bool isFreeDrawPreviewMutationOnly({
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
  if (previousInteraction is! CreatingState ||
      nextInteraction is! CreatingState) {
    return false;
  }
  if (previousInteraction.elementData is! FreeDrawData ||
      nextInteraction.elementData is! FreeDrawData) {
    return false;
  }

  if (!_isSameFreeDrawCreationSession(previousInteraction, nextInteraction)) {
    return false;
  }

  if (!_listEquals(
    previousInteraction.snapGuides,
    nextInteraction.snapGuides,
  )) {
    return false;
  }

  final previousMode = previousInteraction.creationMode;
  final nextMode = nextInteraction.creationMode;
  if (previousMode is! FreeDrawCreationMode ||
      nextMode is! FreeDrawCreationMode) {
    return false;
  }

  return previousInteraction.currentRect != nextInteraction.currentRect ||
      previousMode != nextMode;
}

bool _isSameFreeDrawCreationSession(
  CreatingState previous,
  CreatingState next,
) =>
    previous.elementId == next.elementId &&
    previous.elementData == next.elementData &&
    previous.elementRect == next.elementRect &&
    previous.elementRotation == next.elementRotation &&
    previous.elementOpacity == next.elementOpacity &&
    previous.elementZIndex == next.elementZIndex &&
    previous.startPosition == next.startPosition;

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
