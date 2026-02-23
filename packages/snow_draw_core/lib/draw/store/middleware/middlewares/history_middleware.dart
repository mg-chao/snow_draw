import '../../../actions/draw_actions.dart';
import '../../../actions/history_policy.dart';
import '../../../elements/types/arrow/arrow_like_data.dart';
import '../../../elements/types/serial_number/serial_number_data.dart';
import '../../../history/history_metadata.dart';
import '../../../history/recordable.dart';
import '../../../models/element_state.dart';
import '../../../models/interaction_state.dart';
import '../../history_change_set.dart';
import '../../snapshot.dart';
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
  bool shouldExecute(DispatchContext context) {
    final action = context.action;
    final log = context.drawContext.log.history;

    if (action is Undo || action is Redo || action is ClearHistory) {
      log.trace('History middleware executing', {
        'action': action.runtimeType.toString(),
        'traceId': context.traceId,
      });
      return true;
    }

    final policy = _resolveHistoryPolicy(context, action);
    if (policy != HistoryPolicy.record) {
      log.trace('History middleware skipped', {
        'action': action.runtimeType.toString(),
        'reason': 'policy',
        'policy': policy.name,
      });
      return false;
    }

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
    switch (action) {
      case Undo _:
        return _handleUndo(context, next);
      case Redo _:
        return _handleRedo(context, next);
      case ClearHistory _:
        context.drawContext.log.history.trace('History clear requested', {
          'traceId': context.traceId,
        });
        context.historyManager.clear();
        return next(context);
      default:
        final updatedContext = await next(context);
        _recordHistory(updatedContext, action);
        return updatedContext;
    }
  }

  Future<DispatchContext> _handleUndo(
    DispatchContext context,
    NextFunction next,
  ) {
    context.drawContext.log.history.trace('History undo requested', {
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
    context.drawContext.log.history.trace('History redo requested', {
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
    final coalescing = action.historyCoalescing;

    try {
      final useIncremental =
          changes != null &&
          !_requiresPersistentSnapshots(action: action, changes: changes);

      final snapshotBefore = _buildSnapshotBefore(
        context: context,
        action: action,
        changes: changes,
        includeSelection: includeSelection,
        useIncremental: useIncremental,
      );
      final snapshotAfter = _buildSnapshotAfter(
        context: context,
        changes: changes,
        includeSelection: includeSelection,
        useIncremental: useIncremental,
      );

      final recorded = context.historyManager.record(
        snapshotBefore,
        snapshotAfter,
        metadata: metadata,
        changes: changes,
        coalescing: coalescing,
        currentState: context.initialState,
        nextState: context.currentState,
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

  HistorySnapshot _buildSnapshotBefore({
    required DispatchContext context,
    required DrawAction action,
    required HistoryChangeSet? changes,
    required bool includeSelection,
    required bool useIncremental,
  }) {
    if (useIncremental) {
      final resolvedChanges = changes!;
      if (action.requiresPreActionSnapshot) {
        return context.snapshotBuilder.buildIncrementalSnapshotBeforeAction(
          currentState: context.initialState,
          action: action,
          changes: resolvedChanges,
          includeSelection: includeSelection,
        );
      }
      return context.snapshotBuilder.buildIncrementalSnapshotFromState(
        state: context.initialState,
        changes: resolvedChanges,
        includeSelection: includeSelection,
      );
    }

    if (action.requiresPreActionSnapshot) {
      return context.snapshotBuilder.buildSnapshotBeforeAction(
        currentState: context.initialState,
        action: action,
        includeSelection: includeSelection,
      );
    }

    return PersistentSnapshot.fromState(
      context.initialState,
      includeSelection: includeSelection,
    );
  }

  HistorySnapshot _buildSnapshotAfter({
    required DispatchContext context,
    required HistoryChangeSet? changes,
    required bool includeSelection,
    required bool useIncremental,
  }) {
    if (useIncremental) {
      return context.snapshotBuilder.buildIncrementalSnapshotFromState(
        state: context.currentState,
        changes: changes!,
        includeSelection: includeSelection,
      );
    }

    return PersistentSnapshot.fromState(
      context.currentState,
      includeSelection: includeSelection,
    );
  }

  HistoryPolicy _resolveHistoryPolicy(
    DispatchContext context,
    DrawAction action,
  ) {
    if (action is FinishEdit && _metadataFromEdit(context) == null) {
      return HistoryPolicy.none;
    }
    return switch (action) {
      Recordable _ => HistoryPolicy.record,
      NonRecordable _ => HistoryPolicy.none,
      _ => action.historyPolicy,
    };
  }

  HistoryMetadata? _buildMetadata(DispatchContext context, DrawAction action) =>
      switch (action) {
        final FinishTextEdit finishTextEdit => _metadataFromFinishTextEdit(
          context,
          finishTextEdit,
        ),
        final FinishEdit finishEdit =>
          finishEdit.metadata ?? _metadataFromEdit(context),
        final Recordable recordable => HistoryMetadata(
          description: recordable.historyDescription,
          recordType: recordable.recordType,
        ),
        _ => null,
      };

  HistoryMetadata _metadataFromFinishTextEdit(
    DispatchContext context,
    FinishTextEdit action,
  ) {
    final resolved = _resolveFinishTextEditPayload(context, action);
    final trimmed = resolved.text.trim();
    final isDelete = trimmed.isEmpty && !resolved.isNew;
    final isCreate = resolved.isNew;

    return HistoryMetadata(
      description: isDelete
          ? 'Delete text'
          : isCreate
          ? 'Create text'
          : 'Edit text',
      recordType: isDelete
          ? HistoryRecordType.delete
          : isCreate
          ? HistoryRecordType.create
          : HistoryRecordType.edit,
    );
  }

  ({String elementId, bool isNew, String text}) _resolveFinishTextEditPayload(
    DispatchContext context,
    FinishTextEdit action,
  ) {
    final interaction = context.initialState.application.interaction;
    if (interaction is TextEditingState) {
      return (
        elementId: interaction.elementId,
        isNew: interaction.isNew,
        text: action.text,
      );
    }

    return (
      elementId: action.elementId,
      isNew: action.isNew,
      text: action.text,
    );
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
    final selectionChanged = _selectionChanged(context);
    final actionChangeSet = switch (action) {
      FinishEdit _ => _buildFinishEditChangeSet(
        context: context,
        metadata: metadata,
        selectionChanged: selectionChanged,
      ),
      final ChangeElementZIndex zIndex => _buildZIndexChangeSet(
        context: context,
        elementIds: {zIndex.elementId},
        selectionChanged: selectionChanged,
      ),
      final ChangeElementsZIndex zIndices => _buildZIndexChangeSet(
        context: context,
        elementIds: zIndices.elementIds.toSet(),
        selectionChanged: selectionChanged,
      ),
      final DeleteElements delete => _buildDeleteElementsChangeSet(
        context: context,
        action: delete,
        selectionChanged: selectionChanged,
      ),
      FinishCreateElement _ => _buildFinishCreateElementChangeSet(
        context: context,
        selectionChanged: selectionChanged,
      ),
      final FinishTextEdit finishTextEdit => _buildFinishTextEditChangeSet(
        context: context,
        action: finishTextEdit,
        selectionChanged: selectionChanged,
      ),
      UpdateGlobalElements _ => HistoryChangeSet(
        globalElementsChanged: true,
        selectionChanged: selectionChanged,
      ),
      DuplicateElements _ => _buildDuplicateElementsChangeSet(
        context: context,
        selectionChanged: selectionChanged,
      ),
      _ => null,
    };

    return actionChangeSet ??
        _buildMetadataChangeSet(
          metadata: metadata,
          selectionChanged: selectionChanged,
        );
  }

  bool _selectionChanged(DispatchContext context) =>
      context.includeSelectionInHistory &&
      context.initialState.domain.selection !=
          context.currentState.domain.selection;

  HistoryChangeSet? _buildFinishEditChangeSet({
    required DispatchContext context,
    required HistoryMetadata? metadata,
    required bool selectionChanged,
  }) {
    final affected = metadata?.affectedElementIds ?? const <String>{};
    if (affected.isEmpty) {
      return null;
    }

    final expandedAffectedIds = _expandModifiedIdsForArrowBindings(
      elements: context.initialState.domain.document.elements,
      modifiedIds: affected,
    );
    return HistoryChangeSet(
      modifiedIds: expandedAffectedIds,
      selectionChanged: selectionChanged,
    );
  }

  HistoryChangeSet _buildZIndexChangeSet({
    required DispatchContext context,
    required Set<String> elementIds,
    required bool selectionChanged,
  }) {
    final reordered = _didElementOrderChange(context);
    return HistoryChangeSet(
      modifiedIds: elementIds,
      orderChanged: true,
      selectionChanged: selectionChanged,
      reindexZIndices: reordered,
    );
  }

  HistoryChangeSet _buildDeleteElementsChangeSet({
    required DispatchContext context,
    required DeleteElements action,
    required bool selectionChanged,
  }) {
    final beforeElements = context.initialState.domain.document.elements;
    final removedIds = action.elementIds.toSet();
    _expandDeleteIdsForBoundSerialText(
      elements: beforeElements,
      removedIds: removedIds,
    );
    final modifiedIds = <String>{};
    for (final element in beforeElements) {
      if (removedIds.contains(element.id)) {
        continue;
      }
      final data = element.data;
      if (data is SerialNumberData) {
        final boundId = data.textElementId;
        if (boundId != null && removedIds.contains(boundId)) {
          modifiedIds.add(element.id);
        }
      }
      if (_isArrowBoundToAny(data: data, targetIds: removedIds)) {
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

  HistoryChangeSet? _buildFinishCreateElementChangeSet({
    required DispatchContext context,
    required bool selectionChanged,
  }) {
    final interaction = context.initialState.application.interaction;
    if (interaction is! CreatingState) {
      return null;
    }
    return HistoryChangeSet(
      addedIds: {interaction.elementId},
      orderChanged: true,
      selectionChanged: selectionChanged,
    );
  }

  HistoryChangeSet? _buildFinishTextEditChangeSet({
    required DispatchContext context,
    required FinishTextEdit action,
    required bool selectionChanged,
  }) {
    final resolved = _resolveFinishTextEditPayload(context, action);
    final trimmed = resolved.text.trim();
    if (trimmed.isEmpty) {
      if (resolved.isNew) {
        return null;
      }
      final modifiedIds = _dependentIdsBoundToDeletedText(
        elements: context.initialState.domain.document.elements,
        textElementId: resolved.elementId,
      );
      return HistoryChangeSet(
        modifiedIds: modifiedIds,
        removedIds: {resolved.elementId},
        orderChanged: true,
        selectionChanged: selectionChanged,
      );
    }

    if (resolved.isNew) {
      return HistoryChangeSet(
        addedIds: {resolved.elementId},
        orderChanged: true,
        selectionChanged: selectionChanged,
      );
    }

    return HistoryChangeSet(
      modifiedIds: {resolved.elementId},
      selectionChanged: selectionChanged,
    );
  }

  HistoryChangeSet? _buildDuplicateElementsChangeSet({
    required DispatchContext context,
    required bool selectionChanged,
  }) {
    final addedIds = _addedElementIds(
      before: context.initialState.domain.document.elements,
      after: context.currentState.domain.document.elements,
    );
    if (addedIds.isEmpty) {
      return null;
    }
    return HistoryChangeSet(
      addedIds: addedIds,
      orderChanged: true,
      selectionChanged: selectionChanged,
    );
  }

  HistoryChangeSet? _buildMetadataChangeSet({
    required HistoryMetadata? metadata,
    required bool selectionChanged,
  }) {
    final affected = metadata?.affectedElementIds ?? const <String>{};
    if (affected.isEmpty) {
      return null;
    }
    return HistoryChangeSet(
      modifiedIds: affected,
      selectionChanged: selectionChanged,
    );
  }

  bool _requiresPersistentSnapshots({
    required DrawAction action,
    required HistoryChangeSet changes,
  }) =>
      (action is ChangeElementZIndex || action is ChangeElementsZIndex) &&
      !changes.reindexZIndices;

  bool _didElementOrderChange(DispatchContext context) {
    final before = context.initialState.domain.document.elements;
    final after = context.currentState.domain.document.elements;
    if (before.length != after.length) {
      return true;
    }
    for (var index = 0; index < before.length; index++) {
      if (before[index].id != after[index].id) {
        return true;
      }
    }
    return false;
  }

  Set<String> _expandModifiedIdsForArrowBindings({
    required Iterable<ElementState> elements,
    required Set<String> modifiedIds,
  }) {
    final expandedIds = <String>{...modifiedIds};
    for (final element in elements) {
      if (expandedIds.contains(element.id)) {
        continue;
      }
      if (_isArrowBoundToAny(data: element.data, targetIds: modifiedIds)) {
        expandedIds.add(element.id);
      }
    }
    return expandedIds;
  }

  Set<String> _addedElementIds({
    required Iterable<ElementState> before,
    required Iterable<ElementState> after,
  }) {
    final beforeIds = <String>{for (final element in before) element.id};
    return {
      for (final element in after)
        if (!beforeIds.contains(element.id)) element.id,
    };
  }

  void _expandDeleteIdsForBoundSerialText({
    required Iterable<ElementState> elements,
    required Set<String> removedIds,
  }) {
    var changed = true;
    while (changed) {
      changed = false;
      for (final element in elements) {
        if (!removedIds.contains(element.id)) {
          continue;
        }
        final data = element.data;
        if (data is! SerialNumberData) {
          continue;
        }
        final boundId = data.textElementId;
        if (boundId == null) {
          continue;
        }
        if (removedIds.add(boundId)) {
          changed = true;
        }
      }
    }
  }

  bool _isArrowBoundToAny({
    required Object data,
    required Set<String> targetIds,
  }) {
    if (data is! ArrowLikeData) {
      return false;
    }
    final startTarget = data.startBinding?.elementId;
    final endTarget = data.endBinding?.elementId;
    return (startTarget != null && targetIds.contains(startTarget)) ||
        (endTarget != null && targetIds.contains(endTarget));
  }

  Set<String> _dependentIdsBoundToDeletedText({
    required Iterable<ElementState> elements,
    required String textElementId,
  }) {
    final deletedIds = <String>{textElementId};
    final ids = <String>{};
    for (final element in elements) {
      final data = element.data;
      if (data is SerialNumberData && data.textElementId == textElementId) {
        ids.add(element.id);
        continue;
      }
      if (_isArrowBoundToAny(data: data, targetIds: deletedIds)) {
        ids.add(element.id);
      }
    }
    return ids;
  }
}
