import 'dart:async';

import '../../actions/config_actions.dart';
import '../../actions/draw_actions.dart';
import '../../config/config_manager.dart';
import '../../core/draw_context.dart';
import '../../edit/core/edit_cancel_reason.dart';
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
import '../state_change_detector.dart';
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
  });
  final DrawContext drawContext;
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
  bool _lastCanUndo;
  bool _lastCanRedo;
  var _dispatchTail = Future<void>.value();

  var _isDisposed = false;

  DrawState get state => _services.stateManager.current;

  bool get isDisposed => _isDisposed;

  Future<void> dispatch(DrawAction action) => _enqueue(() async {
    for (final nextAction in _expandActionsForDispatch(action)) {
      await _process(nextAction);
    }
  });

  void syncHistoryAvailability() {
    final canUndo = _services.historyManager.canUndo;
    final canRedo = _services.historyManager.canRedo;
    final changed = canUndo != _lastCanUndo || canRedo != _lastCanRedo;

    _lastCanUndo = canUndo;
    _lastCanRedo = canRedo;

    if (!changed) {
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
  }

  Future<void> _enqueue(Future<void> Function() task) {
    if (_isDisposed) {
      return Future.error(StateError('Dispatch queue has been disposed'));
    }

    Future<void> runTask() async {
      if (_isDisposed) {
        throw StateError('Dispatch queue disposed while pending');
      }
      await task();
    }

    final scheduled = _dispatchTail.then<void>(
      (_) => runTask(),
      onError: (_, StackTrace stackTrace) => runTask(),
    );
    _dispatchTail = scheduled.catchError((Object _, StackTrace _) {});
    return scheduled;
  }

  List<DrawAction> _expandActionsForDispatch(DrawAction action) {
    final cancelReason = _resolveEditCancelReason(action);
    if (cancelReason == null) {
      return [action];
    }
    return [CancelEdit(reason: cancelReason), action];
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
    if (!_services.stateManager.current.application.isEditing) {
      return null;
    }

    if (action is Undo && !_services.historyManager.canUndo) {
      return null;
    }
    if (action is Redo && !_services.historyManager.canRedo) {
      return null;
    }

    return switch (action) {
      CancelEdit _ || UpdateEdit _ || FinishEdit _ => null,
      StartEdit _ => EditCancelReason.newEditStarted,
      _ when action.conflictsWithEditing => EditCancelReason.conflictingAction,
      _ => null,
    };
  }

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
      hasStateChanged: finalContext.hasStateChanged,
    );
  }

  void _applyTransitionEffects({
    required DrawState previousState,
    required DrawState nextState,
    required DrawAction action,
    required bool hasStateChanged,
  }) {
    if (hasStateChanged) {
      _services.stateManager.update(nextState);
      if (!_services.isBatching()) {
        _services.listenerRegistry.notify(previousState, nextState);
      }
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
      case (final EditingState previous, final EditingState next):
        _emitEditingTransition(previous: previous, next: next);
      case (final EditingState previous, _):
        _emitEditingEnded(previous: previous, action: action);
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

  void _emitEditingTransition({
    required EditingState previous,
    required EditingState next,
  }) {
    if (previous.sessionId == next.sessionId) {
      _emitEvent(
        () => EditSessionUpdatedEvent(
          sessionId: next.sessionId,
          operationId: next.operationId,
        ),
      );
      return;
    }

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
  }

  void _emitEditingEnded({
    required EditingState previous,
    required DrawAction action,
  }) {
    if (action is FinishEdit) {
      _emitEvent(
        () => EditSessionFinishedEvent(
          sessionId: previous.sessionId,
          operationId: previous.operationId,
        ),
      );
      return;
    }

    _emitEvent(
      () => EditSessionCancelledEvent(
        sessionId: previous.sessionId,
        operationId: previous.operationId,
        reason: _resolveCancelReason(action),
      ),
    );
  }

  void _emitStateChangeEvents({
    required DrawState previousState,
    required DrawState nextState,
  }) {
    if (hasDocumentStateChanged(previousState, nextState)) {
      _emitEvent(
        () => DocumentChangedEvent(
          elementsVersion: nextState.domain.document.elementsVersion,
          elementCount: nextState.domain.document.elements.length,
        ),
      );
    }

    if (hasSelectionStateChanged(previousState, nextState)) {
      _emitEvent(
        () => SelectionChangedEvent(
          selectedIds: nextState.domain.selection.selectedIds,
          selectionVersion: nextState.domain.selection.selectionVersion,
        ),
      );
    }

    if (hasViewStateChanged(previousState, nextState)) {
      _emitEvent(
        () => ViewChangedEvent(camera: nextState.application.view.camera),
      );
    }

    if (hasInteractionStateChanged(previousState, nextState)) {
      _emitEvent(
        () => InteractionChangedEvent(
          interaction: nextState.application.interaction,
        ),
      );
    }

    syncHistoryAvailability();
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
