import '../../draw/elements/types/rectangle/rectangle_data.dart';
import '../../draw/models/document_state.dart';
import '../../draw/models/draw_state.dart';
import '../../draw/models/interaction_state.dart';
import '../../draw/types/edit_context.dart';

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

  if (previousInteraction is CreatingState &&
      nextInteraction is CreatingState) {
    return _isRectangleCreatingMutationOnly(
      previous: previousInteraction,
      next: nextInteraction,
    );
  }

  if (previousInteraction is EditingState && nextInteraction is EditingState) {
    return _isRectangleEditingMutationOnly(
      previous: previousInteraction,
      next: nextInteraction,
      document: next.domain.document,
    );
  }

  return false;
}

bool _isRectangleCreatingMutationOnly({
  required CreatingState previous,
  required CreatingState next,
}) {
  if (previous.elementData is! RectangleData ||
      next.elementData is! RectangleData) {
    return false;
  }
  if (!_isSameRectangleCreationSession(previous, next)) {
    return false;
  }
  return previous.currentRect != next.currentRect ||
      previous.creationMode != next.creationMode ||
      previous.elementData != next.elementData ||
      !_listEquals(previous.snapGuides, next.snapGuides);
}

bool _isSameRectangleCreationSession(
  CreatingState previous,
  CreatingState next,
) =>
    previous.elementId == next.elementId &&
    previous.elementRect == next.elementRect &&
    previous.elementRotation == next.elementRotation &&
    previous.elementOpacity == next.elementOpacity &&
    previous.elementZIndex == next.elementZIndex &&
    previous.startPosition == next.startPosition;

bool _isRectangleEditingMutationOnly({
  required EditingState previous,
  required EditingState next,
  required DocumentState document,
}) {
  if (!_isSameEditSession(previous, next)) {
    return false;
  }
  if (!_isRectangleEditContext(context: previous.context, document: document) ||
      !_isRectangleEditContext(context: next.context, document: document)) {
    return false;
  }
  return previous.currentTransform != next.currentTransform ||
      !_listEquals(previous.snapGuides, next.snapGuides);
}

bool _isSameEditSession(EditingState previous, EditingState next) =>
    previous.operationId == next.operationId &&
    previous.sessionId == next.sessionId &&
    identical(previous.context, next.context);

bool _isRectangleEditContext({
  required EditContext context,
  required DocumentState document,
}) {
  if (context.selectedIdsAtStart.isEmpty) {
    return false;
  }
  if (document.hasArrowBoundToAny(context.selectedIdsAtStart)) {
    return false;
  }
  for (final elementId in context.selectedIdsAtStart) {
    final element = document.getElementById(elementId);
    if (element?.data is! RectangleData) {
      return false;
    }
  }
  return true;
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
