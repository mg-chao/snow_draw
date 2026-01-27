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
  operationFailed,
}

extension EditFailureReasonX on EditFailureReason {
  bool get isRecoverable => switch (this) {
    EditFailureReason.notEditing => true,
    EditFailureReason.selectionChanged => true,
    EditFailureReason.elementsChanged => true,
    EditFailureReason.noSelection => true,
    EditFailureReason.missingSelectionBounds => true,
    EditFailureReason.unknownOperationId => false,
    EditFailureReason.sessionRestoreFailed => false,
    EditFailureReason.invalidParams => false,
    EditFailureReason.operationFailed => false,
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
  bool get isFailure => failureReason != null;
}
