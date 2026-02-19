import '../../models/draw_state.dart';
import '../../models/interaction_state.dart';
import '../../services/log/log_service.dart';
import '../../types/edit_operation_id.dart';
import 'edit_errors.dart';
import 'edit_result_unified.dart';

/// State transition policy when an edit error occurs.
enum ErrorStatePolicy { toIdle, keepState }

/// Configuration for error handling behavior.
class EditErrorHandlerConfig {
  const EditErrorHandlerConfig({this.statePolicy = ErrorStatePolicy.toIdle});
  final ErrorStatePolicy statePolicy;

  static const toIdle = EditErrorHandlerConfig();

  static const keepState = EditErrorHandlerConfig(
    statePolicy: ErrorStatePolicy.keepState,
  );
}

/// Centralized edit error handling utilities.
class EditErrorHandler {
  const EditErrorHandler._();

  static final ModuleLogger _fallbackLog = LogService.fallback.edit;

  static EditOperationId? extractOperationId(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is EditingState) {
      return interaction.operationId;
    }
    return null;
  }

  static DrawState computeNextState(DrawState state, ErrorStatePolicy policy) {
    if (policy == ErrorStatePolicy.keepState) {
      return state;
    }

    final nextApplication = state.application.toIdle();
    if (identical(nextApplication, state.application)) {
      return state;
    }

    return state.copyWith(application: nextApplication);
  }

  static EditOutcome createFailure({
    required DrawState state,
    required EditErrorHandlerConfig config,
    required EditFailureReason reason,
    EditOperationId? operationId,
  }) => (
    state: computeNextState(state, config.statePolicy),
    failureReason: reason,
    operationId: operationId ?? extractOperationId(state),
  );

  static EditFailureReason mapExceptionToReason(Object error) {
    final actualError = switch (error) {
      EditErrorWithContext(:final innerError) => innerError,
      _ => error,
    };

    return switch (actualError) {
      EditMissingDataError _ => EditFailureReason.missingSelectionBounds,
      EditContextTypeMismatchError _ ||
      EditTransformTypeMismatchError _ ||
      EditParamsTypeMismatchError _ ||
      AssertionError _ => EditFailureReason.invalidParams,

      EditVersionConflictError(conflictType: 'selection') =>
        EditFailureReason.selectionChanged,
      EditVersionConflictError(conflictType: 'elements') =>
        EditFailureReason.elementsChanged,
      EditVersionConflictError() => EditFailureReason.operationFailed,

      EditSessionRestoreError(failureType: SessionRestoreFailure.notEditing) =>
        EditFailureReason.notEditing,
      EditSessionRestoreError(
        failureType: SessionRestoreFailure.unknownOperation,
      ) =>
        EditFailureReason.unknownOperationId,
      EditSessionRestoreError(
        failureType: SessionRestoreFailure.sessionDataInvalid,
      ) =>
        EditFailureReason.sessionRestoreFailed,

      _ => EditFailureReason.operationFailed,
    };
  }

  static void _logUnexpectedError(
    Object error,
    StackTrace stackTrace,
    String? operationName, {
    ModuleLogger? log,
    EditOperationId? operationId,
  }) {
    final effectiveLog = log ?? _fallbackLog;
    final data = <String, dynamic>{'operation': operationName ?? 'unknown'};
    if (operationId != null) {
      data['operationId'] = operationId;
    }
    effectiveLog.error('Unexpected edit error', error, stackTrace, data);
  }
}

/// Higher-order wrapper for unified error handling.
extension EditErrorHandlerExtension on EditErrorHandler {
  static EditOutcome runWithErrorHandling({
    required DrawState state,
    required EditErrorHandlerConfig config,
    required EditOutcome Function() operation,
    EditOperationId? fallbackOperationId,
    String? operationName,
    ModuleLogger? log,
  }) {
    try {
      return operation();
    } on EditError catch (error, _) {
      return EditErrorHandler.createFailure(
        state: state,
        config: config,
        reason: EditErrorHandler.mapExceptionToReason(error),
        operationId: fallbackOperationId,
      );
    } on Object catch (error, stackTrace) {
      EditErrorHandler._logUnexpectedError(
        error,
        stackTrace,
        operationName,
        log: log,
        operationId: fallbackOperationId,
      );

      return EditErrorHandler.createFailure(
        state: state,
        config: config,
        reason: EditErrorHandler.mapExceptionToReason(error),
        operationId: fallbackOperationId,
      );
    }
  }
}
