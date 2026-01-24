import 'package:meta/meta.dart';

import '../../history/history_metadata.dart';
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

/// Unified edit session result (success or failure).
@immutable
class EditResult {
  const EditResult._({
    required this.state,
    this.failureReason,
    this.operationId,
    this.historyMetadata,
  });

  factory EditResult.success({
    required DrawState state,
    EditOperationId? operationId,
    HistoryMetadata? historyMetadata,
  }) => EditResult._(
    state: state,
    operationId: operationId,
    historyMetadata: historyMetadata,
  );

  factory EditResult.failure({
    required DrawState state,
    required EditFailureReason reason,
    EditOperationId? operationId,
  }) => EditResult._(
    state: state,
    failureReason: reason,
    operationId: operationId,
  );
  final DrawState state;
  final EditFailureReason? failureReason;
  final EditOperationId? operationId;
  final HistoryMetadata? historyMetadata;

  bool get isSuccess => failureReason == null;
  bool get isFailure => !isSuccess;
}
