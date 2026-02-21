import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../models/draw_state.dart';
import '../../models/edit_session_id.dart';
import '../../models/interaction_state.dart';
import '../../services/log/log_service.dart';
import '../../types/draw_point.dart';
import '../../types/edit_operation_id.dart';
import '../../types/snap_guides.dart';
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

    final operation = editOperations.getOperation(operationId);
    if (operation == null) {
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
        operation: operation,
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
  }) => EditErrorHandlerExtension.runWithErrorHandling(
    state: state,
    config: _toErrorConfig(failurePolicy),
    operationName: 'updateEdit',
    log: _log,
    operation: () {
      final restored = _restoreOrThrow(state, validateVersions: true);
      return _performUpdate(
        state: state,
        operation: restored.operation,
        editingState: restored.editingState,
        currentPosition: currentPosition,
        modifiers: modifiers,
      );
    },
  );

  EditOutcome finish({required DrawState state}) =>
      EditErrorHandlerExtension.runWithErrorHandling(
        state: state,
        config: EditErrorHandlerConfig.toIdle,
        operationName: 'finishEdit',
        log: _log,
        operation: () {
          final restored = _restoreOrThrow(state, validateVersions: true);
          return _performFinish(
            state: state,
            operation: restored.operation,
            editingState: restored.editingState,
          );
        },
      );

  EditOutcome cancel({required DrawState state}) =>
      EditErrorHandlerExtension.runWithErrorHandling(
        state: state,
        config: EditErrorHandlerConfig.toIdle,
        operationName: 'cancelEdit',
        log: _log,
        operation: () {
          final restored = _restoreOrThrow(state);
          return _performCancel(
            state: state,
            operation: restored.operation,
            editingState: restored.editingState,
          );
        },
      );

  EditErrorHandlerConfig _toErrorConfig(EditUpdateFailurePolicy policy) =>
      switch (policy) {
        EditUpdateFailurePolicy.toIdle => EditErrorHandlerConfig.toIdle,
        EditUpdateFailurePolicy.keepState => EditErrorHandlerConfig.keepState,
      };

  EditOutcome _performStart({
    required DrawState state,
    required EditOperationBase operation,
    required EditOperationId operationId,
    required DrawPoint position,
    required EditOperationParams params,
    required EditSessionId sessionId,
  }) {
    final session = _createSession(
      operation: operation,
      operationId: operationId,
      state: state,
      position: position,
      params: params,
      sessionId: sessionId,
    );

    return (
      state: state.copyWith(
        application: state.application.copyWith(interaction: session),
      ),
      failureReason: null,
      operationId: operationId,
    );
  }

  EditOutcome _performUpdate({
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

    final transformUnchanged =
        updated.transform == editingState.currentTransform;
    final guidesUnchanged = _snapGuideListsEqual(
      updated.snapGuides,
      editingState.snapGuides,
    );
    if (transformUnchanged && guidesUnchanged) {
      return (
        state: state,
        failureReason: null,
        operationId: editingState.operationId,
      );
    }

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

  EditOutcome _performFinish({
    required DrawState state,
    required EditOperationBase operation,
    required EditingState editingState,
  }) {
    _log?.info('Edit session finished', {'operationId': operation.id});
    return (
      state: operation.finish(
        state: state,
        context: editingState.context,
        transform: editingState.currentTransform,
      ),
      failureReason: null,
      operationId: editingState.operationId,
    );
  }

  EditOutcome _performCancel({
    required DrawState state,
    required EditOperationBase operation,
    required EditingState editingState,
  }) {
    _log?.info('Edit session cancelled', {'operationId': operation.id});
    return (
      state: operation.cancel(state: state),
      failureReason: null,
      operationId: editingState.operationId,
    );
  }

  EditingState _createSession({
    required EditOperationBase operation,
    required EditOperationId operationId,
    required DrawState state,
    required DrawPoint position,
    required EditOperationParams params,
    required EditSessionId sessionId,
  }) {
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
    DrawState state, {
    bool validateVersions = false,
  }) {
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

    if (validateVersions) {
      _validateVersionOrThrow(editingState: interaction, currentState: state);
    }

    _log?.trace('Edit session restored', {
      'operationId': interaction.operationId,
      'sessionId': interaction.sessionId,
    });
    return (operation: operation, editingState: interaction);
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

  bool _snapGuideListsEqual(List<SnapGuide> a, List<SnapGuide> b) {
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
}
