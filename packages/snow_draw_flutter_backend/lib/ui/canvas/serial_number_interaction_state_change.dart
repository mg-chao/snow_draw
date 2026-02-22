import 'package:snow_draw_core/snow_draw_core.dart';

import 'interaction_state_change_common.dart';
import 'serial_number_interaction_classifier.dart';

/// Returns true when only an in-progress serial-number interaction changed.
///
/// This fast path intentionally excludes document/view/selection updates so
/// callers can skip cursor hit-testing work while still repainting previews.
bool isSerialNumberInteractionMutationOnly({
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

bool _isSerialNumberCreatingMutationOnly({
  required CreatingState previous,
  required CreatingState next,
}) {
  if (!SerialNumberInteractionClassifier.isSerialNumberCreation(previous) ||
      !SerialNumberInteractionClassifier.isSerialNumberCreation(next) ||
      !isSameCreationSession(previous, next)) {
    return false;
  }
  return didCreatingInteractionPreviewChange(previous, next);
}

bool _isSerialNumberEditingMutationOnly({
  required EditingState previous,
  required EditingState next,
  required DocumentState document,
}) {
  if (!isSameEditSession(previous, next) ||
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
  return didEditingInteractionPreviewChange(previous, next);
}
