import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../models/draw_state.dart';
import '../../models/edit_session_id.dart';
import '../../models/interaction_state.dart';
import '../../services/log/log_service.dart';
import '../../services/text/text_metrics_service.dart';
import '../../types/draw_point.dart';
import '../../types/edit_operation_id.dart';
import '../../types/snap_guides.dart';
import '../edit_operation_registry_interface.dart';
import 'edit_error_handler.dart';
import 'edit_modifiers.dart';
import 'edit_operation.dart';
import 'edit_operation_params.dart';
import 'edit_result_unified.dart';

/// Edit action pipeline (route A): keep store-side session handling,
/// but centralize the orchestration into a small, testable service.
@immutable
class EditSessionService {
  EditSessionService({
    required this.editOperations,
    required this.configProvider,
    this.textMetricsService = defaultTextMetricsService,
    LogService? logService,
  }) : _log = logService?.edit;

  factory EditSessionService.fromRegistry(
    EditOperationRegistry registry, {
    required DrawConfig Function() configProvider,
    TextMetricsService textMetricsService = defaultTextMetricsService,
    LogService? logService,
  }) => EditSessionService(
    editOperations: registry,
    configProvider: configProvider,
    textMetricsService: textMetricsService,
    logService: logService,
  );
  final EditOperationRegistry editOperations;
  final DrawConfig Function() configProvider;
  final TextMetricsService textMetricsService;
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

    return EditErrorHandler.runWithErrorHandling(
      state: state,
      keepStateOnFailure: true,
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
  }) => _withRestoredSession(
    state: state,
    operationName: 'updateEdit',
    validateVersions: true,
    action: (restored) => _performUpdate(
      state: state,
      operation: restored.operation,
      editingState: restored.editingState,
      currentPosition: currentPosition,
      modifiers: modifiers,
    ),
  );

  EditOutcome finish({required DrawState state}) => _withRestoredSession(
    state: state,
    operationName: 'finishEdit',
    validateVersions: true,
    action: (restored) => _performFinish(
      state: state,
      operation: restored.operation,
      editingState: restored.editingState,
    ),
  );

  EditOutcome cancel({required DrawState state}) => _withRestoredSession(
    state: state,
    operationName: 'cancelEdit',
    action: (restored) => _performCancel(
      state: state,
      operation: restored.operation,
      editingState: restored.editingState,
    ),
  );

  EditOutcome _withRestoredSession({
    required DrawState state,
    required String operationName,
    required EditOutcome Function(
      ({EditOperation operation, EditingState editingState}) restored,
    )
    action,
    bool validateVersions = false,
  }) {
    final restoration = _restoreSession(
      state,
      validateVersions: validateVersions,
    );
    if (restoration.failureReason case final reason?) {
      return EditErrorHandler.createFailure(state: state, reason: reason);
    }

    final restored = restoration.session!;
    return EditErrorHandler.runWithErrorHandling(
      state: state,
      operationName: operationName,
      log: _log,
      fallbackOperationId: restored.editingState.operationId,
      operation: () => action(restored),
    );
  }

  EditOutcome _successOutcome({
    required DrawState state,
    required EditOperationId operationId,
  }) => (state: state, failureReason: null, operationId: operationId);

  T _runWithTextMetrics<T>(T Function() action) =>
      runWithScopedTextMetricsService(
        textMetricsService: textMetricsService,
        action: action,
      );

  EditOutcome _performStart({
    required DrawState state,
    required EditOperation operation,
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
    final nextApplication = state.application.copyWith(interaction: session);
    return _successOutcome(
      state: state.copyWith(application: nextApplication),
      operationId: operationId,
    );
  }

  EditOutcome _performUpdate({
    required DrawState state,
    required EditOperation operation,
    required EditingState editingState,
    required DrawPoint currentPosition,
    required EditModifiers modifiers,
  }) {
    _log?.trace('Edit session updated', {'operationId': operation.id});
    final updated = _runWithTextMetrics(
      () => operation.update(
        state: state,
        context: editingState.context,
        transform: editingState.currentTransform,
        currentPosition: currentPosition,
        modifiers: modifiers,
        config: configProvider(),
      ),
    );

    final transformUnchanged =
        updated.transform == editingState.currentTransform;
    final guidesUnchanged = snapGuideListEquals(
      updated.snapGuides,
      editingState.snapGuides,
    );
    if (transformUnchanged && guidesUnchanged) {
      return _successOutcome(
        state: state,
        operationId: editingState.operationId,
      );
    }

    return _successOutcome(
      state: state.copyWith(
        application: state.application.copyWith(
          interaction: editingState.withTransform(
            updated.transform,
            guides: updated.snapGuides,
          ),
        ),
      ),
      operationId: editingState.operationId,
    );
  }

  EditOutcome _performFinish({
    required DrawState state,
    required EditOperation operation,
    required EditingState editingState,
  }) {
    _log?.info('Edit session finished', {'operationId': operation.id});
    return _successOutcome(
      state: _runWithTextMetrics(
        () => operation.finish(
          state: state,
          context: editingState.context,
          transform: editingState.currentTransform,
        ),
      ),
      operationId: editingState.operationId,
    );
  }

  EditOutcome _performCancel({
    required DrawState state,
    required EditOperation operation,
    required EditingState editingState,
  }) {
    _log?.info('Edit session cancelled', {'operationId': operation.id});
    return _successOutcome(
      state: operation.cancel(state: state),
      operationId: editingState.operationId,
    );
  }

  EditingState _createSession({
    required EditOperation operation,
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
    final sessionData = _runWithTextMetrics(() {
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
      return (context: context, transform: transform);
    });
    return EditingState(
      operationId: operationId,
      sessionId: sessionId,
      context: sessionData.context,
      currentTransform: sessionData.transform,
    );
  }

  ({
    ({EditOperation operation, EditingState editingState})? session,
    EditFailureReason? failureReason,
  })
  _restoreSession(DrawState state, {bool validateVersions = false}) {
    final interaction = state.application.interaction;
    if (interaction is! EditingState) {
      _log?.error('Edit session restore failed', null, null, {
        'reason': 'not_editing',
      });
      return (session: null, failureReason: EditFailureReason.notEditing);
    }

    final operation = editOperations.getOperation(interaction.operationId);
    if (operation == null) {
      _log?.error('Edit session restore failed', null, null, {
        'operationId': interaction.operationId,
        'reason': 'unknown_operation',
      });
      return (
        session: null,
        failureReason: EditFailureReason.unknownOperationId,
      );
    }

    if (validateVersions) {
      final versionConflict = _resolveVersionConflict(
        editingState: interaction,
        currentState: state,
      );
      if (versionConflict case final reason?) {
        return (session: null, failureReason: reason);
      }
    }

    _log?.trace('Edit session restored', {
      'operationId': interaction.operationId,
      'sessionId': interaction.sessionId,
    });
    return (
      session: (operation: operation, editingState: interaction),
      failureReason: null,
    );
  }

  EditFailureReason? _resolveVersionConflict({
    required EditingState editingState,
    required DrawState currentState,
  }) {
    final context = editingState.context;
    final currentSelectionVersion =
        currentState.domain.selection.selectionVersion;
    if (context.selectionVersion != currentSelectionVersion) {
      _log?.warning('Edit session version conflict', {
        'operationId': editingState.operationId,
        'type': 'selection',
        'expected': context.selectionVersion,
        'actual': currentSelectionVersion,
      });
      return EditFailureReason.selectionChanged;
    }

    final currentElementsVersion = currentState.domain.document.elementsVersion;
    if (context.elementsVersion != currentElementsVersion) {
      _log?.warning('Edit session version conflict', {
        'operationId': editingState.operationId,
        'type': 'elements',
        'expected': context.elementsVersion,
        'actual': currentElementsVersion,
      });
      return EditFailureReason.elementsChanged;
    }
    return null;
  }
}
