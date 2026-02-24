import '../../models/draw_state.dart';
import '../../models/interaction_state.dart';
import '../../services/log/log_service.dart';
import '../../types/edit_operation_id.dart';
import 'edit_errors.dart';
import 'edit_result_unified.dart';

/// Centralized edit error handling utilities.
class EditErrorHandler {
  const EditErrorHandler._();

  static final ModuleLogger _fallbackLog = LogService.fallback.edit;

  static EditOperationId? extractOperationId(DrawState state) =>
      switch (state.application.interaction) {
        EditingState(:final operationId) => operationId,
        _ => null,
      };

  static DrawState computeNextState(
    DrawState state, {
    required bool keepState,
  }) {
    if (keepState) {
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
    required EditFailureReason reason,
    EditOperationId? operationId,
    bool keepState = false,
  }) => EditOutcome(
    state: computeNextState(state, keepState: keepState),
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
      _ => EditFailureReason.operationFailed,
    };
  }

  /// Executes [operation] and converts thrown errors to [EditOutcome].
  static EditOutcome runWithErrorHandling({
    required DrawState state,
    required EditOutcome Function() operation,
    bool keepStateOnFailure = false,
    EditOperationId? fallbackOperationId,
    String? operationName,
    ModuleLogger? log,
  }) {
    try {
      return operation();
    } on Object catch (error, stackTrace) {
      if (error is! EditError) {
        _logUnexpectedError(
          error,
          stackTrace,
          operationName,
          log: log,
          operationId: fallbackOperationId,
        );
      }
      return createFailure(
        state: state,
        reason: mapExceptionToReason(error),
        operationId: fallbackOperationId,
        keepState: keepStateOnFailure,
      );
    }
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
