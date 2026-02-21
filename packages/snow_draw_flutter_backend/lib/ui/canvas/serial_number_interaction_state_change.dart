import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'serial_number_interaction_classifier.dart';

/// Returns true when only an in-progress serial-number interaction changed.
///
/// This fast path intentionally excludes document/view/selection updates so
/// callers can skip cursor hit-testing work while still repainting previews.
bool isSerialNumberInteractionMutationOnly({
  required DrawState previous,
  required DrawState next,
}) {
  if (!_isInteractionMutationOnly(previous: previous, next: next)) {
    return false;
  }

  final previousInteraction = previous.application.interaction;
  final nextInteraction = next.application.interaction;
  return switch ((previousInteraction, nextInteraction)) {
    (final CreatingState previousCreating, final CreatingState nextCreating) =>
      _isSerialNumberCreatingMutationOnly(
        previous: previousCreating,
        next: nextCreating,
      ),
    (final EditingState previousEditing, final EditingState nextEditing) =>
      _isSerialNumberEditingMutationOnly(
        previous: previousEditing,
        next: nextEditing,
        document: next.domain.document,
      ),
    _ => false,
  };
}

bool _isInteractionMutationOnly({
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

bool _isSerialNumberCreatingMutationOnly({
  required CreatingState previous,
  required CreatingState next,
}) {
  if (!SerialNumberInteractionClassifier.isSerialNumberCreation(previous) ||
      !SerialNumberInteractionClassifier.isSerialNumberCreation(next) ||
      !_isSameSerialNumberCreationSession(previous, next)) {
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

bool _isSerialNumberEditingMutationOnly({
  required EditingState previous,
  required EditingState next,
  required DocumentState document,
}) {
  if (!_isSameSerialNumberEditSession(previous, next) ||
      !SerialNumberInteractionClassifier.isSingleSerialNumberEdit(
        interaction: previous,
        document: document,
      ) ||
      !SerialNumberInteractionClassifier.isSingleSerialNumberEdit(
        interaction: next,
        document: document,
      )) {
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
