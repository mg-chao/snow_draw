import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../models/draw_state.dart';
import '../../models/edit_session_id.dart';
import '../../models/interaction_state.dart';
import '../../services/log/log_service.dart';
import '../../types/draw_point.dart';
import '../../types/edit_operation_id.dart';
import '../edit_operation_registry_interface.dart';
import 'edit_error_handler.dart';
import 'edit_errors.dart';
import 'edit_modifiers.dart';
import 'edit_operation_base.dart';
import 'edit_operation_params.dart';
import 'edit_result_unified.dart';

/// Edit action pipeline (route A): keep store-side session handling,
/// but centralize the orchestration into a small, testable service.
@immutable
class EditSessionService {
  EditSessionService({
    required this.editOperations,
    required this.configProvider,
    LogService? logService,
  }) : _log = logService?.edit;

  factory EditSessionService.fromRegistry(
    EditOperationRegistry registry, {
    required DrawConfig Function() configProvider,
    LogService? logService,
  }) => EditSessionService(
    editOperations: registry,
    configProvider: configProvider,
    logService: logService,
  );
  final EditOperationRegistry editOperations;
  final DrawConfig Function() configProvider;
  final ModuleLogger? _log;

  // Session API.
  EditOutcome start({
    required DrawState state,
    required EditOperationId operationId,
    required DrawPoint position,
    required EditOperationParams params,
    required EditSessionId sessionId,
  }) {
    if (!state.domain.selection.hasSelection) {
      return (
        state: state,
        failureReason: EditFailureReason.noSelection,
        operationId: operationId,
      );
    }

    if (!_hasOperation(operationId)) {
      return (
        state: state,
        failureReason: EditFailureReason.unknownOperationId,
        operationId: operationId,
      );
    }

    return EditErrorHandlerExtension.runWithErrorHandling(
      state: state,
      config: EditErrorHandlerConfig.keepState,
      fallbackOperationId: operationId,
      operationName: 'startEdit',
      log: _log,
      operation: () => _performStart(
        state: state,
        operationId: operationId,
        position: position,
        params: params,
        sessionId: sessionId,
      ),
    );
  }

  EditOutcome update({
    required DrawState state,
    required DrawPoint currentPosition,
    EditModifiers modifiers = const EditModifiers(),
    EditUpdateFailurePolicy failurePolicy = EditUpdateFailurePolicy.toIdle,
  }) {
    final config = _toErrorConfig(failurePolicy);

    return EditErrorHandlerExtension.runWithErrorHandling(
      state: state,
      config: config,
      operationName: 'updateEdit',
      log: _log,
      operation: () {
        // Version validation now throws EditVersionConflictError
        final interaction = state.application.interaction;
        if (interaction is EditingState) {
          _validateVersionOrThrow(
            editingState: interaction,
            currentState: state,
          );
        }

        return _performUpdate(
          state: state,
          currentPosition: currentPosition,
          modifiers: modifiers,
        );
      },
    );
  }

  EditOutcome finish({required DrawState state}) =>
      EditErrorHandlerExtension.runWithErrorHandling(
        state: state,
        config: EditErrorHandlerConfig.toIdle,
        operationName: 'finishEdit',
        log: _log,
        operation: () {
          // Version validation now throws EditVersionConflictError
          final interaction = state.application.interaction;
          if (interaction is EditingState) {
            _validateVersionOrThrow(
              editingState: interaction,
              currentState: state,
            );
          }

          return _performFinish(state: state);
        },
      );

  EditOutcome cancel({required DrawState state}) =>
      EditErrorHandlerExtension.runWithErrorHandling(
        state: state,
        config: EditErrorHandlerConfig.toIdle,
        operationName: 'cancelEdit',
        log: _log,
        operation: () => _performCancel(state: state),
      );

  EditErrorHandlerConfig _toErrorConfig(EditUpdateFailurePolicy policy) =>
      switch (policy) {
        EditUpdateFailurePolicy.toIdle => EditErrorHandlerConfig.toIdle,
        EditUpdateFailurePolicy.keepState => EditErrorHandlerConfig.keepState,
      };

  EditOutcome _performStart({
    required DrawState state,
    required EditOperationId operationId,
    required DrawPoint position,
    required EditOperationParams params,
    required EditSessionId sessionId,
  }) {
    // Note: We don't pre-compute selection data here. Operations compute it
    // themselves in createContext() since they need more than just bounds
    // (rotation, center, etc.). This avoids redundant O(n) computation.
    final session = _createSession(
      operationId: operationId,
      state: state,
      position: position,
      params: params,
      sessionId: sessionId,
    );

    final newState = state.copyWith(
      application: state.application.copyWith(interaction: session),
    );

    return (
      state: newState,
      failureReason: null,
      operationId: operationId,
    );
  }

  EditOutcome _performUpdate({
    required DrawState state,
    required DrawPoint currentPosition,
    required EditModifiers modifiers,
  }) {
    // Session restoration now throws EditSessionRestoreError
    final restored = _restoreOrThrow(state);

    return _performUpdateWithSession(
      state: state,
      operation: restored.operation,
      editingState: restored.editingState,
      currentPosition: currentPosition,
      modifiers: modifiers,
    );
  }

  EditOutcome _performUpdateWithSession({
    required DrawState state,
    required EditOperationBase operation,
    required EditingState editingState,
    required DrawPoint currentPosition,
    required EditModifiers modifiers,
  }) {
    _log?.trace('Edit session updated', {'operationId': operation.id});
    final updated = operation.update(
      state: state,
      context: editingState.context,
      transform: editingState.currentTransform,
      currentPosition: currentPosition,
      modifiers: modifiers,
      config: configProvider(),
    );

    return (
      state: state.copyWith(
        application: state.application.copyWith(
          interaction: editingState.withTransform(
            updated.transform,
            guides: updated.snapGuides,
          ),
        ),
      ),
      failureReason: null,
      operationId: editingState.operationId,
    );
  }

  EditOutcome _performFinish({required DrawState state}) {
    // Session restoration now throws EditSessionRestoreError
    final restored = _restoreOrThrow(state);

    return (
      state: _finishSession(
        operation: restored.operation,
        state: state,
        editingState: restored.editingState,
      ),
      failureReason: null,
      operationId: restored.editingState.operationId,
    );
  }

  EditOutcome _performCancel({required DrawState state}) {
    // Session restoration now throws EditSessionRestoreError
    final restored = _restoreOrThrow(state);

    return (
      state: _cancelSession(
        operation: restored.operation,
        state: state,
        editingState: restored.editingState,
      ),
      failureReason: null,
      operationId: restored.editingState.operationId,
    );
  }

  bool _hasOperation(EditOperationId operationId) =>
      editOperations.getOperation(operationId) != null;

  EditingState _createSession({
    required EditOperationId operationId,
    required DrawState state,
    required DrawPoint position,
    required EditOperationParams params,
    required EditSessionId sessionId,
  }) {
    final operation = editOperations.getOperation(operationId);
    if (operation == null) {
      _log?.error('Edit session create failed', null, null, {
        'operationId': operationId,
        'reason': 'unknown_operation',
      });
      throw ArgumentError('Unknown operation: $operationId');
    }
    _log?.info('Edit session created', {
      'operationId': operationId,
      'params': params.runtimeType.toString(),
    });
    final context = operation.createContext(
      state: state,
      position: position,
      params: params,
    );
    final transform = operation.initialTransform(
      state: state,
      context: context,
      startPosition: position,
    );
    return EditingState(
      operationId: operationId,
      sessionId: sessionId,
      context: context,
      currentTransform: transform,
    );
  }

  ({EditOperationBase operation, EditingState editingState}) _restoreOrThrow(
    DrawState state,
  ) {
    final interaction = state.application.interaction;
    if (interaction is! EditingState) {
      _log?.error('Edit session restore failed', null, null, {
        'reason': 'not_editing',
      });
      throw const EditSessionRestoreError(
        failureType: SessionRestoreFailure.notEditing,
      );
    }

    final operation = editOperations.getOperation(interaction.operationId);
    if (operation == null) {
      _log?.error('Edit session restore failed', null, null, {
        'operationId': interaction.operationId,
        'reason': 'unknown_operation',
      });
      throw EditSessionRestoreError(
        failureType: SessionRestoreFailure.unknownOperation,
        operationId: interaction.operationId,
      );
    }

    _log?.trace('Edit session restored', {
      'operationId': interaction.operationId,
      'sessionId': interaction.sessionId,
    });
    return (operation: operation, editingState: interaction);
  }

  DrawState _finishSession({
    required EditOperationBase operation,
    required DrawState state,
    required EditingState editingState,
  }) {
    _log?.info('Edit session finished', {'operationId': operation.id});
    return operation.finish(
      state: state,
      context: editingState.context,
      transform: editingState.currentTransform,
    );
  }

  DrawState _cancelSession({
    required EditOperationBase operation,
    required DrawState state,
    required EditingState editingState,
  }) {
    _log?.info('Edit session cancelled', {'operationId': operation.id});
    return operation.cancel(state: state, context: editingState.context);
  }

  void _validateVersionOrThrow({
    required EditingState editingState,
    required DrawState currentState,
  }) {
    final context = editingState.context;

    if (context.selectionVersion !=
        currentState.domain.selection.selectionVersion) {
      throw EditVersionConflictError(
        conflictType: 'selection',
        expectedVersion: context.selectionVersion,
        actualVersion: currentState.domain.selection.selectionVersion,
        operationId: editingState.operationId,
      );
    }

    if (context.elementsVersion !=
        currentState.domain.document.elementsVersion) {
      throw EditVersionConflictError(
        conflictType: 'elements',
        expectedVersion: context.elementsVersion,
        actualVersion: currentState.domain.document.elementsVersion,
        operationId: editingState.operationId,
      );
    }
  }
}
