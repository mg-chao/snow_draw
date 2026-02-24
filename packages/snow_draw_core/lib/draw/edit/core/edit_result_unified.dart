import 'package:meta/meta.dart';

import '../../models/draw_state.dart';
import '../../types/edit_operation_id.dart';

/// Unified failure reasons for edit sessions.
enum EditFailureReason {
  /// Session/dispatch failures.
  notEditing,
  unknownOperationId,

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

/// Edit session outcome.
@immutable
final class EditOutcome {
  const EditOutcome({
    required this.state,
    this.failureReason,
    this.operationId,
  });

  final DrawState state;
  final EditFailureReason? failureReason;
  final EditOperationId? operationId;

  bool get isSuccess => failureReason == null;
}
