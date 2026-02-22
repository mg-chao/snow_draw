import 'package:snow_draw_core/snow_draw_core.dart';

/// Predicate for supported creation interactions in mutation fast paths.
typedef CreatingInteractionPredicate = bool Function(CreatingState interaction);

/// Predicate for supported editing interactions in mutation fast paths.
typedef EditingInteractionPredicate =
    bool Function(EditingState interaction, DocumentState document);

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

/// Returns true when [previous]/[next] qualify for a typed interaction fast path.
bool isTypedInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
  required CreatingInteractionPredicate supportsCreating,
  required EditingInteractionPredicate supportsEditing,
}) {
  if (!isInteractionMutationOnly(previous: previous, next: next)) {
    return false;
  }

  final previousInteraction = previous.application.interaction;
  final nextInteraction = next.application.interaction;
  final document = next.domain.document;
  return switch ((previousInteraction, nextInteraction)) {
    (final CreatingState previousCreating, final CreatingState nextCreating) =>
      isSameCreationSession(previousCreating, nextCreating) &&
          supportsCreating(previousCreating) &&
          supportsCreating(nextCreating) &&
          didCreatingInteractionPreviewChange(previousCreating, nextCreating),
    (final EditingState previousEditing, final EditingState nextEditing) =>
      isSameEditSession(previousEditing, nextEditing) &&
          supportsEditing(previousEditing, document) &&
          supportsEditing(nextEditing, document) &&
          didEditingInteractionPreviewChange(previousEditing, nextEditing),
    _ => false,
  };
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

/// Returns true when all selected elements in [context] satisfy [predicate].
bool selectionMatchesElements({
  required EditContext context,
  required DocumentState document,
  required bool Function(ElementState element) predicate,
}) {
  final selectedIds = context.selectedIdsAtStart;
  if (selectedIds.isEmpty) {
    return false;
  }
  for (final elementId in selectedIds) {
    final element = document.getElementById(elementId);
    if (element == null || !predicate(element)) {
      return false;
    }
  }
  return true;
}
