import 'package:snow_draw_core/snow_draw_core.dart';

/// Returns true when only application interaction state changed.
///
/// This guard requires domain state identity to remain stable so callers can
/// safely skip static-layer rebuilds.
bool isInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) {
  if (identical(previous, next) || !identical(previous.domain, next.domain)) {
    return false;
  }

  final previousApplication = previous.application;
  final nextApplication = next.application;
  return previousApplication.view == nextApplication.view &&
      previousApplication.selectionOverlay == nextApplication.selectionOverlay;
}

/// Returns true when [previous] and [next] belong to the same create session.
bool isSameCreationSession(CreatingState previous, CreatingState next) =>
    previous.elementId == next.elementId &&
    previous.elementRect == next.elementRect &&
    previous.elementRotation == next.elementRotation &&
    previous.elementOpacity == next.elementOpacity &&
    previous.elementZIndex == next.elementZIndex &&
    previous.startPosition == next.startPosition;

/// Returns true when [previous] and [next] belong to the same edit session.
bool isSameEditSession(EditingState previous, EditingState next) =>
    previous.operationId == next.operationId &&
    previous.sessionId == next.sessionId &&
    identical(previous.context, next.context);

/// Returns true when create-preview fields changed between two interactions.
bool didCreatingInteractionPreviewChange(
  CreatingState previous,
  CreatingState next,
) =>
    previous.currentRect != next.currentRect ||
    previous.creationMode != next.creationMode ||
    previous.elementData != next.elementData ||
    !listItemsEqual(previous.snapGuides, next.snapGuides);

/// Returns true when edit-preview fields changed between two interactions.
bool didEditingInteractionPreviewChange(
  EditingState previous,
  EditingState next,
) =>
    previous.currentTransform != next.currentTransform ||
    !listItemsEqual(previous.snapGuides, next.snapGuides);

/// Lightweight list equality helper that avoids extra package dependencies.
bool listItemsEqual<T>(List<T> first, List<T> second) {
  if (identical(first, second)) {
    return true;
  }
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
