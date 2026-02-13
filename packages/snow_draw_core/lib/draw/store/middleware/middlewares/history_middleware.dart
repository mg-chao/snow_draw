import '../../../actions/draw_actions.dart';
import '../../../actions/history_policy.dart';
import '../../../elements/types/serial_number/serial_number_data.dart';
import '../../../history/history_metadata.dart';
import '../../../history/recordable.dart';
import '../../../models/interaction_state.dart';
import '../../history_change_set.dart';
import '../../snapshot.dart';
import '../history_recording_error.dart';
import '../middleware_base.dart';
import '../middleware_context.dart';

const _skipHistoryMetadataKey = 'skipHistoryRecording';

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
  int get priority => 400; // Medium-high priority - after reduction

  @override
  bool shouldExecute(DispatchContext context) {
    final action = context.action;
    final log = context.drawContext.log.history;

    // Always execute for undo/redo/clear
    if (action is Undo || action is Redo || action is ClearHistory) {
      log.trace('History middleware executing', {
        'action': action.runtimeType.toString(),
        'traceId': context.traceId,
      });
      return true;
    }

    final skipHistory =
        context.getMetadata<bool>(_skipHistoryMetadataKey) ?? false;
    if (skipHistory) {
      log.warning('History middleware skipped', {
        'action': action.runtimeType.toString(),
        'reason': 'fallback',
        'traceId': context.traceId,
      });
      return false;
    }

    // Check if we should record history
    final policy = _resolveHistoryPolicy(context, action);
    if (policy == HistoryPolicy.skip || policy != HistoryPolicy.record) {
      log.trace('History middleware skipped', {
        'action': action.runtimeType.toString(),
        'reason': 'policy',
        'policy': policy.name,
      });
      return false;
    }

    // Don't record during batching
    if (context.isBatching) {
      log.trace('History middleware skipped', {
        'action': action.runtimeType.toString(),
        'reason': 'batching',
      });
      return false;
    }

    return true;
  }

  @override
  Future<DispatchContext> invoke(
    DispatchContext context,
    NextFunction next,
  ) async {
    final action = context.action;

    // Handle undo
    if (action is Undo) {
      return _handleUndo(context, next);
    }

    // Handle redo
    if (action is Redo) {
      return _handleRedo(context, next);
    }

    // Handle clear history
    if (action is ClearHistory) {
      context.drawContext.log.history.info('History clear requested', {
        'traceId': context.traceId,
      });
      context.historyManager.clear();
      return next(context);
    }

    // Record history after other middlewares execute
    final updatedContext = await next(context);
    _recordHistory(updatedContext, action);
    return updatedContext;
  }

  Future<DispatchContext> _handleUndo(
    DispatchContext context,
    NextFunction next,
  ) {
    context.drawContext.log.history.info('History undo requested', {
      'traceId': context.traceId,
    });
    if (!context.historyManager.canUndo) {
      return next(context);
    }

    // Apply undo delta to current state (after reduction).
    final restoredState = context.historyManager.undo(context.currentState);
    if (restoredState == null) {
      return next(context);
    }

    // Update context with restored state
    final updatedContext = context.withCurrentState(restoredState);
    return next(updatedContext);
  }

  Future<DispatchContext> _handleRedo(
    DispatchContext context,
    NextFunction next,
  ) {
    context.drawContext.log.history.info('History redo requested', {
      'traceId': context.traceId,
    });
    if (!context.historyManager.canRedo) {
      return next(context);
    }

    // Apply redo delta to current state (after reduction).
    final restoredState = context.historyManager.redo(context.currentState);
    if (restoredState == null) {
      return next(context);
    }

    // Update context with restored state
    final updatedContext = context.withCurrentState(restoredState);
    return next(updatedContext);
  }

  void _recordHistory(DispatchContext context, DrawAction action) {
    final log = context.drawContext.log.history;
    final metadata = _buildMetadata(context, action);
    final changes = _buildChangeSet(context, action, metadata);
    final includeSelection = context.includeSelectionInHistory;

    try {
      // Reordering a single element can still mutate many peers (for example
      // z-index reindexing), so those transitions use full snapshots.
      final useIncremental =
          changes != null &&
          !(changes.orderChanged && changes.isSingleElementChange);

      // Take snapshot before action
      final snapshotBefore = useIncremental
          ? (action.requiresPreActionSnapshot
                ? context.snapshotBuilder.buildIncrementalSnapshotBeforeAction(
                    currentState: context.initialState,
                    action: action,
                    changes: changes,
                    includeSelection: includeSelection,
                  )
                : context.snapshotBuilder.buildIncrementalSnapshotFromState(
                    state: context.initialState,
                    changes: changes,
                    includeSelection: includeSelection,
                  ))
          : (action.requiresPreActionSnapshot
                ? context.snapshotBuilder.buildSnapshotBeforeAction(
                    currentState: context.initialState,
                    action: action,
                    includeSelection: includeSelection,
                  )
                : PersistentSnapshot.fromState(
                    context.initialState,
                    includeSelection: includeSelection,
                  ));

      // Take snapshot after action
      final snapshotAfter = useIncremental
          ? context.snapshotBuilder.buildIncrementalSnapshotFromState(
              state: context.currentState,
              changes: changes,
              includeSelection: includeSelection,
            )
          : PersistentSnapshot.fromState(
              context.currentState,
              includeSelection: includeSelection,
            );

      final recorded = context.historyManager.record(
        snapshotBefore,
        snapshotAfter,
        metadata: metadata,
        changes: changes,
      );
      log.debug('History record evaluated', {
        'action': action.runtimeType.toString(),
        'recorded': recorded,
        'description': metadata?.description,
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
    if (action is Recordable) {
      if (action is FinishEdit) {
        final metadata = _metadataFromEdit(context);
        if (metadata == null) {
          return HistoryPolicy.none;
        }
      }
      return HistoryPolicy.record;
    }
    if (action is NonRecordable) {
      return HistoryPolicy.none;
    }
    return action.historyPolicy;
  }

  HistoryMetadata? _buildMetadata(DispatchContext context, DrawAction action) {
    if (action is FinishEdit) {
      return action.metadata ?? _metadataFromEdit(context);
    }

    if (action is Recordable) {
      final recordable = action as Recordable;
      return HistoryMetadata(
        description: recordable.historyDescription,
        recordType: recordable.recordType,
      );
    }

    return null;
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

  HistoryChangeSet? _buildChangeSet(
    DispatchContext context,
    DrawAction action,
    HistoryMetadata? metadata,
  ) {
    final selectionChanged =
        context.includeSelectionInHistory &&
        context.initialState.domain.selection !=
            context.currentState.domain.selection;

    if (action is FinishEdit) {
      final affected = metadata?.affectedElementIds ?? const <String>{};
      if (affected.isNotEmpty) {
        return HistoryChangeSet(
          modifiedIds: affected,
          selectionChanged: selectionChanged,
        );
      }
      return null;
    }

    if (action is ChangeElementZIndex) {
      return HistoryChangeSet(
        modifiedIds: {action.elementId},
        orderChanged: true,
        selectionChanged: selectionChanged,
      );
    }

    if (action is DeleteElements) {
      final removedIds = action.elementIds.toSet();
      final modifiedIds = <String>{};
      final beforeElements = context.initialState.domain.document.elements;
      for (final element in beforeElements) {
        final data = element.data;
        if (data is! SerialNumberData) {
          continue;
        }
        final boundId = data.textElementId;
        if (boundId == null) {
          continue;
        }
        if (removedIds.contains(element.id)) {
          removedIds.add(boundId);
          continue;
        }
        if (removedIds.contains(boundId)) {
          modifiedIds.add(element.id);
        }
      }
      return HistoryChangeSet(
        modifiedIds: modifiedIds,
        removedIds: removedIds,
        orderChanged: true,
        selectionChanged: selectionChanged,
      );
    }

    if (action is FinishCreateElement) {
      final interaction = context.initialState.application.interaction;
      if (interaction is CreatingState) {
        return HistoryChangeSet(
          addedIds: {interaction.elementId},
          orderChanged: true,
          selectionChanged: selectionChanged,
        );
      }
      return null;
    }

    if (action is FinishTextEdit) {
      final trimmed = action.text.trim();
      if (trimmed.isEmpty) {
        if (action.isNew) {
          return null;
        }
        return HistoryChangeSet(
          removedIds: {action.elementId},
          orderChanged: true,
          selectionChanged: selectionChanged,
        );
      }
      if (action.isNew) {
        return HistoryChangeSet(
          addedIds: {action.elementId},
          orderChanged: true,
          selectionChanged: selectionChanged,
        );
      }
      return HistoryChangeSet(
        modifiedIds: {action.elementId},
        selectionChanged: selectionChanged,
      );
    }

    if (action is DuplicateElements) {
      return null;
    }

    final affected = metadata?.affectedElementIds ?? const <String>{};
    if (affected.isNotEmpty) {
      return HistoryChangeSet(
        modifiedIds: affected,
        selectionChanged: selectionChanged,
      );
    }

    return null;
  }
}
