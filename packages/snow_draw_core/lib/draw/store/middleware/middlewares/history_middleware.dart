import '../../../actions/draw_actions.dart';
import '../../../actions/history_policy.dart';
import '../../../elements/types/serial_number/serial_number_dependencies.dart';
import '../../../history/history_metadata.dart';
import '../../../history/recordable.dart';
import '../../../models/draw_state.dart';
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
    if (action.requiresPreActionSnapshot) {
      if (useIncremental) {
        final resolvedChanges = changes!;
        return context.snapshotBuilder.buildIncrementalSnapshotBeforeAction(
          currentState: context.initialState,
          action: action,
          changes: resolvedChanges,
          includeSelection: includeSelection,
        );
      }
      return context.snapshotBuilder.buildSnapshotBeforeAction(
        currentState: context.initialState,
        action: action,
        includeSelection: includeSelection,
      );
    }

    return _buildSnapshotFromState(
      context: context,
      state: context.initialState,
      changes: changes,
      includeSelection: includeSelection,
      useIncremental: useIncremental,
    );
  }

  HistorySnapshot _buildSnapshotAfter({
    required DispatchContext context,
    required HistoryChangeSet? changes,
    required bool includeSelection,
    required bool useIncremental,
  }) => _buildSnapshotFromState(
    context: context,
    state: context.currentState,
    changes: changes,
    includeSelection: includeSelection,
    useIncremental: useIncremental,
  );

  HistorySnapshot _buildSnapshotFromState({
    required DispatchContext context,
    required DrawState state,
    required HistoryChangeSet? changes,
    required bool includeSelection,
    required bool useIncremental,
  }) {
    if (useIncremental) {
      return context.snapshotBuilder.buildIncrementalSnapshotFromState(
        state: state,
        changes: changes!,
        includeSelection: includeSelection,
      );
    }

    return PersistentSnapshot.fromState(
      state,
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

  HistoryMetadata? _metadataFromFinishTextEdit(
    DispatchContext context,
    FinishTextEdit action,
  ) {
    final outcome = _resolveFinishTextEditOutcome(context, action);
    return switch (outcome.kind) {
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

  ({String elementId, _FinishTextEditOutcomeKind kind})
  _resolveFinishTextEditOutcome(
    DispatchContext context,
    FinishTextEdit action,
  ) {
    final payload = _resolveFinishTextEditPayload(context, action);
    final hasText = payload.text.trim().isNotEmpty;
    final kind = switch ((payload.isNew, hasText)) {
      (true, false) => _FinishTextEditOutcomeKind.noop,
      (false, false) => _FinishTextEditOutcomeKind.delete,
      (true, true) => _FinishTextEditOutcomeKind.create,
      (false, true) => _FinishTextEditOutcomeKind.edit,
    };
    return (elementId: payload.elementId, kind: kind);
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

  HistoryChangeSet? _buildDeleteElementsChangeSet({
    required DispatchContext context,
    required DeleteElements action,
    required bool selectionChanged,
  }) {
    final document = context.initialState.domain.document;
    final beforeElements = context.initialState.domain.document.elements;
    final removedIds = expandSerialNumberBoundTextIds(
      elements: beforeElements,
      seedIds: action.elementIds.where(document.elementMap.containsKey),
    );
    if (removedIds.isEmpty) {
      return selectionChanged ? HistoryChangeSet(selectionChanged: true) : null;
    }
    final modifiedIds = collectDependentElementIds(
      elements: beforeElements,
      targetIds: removedIds,
      excludedIds: removedIds,
    );
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
    final outcome = _resolveFinishTextEditOutcome(context, action);
    return switch (outcome.kind) {
      _FinishTextEditOutcomeKind.delete => HistoryChangeSet(
        modifiedIds: _dependentIdsBoundToDeletedText(
          elements: context.initialState.domain.document.elements,
          textElementId: outcome.elementId,
        ),
        removedIds: {outcome.elementId},
        orderChanged: true,
        selectionChanged: selectionChanged,
      ),
      _FinishTextEditOutcomeKind.create => HistoryChangeSet(
        addedIds: {outcome.elementId},
        orderChanged: true,
        selectionChanged: selectionChanged,
      ),
      _FinishTextEditOutcomeKind.edit => HistoryChangeSet(
        modifiedIds: {outcome.elementId},
        selectionChanged: selectionChanged,
      ),
      _FinishTextEditOutcomeKind.noop => null,
    };
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
  }) => {
    ...modifiedIds,
    ...collectDependentElementIds(
      elements: elements,
      targetIds: modifiedIds,
      excludedIds: modifiedIds,
      includeSerialBindings: false,
    ),
  };

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

  Set<String> _dependentIdsBoundToDeletedText({
    required Iterable<ElementState> elements,
    required String textElementId,
  }) => collectDependentElementIds(
    elements: elements,
    targetIds: {textElementId},
    excludedIds: {textElementId},
  );
}

enum _FinishTextEditOutcomeKind { create, edit, delete, noop }
