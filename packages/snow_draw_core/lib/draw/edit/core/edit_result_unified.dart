import '../../models/draw_state.dart';
import '../../types/edit_operation_id.dart';

/// Unified failure reasons for edit sessions.
enum EditFailureReason {
  /// Session/dispatch failures.
  notEditing,
  unknownOperationId,
  sessionRestoreFailed,

  /// State conflicts.
  selectionChanged,
  elementsChanged,

  /// Start-edit validation failures.
  noSelection,
  missingSelectionBounds,
  invalidParams,

  /// Unexpected operation failure.
  operationFailed;

  bool get isRecoverable => switch (this) {
    EditFailureReason.notEditing ||
    EditFailureReason.selectionChanged ||
    EditFailureReason.elementsChanged ||
    EditFailureReason.noSelection ||
    EditFailureReason.missingSelectionBounds => true,
    _ => false,
  };
}

/// Edit session outcome tuple.
typedef EditOutcome = ({
  DrawState state,
  EditFailureReason? failureReason,
  EditOperationId? operationId,
});

extension EditOutcomeX on EditOutcome {
  bool get isSuccess => failureReason == null;
  bool get isFailure => !isSuccess;
}
