import 'package:snow_draw_core/snow_draw_core.dart';

/// Returns true when only an in-progress arrow interaction changed.
///
/// This fast path intentionally excludes document/view/selection updates so
/// callers can repaint only the dynamic layer without rebuilding static-scene
/// snapshots.
bool isArrowInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) {
  if (identical(previous, next) || !identical(previous.domain, next.domain)) {
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

  if (previousInteraction is CreatingState &&
      nextInteraction is CreatingState) {
    return _isArrowCreatingMutationOnly(
      previous: previousInteraction,
      next: nextInteraction,
    );
  }

  if (previousInteraction is EditingState && nextInteraction is EditingState) {
    return _isArrowEditingMutationOnly(
      previous: previousInteraction,
      next: nextInteraction,
      document: next.domain.document,
    );
  }

  return false;
}

bool _isArrowCreatingMutationOnly({
  required CreatingState previous,
  required CreatingState next,
}) {
  if (previous.elementData is! ArrowData || next.elementData is! ArrowData) {
    return false;
  }
  if (!_isSameArrowCreationSession(previous, next)) {
    return false;
  }

  return previous.currentRect != next.currentRect ||
      previous.creationMode != next.creationMode ||
      previous.elementData != next.elementData ||
      !_listEquals(previous.snapGuides, next.snapGuides);
}

bool _isSameArrowCreationSession(CreatingState previous, CreatingState next) =>
    previous.elementId == next.elementId &&
    previous.elementRect == next.elementRect &&
    previous.elementRotation == next.elementRotation &&
    previous.elementOpacity == next.elementOpacity &&
    previous.elementZIndex == next.elementZIndex &&
    previous.startPosition == next.startPosition;

bool _isArrowEditingMutationOnly({
  required EditingState previous,
  required EditingState next,
  required DocumentState document,
}) {
  if (!_isSameEditSession(previous, next)) {
    return false;
  }
  if (!_isArrowEditContext(context: next.context, document: document)) {
    return false;
  }

  return previous.currentTransform != next.currentTransform ||
      !_listEquals(previous.snapGuides, next.snapGuides);
}

bool _isSameEditSession(EditingState previous, EditingState next) =>
    previous.operationId == next.operationId &&
    previous.sessionId == next.sessionId &&
    identical(previous.context, next.context);

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
