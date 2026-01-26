import 'package:meta/meta.dart';

import '../../types/edit_operation_id.dart';
import 'edit_result_unified.dart';

/// Diagnostic events emitted by the edit pipeline.
///
/// These are intended for observability (logging/telemetry) and testing, so
/// update-failure policy changes are measurable.
@immutable
sealed class EditSessionEvent {
  const EditSessionEvent();
}

enum EditFailureCategory { business, system }

extension EditFailureReasonCategory on EditFailureReason {
  EditFailureCategory get category => switch (this) {
    EditFailureReason.noSelection => EditFailureCategory.business,
    EditFailureReason.missingSelectionBounds => EditFailureCategory.business,
    EditFailureReason.selectionChanged => EditFailureCategory.business,
    EditFailureReason.elementsChanged => EditFailureCategory.business,
    EditFailureReason.notEditing => EditFailureCategory.business,
    EditFailureReason.unknownOperationId => EditFailureCategory.system,
    EditFailureReason.invalidParams => EditFailureCategory.system,
    EditFailureReason.sessionRestoreFailed => EditFailureCategory.system,
    EditFailureReason.operationFailed => EditFailureCategory.system,
  };
}

@immutable
class EditStartFailed extends EditSessionEvent {
  const EditStartFailed({required this.reason, required this.operationId});
  final EditFailureReason reason;
  final EditOperationId operationId;

  @override
  String toString() =>
      'EditStartFailed(reason: $reason, operationId: $operationId)';
}

@immutable
class EditUpdateFailed extends EditSessionEvent {
  const EditUpdateFailed({required this.reason, required this.operationId});
  final EditFailureReason reason;

  /// Operation id captured from the current editing state (when available).
  final EditOperationId? operationId;

  @override
  String toString() =>
      'EditUpdateFailed(reason: $reason, operationId: $operationId)';
}

@immutable
class EditFinishFailed extends EditSessionEvent {
  const EditFinishFailed({required this.reason, required this.operationId});
  final EditFailureReason reason;
  final EditOperationId? operationId;

  @override
  String toString() =>
      'EditFinishFailed(reason: $reason, operationId: $operationId)';
}

@immutable
class EditCancelled extends EditSessionEvent {
  const EditCancelled({required this.operationId});
  final EditOperationId? operationId;

  @override
  String toString() => 'EditCancelled(operationId: $operationId)';
}

@immutable
class EditCancelFailed extends EditSessionEvent {
  const EditCancelFailed({required this.reason, required this.operationId});
  final EditFailureReason reason;
  final EditOperationId? operationId;

  @override
  String toString() =>
      'EditCancelFailed(reason: $reason, operationId: $operationId)';
}


