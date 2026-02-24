import 'dart:async';
import 'dart:collection';

import '../../actions/config_actions.dart';
import '../../actions/draw_actions.dart';
import '../../config/config_manager.dart';
import '../../core/dependency_interfaces.dart';
import '../../edit/core/edit_cancel_reason.dart';
import '../../edit/core/edit_event_factory.dart';
import '../../edit/core/edit_session_id_generator.dart';
import '../../edit/core/edit_session_service.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../elements/types/serial_number/serial_number_sequence.dart';
import '../../events/edit_events.dart';
import '../../events/error_events.dart';
import '../../events/event_bus.dart';
import '../../events/state_events.dart';
import '../../models/draw_state.dart';
import '../../models/interaction_state.dart';
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

    if (!emitIfChanged || !changed) {
      return;
    }

    _emitEvent(
      () => HistoryAvailabilityChangedEvent(canUndo: canUndo, canRedo: canRedo),
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

    await _runWithFrozenConfig(() async {
      await _processThroughPipeline(action);
    });
  }

  Future<void> _processThroughPipeline(DrawAction action) async {
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

    final finalContext = await _executePipeline(initialContext);
    if (finalContext.hasError) {
      final error = finalContext.error ?? StateError('Dispatch failed');
      final stackTrace = finalContext.stackTrace ?? StackTrace.current;
      _reportDispatchError(
        action: action,
        source: finalContext.errorSource ?? 'unknown',
        traceId: finalContext.traceId,
        error: error,
        stackTrace: stackTrace,
      );
      _rethrowIfCritical(action, error, stackTrace);
      return;
    }

    _commit(initialContext: initialContext, finalContext: finalContext);
  }

  Future<void> _runWithFrozenConfig(FutureOr<void> Function() action) async {
    _services.configManager.freeze();
    try {
      await action();
    } finally {
      _services.configManager.unfreeze();
    }
  }

  Future<DispatchContext> _executePipeline(
    DispatchContext initialContext,
  ) async {
    try {
      return await _pipeline.execute(initialContext);
    } on Object catch (error, stackTrace) {
      return initialContext.withError(error, stackTrace, source: 'Pipeline');
    }
  }

  bool _handleConfigAction(DrawAction action) {
    switch (action) {
      case UpdateConfig(:final config):
        _services.configManager.update(config);
        return true;
      case UpdateSelectionConfig(:final selection):
        _services.configManager.updateSelection(selection);
        return true;
      case UpdateCanvasConfig(:final canvas):
        _services.configManager.updateCanvas(canvas);
        return true;
      default:
        return false;
    }
  }

  EditCancelReason? _resolveEditCancelReason(DrawAction action) {
    final state = _services.stateManager.current;
    if (!state.application.isEditing) {
      return null;
    }

    return switch (action) {
      CancelEdit _ || UpdateEdit _ || FinishEdit _ => null,
      StartEdit _ || EditIntentAction _ => EditCancelReason.newEditStarted,
      Undo _ || Redo _ =>
        _hasConflictingHistoryNavigation(action)
            ? EditCancelReason.conflictingAction
            : null,
      _ =>
        action.conflictsWithEditing ? EditCancelReason.conflictingAction : null,
    };
  }

  bool _hasConflictingHistoryNavigation(DrawAction action) => switch (action) {
    Undo _ => _services.historyManager.canUndo,
    Redo _ => _services.historyManager.canRedo,
    _ => false,
  };

  void _commit({
    required DispatchContext initialContext,
    required DispatchContext finalContext,
  }) {
    _maybeIncrementSerialNumberDefaults(
      previousState: initialContext.initialState,
      nextState: finalContext.currentState,
      action: initialContext.action,
    );

    _applyTransitionEffects(
      previousState: initialContext.initialState,
      nextState: finalContext.currentState,
      action: initialContext.action,
      events: finalContext.events,
      hasStateChanged: finalContext.hasStateChanged,
    );
  }

  void _applyTransitionEffects({
    required DrawState previousState,
    required DrawState nextState,
    required DrawAction action,
    required bool hasStateChanged,
    required List<EditSessionEvent> events,
  }) {
    if (hasStateChanged) {
      _services.stateManager.update(nextState);
      if (!_services.isBatching()) {
        _services.listenerRegistry.notify(previousState, nextState);
      }
    }

    if (events.isNotEmpty) {
      _services.publishEditEvents(events);
    }

    _emitEditSessionEvents(
      previousState: previousState,
      nextState: nextState,
      action: action,
    );
    _emitStateChangeEvents(previousState: previousState, nextState: nextState);
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

    if (nextElements.last.data is! SerialNumberData) {
      return;
    }

    final nextSerialFromDocument = resolveNextSerialNumber(nextElements);
    if (nextSerialFromDocument == null) {
      return;
    }
    final currentConfig = _services.configManager.current;
    final nextSerial =
        nextSerialFromDocument > currentConfig.serialNumberStyle.serialNumber
        ? nextSerialFromDocument
        : currentConfig.serialNumberStyle.serialNumber;
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

  void _reportDispatchError({
    required DrawAction action,
    required String source,
    required Object error,
    required StackTrace stackTrace,
    String? traceId,
  }) {
    _services.drawContext.log.store.error(
      'Dispatch failed',
      error,
      stackTrace,
      {
        'action': action.runtimeType.toString(),
        'criticality': action.criticality.toString(),
        'source': source,
        ...?(traceId == null ? null : {'traceId': traceId}),
      },
    );

    _emitEvent(
      () => ErrorEvent(
        message: _buildErrorMessage(
          action: action,
          source: source,
          traceId: traceId,
        ),
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  String _buildErrorMessage({
    required DrawAction action,
    required String source,
    String? traceId,
  }) {
    if (traceId == null || traceId.isEmpty) {
      return 'Dispatch ${action.runtimeType} failed (source: $source)';
    }
    return 'Dispatch ${action.runtimeType} failed '
        '(traceId: $traceId, source: $source)';
  }

  void _emitEditSessionEvents({
    required DrawState previousState,
    required DrawState nextState,
    required DrawAction action,
  }) {
    final prevInteraction = previousState.application.interaction;
    final nextInteraction = nextState.application.interaction;

    switch ((prevInteraction, nextInteraction)) {
      case (final EditingState previous, final EditingState next)
          when previous.sessionId == next.sessionId:
        _emitEvent(
          () => EditSessionUpdatedEvent(
            sessionId: next.sessionId,
            operationId: next.operationId,
          ),
        );
      case (final EditingState previous, final EditingState next):
        _emitEvent(
          () => EditSessionCancelledEvent(
            sessionId: previous.sessionId,
            operationId: previous.operationId,
            reason: EditCancelReason.newEditStarted,
          ),
        );
        _emitEvent(
          () => EditSessionStartedEvent(
            sessionId: next.sessionId,
            operationId: next.operationId,
          ),
        );
      case (final EditingState previous, _):
        if (action is FinishEdit) {
          _emitEvent(
            () => EditSessionFinishedEvent(
              sessionId: previous.sessionId,
              operationId: previous.operationId,
            ),
          );
        } else {
          _emitEvent(
            () => EditSessionCancelledEvent(
              sessionId: previous.sessionId,
              operationId: previous.operationId,
              reason: _resolveCancelReason(action),
            ),
          );
        }
      case (_, final EditingState next):
        _emitEvent(
          () => EditSessionStartedEvent(
            sessionId: next.sessionId,
            operationId: next.operationId,
          ),
        );
      default:
        break;
    }
  }

  void _emitStateChangeEvents({
    required DrawState previousState,
    required DrawState nextState,
  }) {
    if (previousState.domain.document.elementsVersion !=
        nextState.domain.document.elementsVersion) {
      _emitEvent(
        () => DocumentChangedEvent(
          elementsVersion: nextState.domain.document.elementsVersion,
          elementCount: nextState.domain.document.elements.length,
        ),
      );
    }

    if (previousState.domain.selection.selectionVersion !=
        nextState.domain.selection.selectionVersion) {
      _emitEvent(
        () => SelectionChangedEvent(
          selectedIds: nextState.domain.selection.selectedIds,
          selectionVersion: nextState.domain.selection.selectionVersion,
        ),
      );
    }

    if (previousState.application.view != nextState.application.view) {
      _emitEvent(
        () => ViewChangedEvent(camera: nextState.application.view.camera),
      );
    }

    if (previousState.application.interaction !=
        nextState.application.interaction) {
      _emitEvent(
        () => InteractionChangedEvent(
          interaction: nextState.application.interaction,
        ),
      );
    }

    syncHistoryAvailability(emitIfChanged: true);
  }

  void _emitEvent<T extends DrawEvent>(T Function() eventFactory) {
    _services.eventBus.emitLazy<T>(eventFactory);
  }

  void _rethrowIfCritical(
    DrawAction action,
    Object error,
    StackTrace stackTrace,
  ) {
    if (action.criticality != ActionCriticality.critical) {
      return;
    }
    Error.throwWithStackTrace(error, stackTrace);
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
