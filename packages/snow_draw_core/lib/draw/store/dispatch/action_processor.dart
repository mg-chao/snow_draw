import 'dart:async';
import 'dart:collection';

import '../../actions/config_actions.dart';
import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../edit/core/edit_cancel_reason.dart';
import '../../edit/core/edit_event_factory.dart';
import '../../edit/core/edit_session_id_generator.dart';
import '../../edit/core/edit_session_service.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../events/edit_events.dart';
import '../../events/error_events.dart';
import '../../events/event_bus.dart';
import '../../events/state_events.dart';
import '../../models/draw_state.dart';
import '../../models/interaction_state.dart';
import '../config_manager.dart';
import '../history_manager.dart';
import '../listener_registry.dart';
import '../middleware/middleware_context.dart';
import '../middleware/middleware_pipeline.dart';
import '../snapshot_builder.dart';
import '../state_manager.dart';

class ActionProcessorServices {
  const ActionProcessorServices({
    required this.drawContext,
    required this.stateManager,
    required this.historyManager,
    required this.configManager,
    required this.listenerRegistry,
    required this.snapshotBuilder,
    required this.editSessionService,
    required this.sessionIdGenerator,
    required this.isBatching,
    required this.includeSelectionInHistory,
    required this.eventBus,
    required this.publishEditEvents,
  });
  final InteractionReducerDeps drawContext;
  final StateManager stateManager;
  final HistoryManager historyManager;
  final ConfigManager configManager;
  final ListenerRegistry listenerRegistry;
  final SnapshotBuilder snapshotBuilder;
  final EditSessionService editSessionService;
  final EditSessionIdGenerator sessionIdGenerator;
  final bool Function() isBatching;
  final bool includeSelectionInHistory;
  final EventBus eventBus;
  final void Function(List<EditSessionEvent> events) publishEditEvents;
}

class ActionProcessor {
  ActionProcessor({
    required ActionProcessorServices services,
    required MiddlewarePipeline pipeline,
  }) : _services = services,
       _pipeline = pipeline,
       _lastCanUndo = services.historyManager.canUndo,
       _lastCanRedo = services.historyManager.canRedo;
  final ActionProcessorServices _services;
  final MiddlewarePipeline _pipeline;
  final _queue = Queue<_DispatchTask>();
  bool _lastCanUndo;
  bool _lastCanRedo;

  var _isProcessing = false;
  var _isDisposed = false;

  DrawState get state => _services.stateManager.current;

  bool get isDisposed => _isDisposed;

  Future<void> dispatch(DrawAction action) =>
      _enqueue(() => _processWithExplicitCancel(action));

  void syncHistoryAvailability({bool emitIfChanged = false}) {
    final canUndo = _services.historyManager.canUndo;
    final canRedo = _services.historyManager.canRedo;
    final changed = canUndo != _lastCanUndo || canRedo != _lastCanRedo;

    _lastCanUndo = canUndo;
    _lastCanRedo = canRedo;

    if (!emitIfChanged || !changed || !_services.eventBus.hasListeners) {
      return;
    }

    _services.eventBus.emit(
      HistoryAvailabilityChangedEvent(canUndo: canUndo, canRedo: canRedo),
    );
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;

    for (final task in List<_DispatchTask>.from(_queue)) {
      task.completeWithError(
        StateError('Dispatch queue disposed while pending'),
      );
    }
    _queue.clear();
  }

  Future<void> _enqueue(Future<void> Function() task) {
    if (_isDisposed) {
      return Future.error(StateError('Dispatch queue has been disposed'));
    }

    final queued = _DispatchTask(task);
    _queue.addLast(queued);

    if (!_isProcessing) {
      unawaited(_drainQueue());
    }

    return queued.completer.future;
  }

  Future<void> _drainQueue() async {
    _isProcessing = true;
    try {
      while (_queue.isNotEmpty) {
        final next = _queue.removeFirst();
        await next.run();
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processWithExplicitCancel(DrawAction action) async {
    final cancelReason = _resolveEditCancelReason(action);
    if (cancelReason != null) {
      await _process(CancelEdit(reason: cancelReason));
    }
    await _process(action);
  }

  Future<void> _process(DrawAction action) async {
    if (_handleConfigAction(action)) {
      return;
    }

    _services.configManager.freeze();
    try {
      final initialContext = DispatchContext.initial(
        action: action,
        state: _services.stateManager.current,
        drawContext: _services.drawContext,
        historyManager: _services.historyManager,
        snapshotBuilder: _services.snapshotBuilder,
        editSessionService: _services.editSessionService,
        sessionIdGenerator: _services.sessionIdGenerator,
        isBatching: _services.isBatching(),
        includeSelectionInHistory: _services.includeSelectionInHistory,
      );

      DispatchContext finalContext;
      try {
        finalContext = await _pipeline.execute(initialContext);
      } on Object catch (error, stackTrace) {
        finalContext = initialContext.withError(
          error,
          stackTrace,
          source: 'Pipeline',
        );
      }

      if (finalContext.hasError) {
        final error =
            finalContext.error ?? StateError('Dispatch error without detail');
        final stackTrace = finalContext.stackTrace ?? StackTrace.current;

        _reportError(action, error, stackTrace, finalContext);

        if (action.criticality == ActionCriticality.critical) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        return;
      }

      _commit(initialContext: initialContext, finalContext: finalContext);
    } finally {
      _services.configManager.unfreeze();
    }
  }

  bool _handleConfigAction(DrawAction action) {
    if (action is UpdateConfig) {
      _services.configManager.update(action.config);
      return true;
    }
    if (action is UpdateSelectionConfig) {
      _services.configManager.updateSelection(action.selection);
      return true;
    }
    if (action is UpdateCanvasConfig) {
      _services.configManager.updateCanvas(action.canvas);
      return true;
    }
    return false;
  }

  EditCancelReason? _resolveEditCancelReason(DrawAction action) {
    final state = _services.stateManager.current;
    if (!state.application.isEditing) {
      return null;
    }

    if (action is CancelEdit || action is UpdateEdit || action is FinishEdit) {
      return null;
    }

    if (action is StartEdit || action is EditIntentAction) {
      return EditCancelReason.newEditStarted;
    }

    if (action is Undo) {
      return _services.historyManager.canUndo
          ? EditCancelReason.conflictingAction
          : null;
    }

    if (action is Redo) {
      return _services.historyManager.canRedo
          ? EditCancelReason.conflictingAction
          : null;
    }

    return action.conflictsWithEditing
        ? EditCancelReason.conflictingAction
        : null;
  }

  void _commit({
    required DispatchContext initialContext,
    required DispatchContext finalContext,
  }) {
    if (finalContext.hasStateChanged) {
      _services.stateManager.update(finalContext.currentState);

      if (!_services.isBatching()) {
        _services.listenerRegistry.notify(
          initialContext.initialState,
          finalContext.currentState,
        );
      }
    }

    _maybeIncrementSerialNumberDefaults(
      previousState: initialContext.initialState,
      nextState: finalContext.currentState,
      action: initialContext.action,
    );

    if (finalContext.events.isNotEmpty) {
      _services.publishEditEvents(finalContext.events);
    }

    final alreadyEmitted =
        finalContext.getMetadata<bool>('editEventsEmitted') ?? false;
    if (!alreadyEmitted) {
      _emitEditSessionEvents(
        previousState: initialContext.initialState,
        nextState: finalContext.currentState,
        action: initialContext.action,
      );
    }

    _emitStateChangeEvents(
      previousState: initialContext.initialState,
      nextState: finalContext.currentState,
    );
  }

  void _maybeIncrementSerialNumberDefaults({
    required DrawState previousState,
    required DrawState nextState,
    required DrawAction action,
  }) {
    if (action is! FinishCreateElement) {
      return;
    }

    final previousElements = previousState.domain.document.elements;
    final nextElements = nextState.domain.document.elements;
    if (nextElements.length <= previousElements.length) {
      return;
    }

    final created = nextElements.isNotEmpty ? nextElements.last : null;
    final data = created?.data;
    if (data is! SerialNumberData) {
      return;
    }

    final nextSerial = data.number + 1;
    final currentConfig = _services.configManager.current;
    final nextSerialStyle = currentConfig.serialNumberStyle.copyWith(
      serialNumber: nextSerial,
    );
    if (nextSerialStyle == currentConfig.serialNumberStyle) {
      return;
    }
    _services.configManager.update(
      currentConfig.copyWith(serialNumberStyle: nextSerialStyle),
    );
  }

  void _reportError(
    DrawAction action,
    Object error,
    StackTrace stackTrace,
    DispatchContext context,
  ) {
    final source = context.errorSource ?? 'unknown';
    final traceId = context.traceId;

    _services.drawContext.log.store
        .error('Dispatch failed', error, stackTrace, {
          'action': action.runtimeType.toString(),
          'criticality': action.criticality.toString(),
          'source': source,
          'traceId': traceId,
        });

    if (_services.eventBus.hasListeners) {
      _services.eventBus.emit(
        ErrorEvent(
          message:
              'Dispatch ${action.runtimeType} failed '
              '(traceId: $traceId, source: $source)',
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  void _emitEditSessionEvents({
    required DrawState previousState,
    required DrawState nextState,
    required DrawAction action,
  }) {
    if (!_services.eventBus.hasListeners) {
      return;
    }

    final prevInteraction = previousState.application.interaction;
    final nextInteraction = nextState.application.interaction;

    if (prevInteraction is! EditingState && nextInteraction is EditingState) {
      _services.eventBus.emit(
        EditSessionStartedEvent(
          sessionId: nextInteraction.sessionId,
          operationId: nextInteraction.operationId,
        ),
      );
      return;
    }

    if (prevInteraction is EditingState && nextInteraction is EditingState) {
      if (prevInteraction.sessionId == nextInteraction.sessionId) {
        _services.eventBus.emit(
          EditSessionUpdatedEvent(
            sessionId: nextInteraction.sessionId,
            operationId: nextInteraction.operationId,
          ),
        );
        return;
      }

      _services.eventBus.emit(
        EditSessionCancelledEvent(
          sessionId: prevInteraction.sessionId,
          operationId: prevInteraction.operationId,
          reason: EditCancelReason.newEditStarted,
        ),
      );
      _services.eventBus.emit(
        EditSessionStartedEvent(
          sessionId: nextInteraction.sessionId,
          operationId: nextInteraction.operationId,
        ),
      );
      return;
    }

    if (prevInteraction is EditingState && nextInteraction is! EditingState) {
      if (action is FinishEdit) {
        _services.eventBus.emit(
          EditSessionFinishedEvent(
            sessionId: prevInteraction.sessionId,
            operationId: prevInteraction.operationId,
          ),
        );
      } else {
        _services.eventBus.emit(
          EditSessionCancelledEvent(
            sessionId: prevInteraction.sessionId,
            operationId: prevInteraction.operationId,
            reason: _resolveCancelReason(action),
          ),
        );
      }
    }
  }

  void _emitStateChangeEvents({
    required DrawState previousState,
    required DrawState nextState,
  }) {
    final hasEventListeners = _services.eventBus.hasListeners;

    if (hasEventListeners &&
        previousState.domain.document.elementsVersion !=
            nextState.domain.document.elementsVersion) {
      _services.eventBus.emit(
        DocumentChangedEvent(
          elementsVersion: nextState.domain.document.elementsVersion,
          elementCount: nextState.domain.document.elements.length,
        ),
      );
    }

    if (hasEventListeners &&
        previousState.domain.selection.selectionVersion !=
            nextState.domain.selection.selectionVersion) {
      _services.eventBus.emit(
        SelectionChangedEvent(
          selectedIds: nextState.domain.selection.selectedIds,
          selectionVersion: nextState.domain.selection.selectionVersion,
        ),
      );
    }

    if (hasEventListeners &&
        previousState.application.view != nextState.application.view) {
      _services.eventBus.emit(
        ViewChangedEvent(camera: nextState.application.view.camera),
      );
    }

    if (hasEventListeners &&
        previousState.application.interaction !=
            nextState.application.interaction) {
      _services.eventBus.emit(
        InteractionChangedEvent(interaction: nextState.application.interaction),
      );
    }

    _emitHistoryAvailabilityIfNeeded();
  }

  void _emitHistoryAvailabilityIfNeeded() {
    syncHistoryAvailability(emitIfChanged: true);
  }

  EditCancelReason _resolveCancelReason(DrawAction action) => switch (action) {
    CancelEdit(:final reason) => reason,
    StartEdit _ => EditCancelReason.newEditStarted,
    _ => EditCancelReason.userCancelled,
  };
}

class _DispatchTask {
  _DispatchTask(Future<void> Function() task)
    : _task = task,
      completer = Completer<void>();
  final Completer<void> completer;
  final Future<void> Function() _task;

  Future<void> run() async {
    try {
      await _task();
      if (!completer.isCompleted) {
        completer.complete();
      }
    } on Object catch (error, stackTrace) {
      completeWithError(error, stackTrace);
    }
  }

  void completeWithError(Object error, [StackTrace? stackTrace]) {
    if (completer.isCompleted) {
      return;
    }
    if (stackTrace != null) {
      completer.completeError(error, stackTrace);
    } else {
      completer.completeError(error);
    }
  }
}
