import '../../draw/models/draw_state.dart';
import '../../draw/models/interaction_state.dart';
import 'serial_number_interaction_classifier.dart';

/// Returns true when only an in-progress serial-number interaction changed.
///
/// This fast path intentionally excludes document/view/selection updates so
/// callers can skip cursor hit-testing work while still repainting previews.
bool isSerialNumberInteractionMutationOnly({
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
  if (SerialNumberInteractionClassifier.isSerialNumberCreation(
        previousInteraction,
      ) &&
      SerialNumberInteractionClassifier.isSerialNumberCreation(
        nextInteraction,
      )) {
    return _isSerialNumberCreatingMutationOnly(
      previousInteraction as CreatingState,
      nextInteraction as CreatingState,
    );
  }

  final document = next.domain.document;
  if (!SerialNumberInteractionClassifier.isSingleSerialNumberEdit(
        interaction: previousInteraction,
        document: document,
      ) ||
      !SerialNumberInteractionClassifier.isSingleSerialNumberEdit(
        interaction: nextInteraction,
        document: document,
      )) {
    return false;
  }
  return _isSerialNumberEditingMutationOnly(
    previousInteraction as EditingState,
    nextInteraction as EditingState,
  );
}

bool _isSerialNumberCreatingMutationOnly(
  CreatingState previous,
  CreatingState next,
) {
  if (!_isSameSerialNumberCreationSession(previous, next)) {
    return false;
  }
  return previous.currentRect != next.currentRect ||
      previous.creationMode != next.creationMode ||
      previous.elementData != next.elementData ||
      !_listEquals(previous.snapGuides, next.snapGuides);
}

bool _isSameSerialNumberCreationSession(
  CreatingState previous,
  CreatingState next,
) =>
    previous.elementId == next.elementId &&
    previous.elementRect == next.elementRect &&
    previous.elementRotation == next.elementRotation &&
    previous.elementOpacity == next.elementOpacity &&
    previous.elementZIndex == next.elementZIndex &&
    previous.startPosition == next.startPosition;

bool _isSerialNumberEditingMutationOnly(
  EditingState previous,
  EditingState next,
) {
  if (!_isSameSerialNumberEditSession(previous, next)) {
    return false;
  }
  return previous.currentTransform != next.currentTransform ||
      !_listEquals(previous.snapGuides, next.snapGuides);
}

bool _isSameSerialNumberEditSession(EditingState previous, EditingState next) =>
    previous.operationId == next.operationId &&
    previous.sessionId == next.sessionId &&
    identical(previous.context, next.context);

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
