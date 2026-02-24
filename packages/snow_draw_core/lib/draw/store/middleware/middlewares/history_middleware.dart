import '../../../actions/draw_actions.dart';
import '../../../actions/history_policy.dart';
import '../../../history/history_metadata.dart';
import '../../../history/recordable.dart';
import '../../../models/draw_state.dart';
import '../../../models/interaction_state.dart';
import '../history_recording_error.dart';
import '../middleware_base.dart';
import '../middleware_context.dart';

/// History middleware that manages undo/redo snapshots.
///
/// It handles:
/// - Recording snapshots for recordable actions
/// - Undo/redo operations
/// - History clearing
/// - Batch mode awareness
///
/// Note: This currently uses delta-based history.
/// Future enhancement: Migrate to Event Sourcing for even better performance.
class HistoryMiddleware extends MiddlewareBase {
  const HistoryMiddleware();

  @override
  String get name => 'History';

  @override
  int get priority => 400;

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) {
    final action = context.action;
    return switch (action) {
      Undo _ => _handleUndo(context, next),
      Redo _ => _handleRedo(context, next),
      ClearHistory _ => _handleClearHistory(context, next),
      _ => _handleRecordableAction(context, next),
    };
  }

  Future<DispatchContext> _handleClearHistory(
    DispatchContext context,
    NextFunction next,
  ) {
    context.drawContext.log.history.trace('History clear requested', {
      'traceId': context.traceId,
    });
    context.historyManager.clear();
    return next(context);
  }

  Future<DispatchContext> _handleRecordableAction(
    DispatchContext context,
    NextFunction next,
  ) async {
    final action = context.action;
    final log = context.drawContext.log.history;
    final policy = _resolveHistoryPolicy(context, action);
    if (policy != HistoryPolicy.record) {
      log.trace('History middleware skipped', {
        'action': action.runtimeType.toString(),
        'reason': 'policy',
        'policy': policy.name,
      });
      return next(context);
    }

    if (context.isBatching) {
      log.trace('History middleware skipped', {
        'action': action.runtimeType.toString(),
        'reason': 'batching',
      });
      return next(context);
    }

    final updatedContext = await next(context);
    _recordHistory(updatedContext, action);
    return updatedContext;
  }

  Future<DispatchContext> _handleUndo(
    DispatchContext context,
    NextFunction next,
  ) => _handleHistoryNavigation(
    context: context,
    next: next,
    actionName: 'undo',
    canNavigate: context.historyManager.canUndo,
    restore: context.historyManager.undo,
  );

  Future<DispatchContext> _handleRedo(
    DispatchContext context,
    NextFunction next,
  ) => _handleHistoryNavigation(
    context: context,
    next: next,
    actionName: 'redo',
    canNavigate: context.historyManager.canRedo,
    restore: context.historyManager.redo,
  );

  Future<DispatchContext> _handleHistoryNavigation({
    required DispatchContext context,
    required NextFunction next,
    required String actionName,
    required bool canNavigate,
    required DrawState? Function(DrawState currentState) restore,
  }) {
    context.drawContext.log.history.trace('History $actionName requested', {
      'traceId': context.traceId,
    });
    if (!canNavigate) {
      return next(context);
    }

    final restoredState = restore(context.currentState);
    if (restoredState == null) {
      return next(context);
    }

    return next(context.withCurrentState(restoredState));
  }

  void _recordHistory(DispatchContext context, DrawAction action) {
    final log = context.drawContext.log.history;
    final metadata = _buildMetadata(context, action);
    final includeSelection = context.includeSelectionInHistory;
    final coalescing = action.historyCoalescing;

    try {
      final snapshotBefore = context.snapshotBuilder.buildSnapshotFromState(
        state: context.initialState,
        includeSelection: includeSelection,
      );
      final snapshotAfter = context.snapshotBuilder.buildSnapshotFromState(
        state: context.currentState,
        includeSelection: includeSelection,
      );

      final recorded = context.historyManager.record(
        snapshotBefore,
        snapshotAfter,
        metadata: metadata,
        coalescing: coalescing,
        currentState: context.initialState,
      );
      log.trace('History record evaluated', {
        'action': action.runtimeType.toString(),
        'recorded': recorded,
        'description': metadata?.description,
        'coalescingKey': coalescing?.key,
        'traceId': context.traceId,
      });
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        HistoryRecordingError(
          action: action.runtimeType.toString(),
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  HistoryPolicy _resolveHistoryPolicy(
    DispatchContext context,
    DrawAction action,
  ) {
    if (action is FinishEdit &&
        _metadataFromFinishEdit(context, action) == null) {
      return HistoryPolicy.none;
    }
    return action.historyPolicy;
  }

  HistoryMetadata? _buildMetadata(DispatchContext context, DrawAction action) =>
      switch (action) {
        final FinishTextEdit finishTextEdit => _metadataFromFinishTextEdit(
          finishTextEdit,
        ),
        final FinishEdit finishEdit => _metadataFromFinishEdit(
          context,
          finishEdit,
        ),
        final Recordable recordable => HistoryMetadata(
          description: recordable.historyDescription,
          recordType: recordable.recordType,
        ),
        _ => null,
      };

  HistoryMetadata? _metadataFromFinishEdit(
    DispatchContext context,
    FinishEdit action,
  ) => action.metadata ?? _metadataFromEdit(context);

  HistoryMetadata? _metadataFromFinishTextEdit(FinishTextEdit action) {
    final kind = _resolveFinishTextEditOutcomeKind(action);
    return switch (kind) {
      _FinishTextEditOutcomeKind.delete => HistoryMetadata(
        description: 'Delete text',
        recordType: HistoryRecordType.delete,
      ),
      _FinishTextEditOutcomeKind.create => HistoryMetadata(
        description: 'Create text',
        recordType: HistoryRecordType.create,
      ),
      _FinishTextEditOutcomeKind.edit => HistoryMetadata(
        description: 'Edit text',
        recordType: HistoryRecordType.edit,
      ),
      _FinishTextEditOutcomeKind.noop => null,
    };
  }

  _FinishTextEditOutcomeKind _resolveFinishTextEditOutcomeKind(
    FinishTextEdit action,
  ) {
    final hasText = action.text.trim().isNotEmpty;
    return switch ((action.isNew, hasText)) {
      (true, false) => _FinishTextEditOutcomeKind.noop,
      (false, false) => _FinishTextEditOutcomeKind.delete,
      (true, true) => _FinishTextEditOutcomeKind.create,
      (false, true) => _FinishTextEditOutcomeKind.edit,
    };
  }

  HistoryMetadata? _metadataFromEdit(DispatchContext context) {
    final interaction = context.initialState.application.interaction;
    if (interaction is! EditingState) {
      return null;
    }

    final operation = context.drawContext.editOperations.getOperation(
      interaction.operationId,
    );
    if (operation == null || !operation.recordsHistory) {
      return null;
    }

    return operation.createHistoryMetadata(
      context: interaction.context,
      transform: interaction.currentTransform,
    );
  }
}

enum _FinishTextEditOutcomeKind { create, edit, delete, noop }
