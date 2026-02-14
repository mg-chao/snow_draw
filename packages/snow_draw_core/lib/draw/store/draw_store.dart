import 'dart:async';
import 'dart:ui' show VoidCallback;

import '../actions/draw_actions.dart';
import '../config/draw_config.dart';
import '../core/draw_context.dart';
import '../edit/core/edit_event_factory.dart';
import '../edit/core/edit_session_service.dart';
import '../events/event_bus.dart';
import '../models/draw_state.dart';
import '../models/edit_session_id.dart';
import 'config_manager.dart';
import 'dispatch/action_processor.dart';
import 'draw_store_interface.dart';
import 'history_manager.dart';
import 'listener_registry.dart';
import 'middleware/middleware_pipeline.dart';
import 'middleware/middleware_pipeline_factory.dart';
import 'selector.dart';
import 'snapshot.dart';
import 'snapshot_builder.dart';
import 'state_manager.dart';

class DefaultDrawStore implements DrawStore {
  DefaultDrawStore({
    required DrawContext context,
    DrawState? initialState,
    this.includeSelectionInHistory = false,
    HistoryManager? historyManager,
    SnapshotBuilder snapshotBuilder = const SnapshotBuilder(),
    MiddlewarePipeline? pipeline,
    EventBus? eventBus,
  }) : _ownsEventBus = eventBus == null && context.eventBus == null,
       _eventBus = eventBus ?? context.eventBus ?? EventBus(),
       _snapshotBuilder = snapshotBuilder,
       _editEventController = StreamController<EditSessionEvent>.broadcast() {
    this.context = context.eventBus == _eventBus
        ? context
        : context.copyWith(eventBus: _eventBus);

    _historyManager =
        historyManager ?? HistoryManager(logService: this.context.log);
    _stateManager = StateManager(initialState ?? DrawState());
    _configManager = this.context.configManager;
    _listenerRegistry = ListenerRegistry(
      onError: (error, stackTrace) {
        this.context.log.store.error(
          'Listener threw during notification',
          error,
          stackTrace,
        );
      },
    );

    _editSessionService = EditSessionService.fromRegistry(
      this.context.editOperations,
      configProvider: () => _configManager.current,
      logService: this.context.log,
    );

    _pipeline = pipeline ?? middlewarePipelineFactory.createDefault();

    final services = ActionProcessorServices(
      drawContext: this.context,
      stateManager: _stateManager,
      historyManager: _historyManager,
      configManager: _configManager,
      listenerRegistry: _listenerRegistry,
      snapshotBuilder: _snapshotBuilder,
      editSessionService: _editSessionService,
      sessionIdGenerator: _generateEditSessionId,
      isBatching: () => _isBatching,
      includeSelectionInHistory: includeSelectionInHistory,
      eventBus: _eventBus,
      publishEditEvents: _publishEditEvents,
    );

    _actionProcessor = ActionProcessor(services: services, pipeline: _pipeline);
  }
  @override
  late final DrawContext context;

  late final StateManager _stateManager;
  late final ConfigManager _configManager;
  late final ListenerRegistry _listenerRegistry;

  late final HistoryManager _historyManager;
  late final EditSessionService _editSessionService;
  final StreamController<EditSessionEvent> _editEventController;
  final SnapshotBuilder _snapshotBuilder;
  final bool _ownsEventBus;
  final EventBus _eventBus;
  final bool includeSelectionInHistory;

  late final MiddlewarePipeline _pipeline;
  late final ActionProcessor _actionProcessor;

  var _isDisposed = false;
  var _isBatching = false;
  PersistentSnapshot? _batchStartSnapshot;
  DrawState? _batchStartState;
  var _batchSequence = 0;
  String? _currentBatchId;
  var _editSessionSequence = 0;

  @override
  DrawState get state => _stateManager.current;

  @override
  DrawState get currentState => state;

  bool get canUndo => _historyManager.canUndo;
  bool get canRedo => _historyManager.canRedo;

  @override
  DrawConfig get config => _configManager.current;

  @override
  Stream<DrawConfig> get configStream => _configManager.stream;

  /// Event bus.
  EventBus get eventBus => _eventBus;

  /// Event stream (convenience accessor).
  @override
  Stream<DrawEvent> get eventStream => _eventBus.stream;

  /// Edit diagnostic event stream.
  Stream<EditSessionEvent> get editEvents => _editEventController.stream;

  @override
  VoidCallback listen(
    StateChangeListener<DrawState> listener, {
    Set<DrawStateChange>? changeTypes,
  }) {
    _checkNotDisposed();
    return _listenerRegistry.register(listener, changeTypes: changeTypes);
  }

  @override
  void unsubscribe(StateChangeListener<DrawState> listener) {
    _listenerRegistry.unregister(listener);
  }

  @override
  VoidCallback select<T>(
    StateSelector<DrawState, T> selector,
    StateChangeListener<T> listener, {
    bool Function(T, T)? equals,
  }) {
    _checkNotDisposed();

    // Read the current value on init, but do not notify.
    var previousValue = selector.select(state);

    return listen((state) {
      final newValue = selector.select(state);

      // Use custom or default equality.
      final equalsFn = equals ?? selector.equals;

      if (!equalsFn(previousValue, newValue)) {
        previousValue = newValue;
        listener(newValue);
      }
    });
  }

  void beginBatch() {
    if (_isBatching) {
      return;
    }
    _isBatching = true;
    _currentBatchId = 'batch_${_batchSequence++}';
    _batchStartState = state;
    _batchStartSnapshot = _snapshotBuilder.buildSnapshotFromState(
      state: state,
      includeSelection: includeSelectionInHistory,
    );
    context.log.store.info('Batch started', {'batchId': _currentBatchId});
    context.log.store.debug('Batch snapshot captured', {
      'batchId': _currentBatchId,
      'elements': state.domain.document.elements.length,
    });
  }

  void endBatch() {
    if (!_isBatching) {
      return;
    }
    _isBatching = false;

    final startState = _batchStartState;
    final startSnapshot = _batchStartSnapshot;
    _batchStartState = null;
    _batchStartSnapshot = null;

    if (startSnapshot == null) {
      context.log.store.warning('Batch ended without snapshot', {
        'batchId': _currentBatchId,
      });
      _currentBatchId = null;
      return;
    }

    final endSnapshot = _snapshotBuilder.buildSnapshotFromState(
      state: state,
      includeSelection: includeSelectionInHistory,
    );

    if (endSnapshot != startSnapshot) {
      _historyManager.record(startSnapshot, endSnapshot);
      context.log.store.info('Batch ended', {
        'batchId': _currentBatchId,
        'recorded': true,
      });
    } else {
      context.log.store.info('Batch ended', {
        'batchId': _currentBatchId,
        'recorded': false,
      });
    }

    _currentBatchId = null;

    if (startState == null || startState == state) {
      return;
    }

    _listenerRegistry.notify(startState, state);
  }

  @override
  Future<void> dispatch(DrawAction action) {
    _checkNotDisposed();
    return _actionProcessor.dispatch(action);
  }

  @override
  Future<void> call(DrawAction action) => dispatch(action);

  Future<void> undo() => dispatch(const Undo());

  Future<void> redo() => dispatch(const Redo());

  Future<void> clearHistory() => dispatch(const ClearHistory());

  HistoryManagerSnapshot exportHistory() => _historyManager.snapshot();

  void restoreHistory(HistoryManagerSnapshot snapshot) {
    _historyManager.restore(snapshot);
    _actionProcessor.syncHistoryAvailability(emitIfChanged: true);
  }

  Map<String, dynamic> exportHistoryJson() =>
      _historyManager.snapshot().toJson();

  void restoreHistoryJson(Map<String, dynamic> json) {
    final snapshot = HistoryManagerSnapshot.fromJson(
      json,
      elementRegistry: context.elementRegistry,
      onUnknownElement: (info) {
        context.log.history.warning('Unknown element in history', {
          'type': info.elementType,
          'id': info.elementId,
          'source': info.source,
          'error': info.error?.toString(),
        });
      },
    );
    _historyManager.restore(snapshot);
    _actionProcessor.syncHistoryAvailability(emitIfChanged: true);
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError('DrawStore has been disposed and cannot be used');
    }
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    _actionProcessor.dispose();

    unawaited(_configManager.dispose());
    unawaited(_editEventController.close());
    if (_ownsEventBus) {
      unawaited(_eventBus.dispose());
    }
    _listenerRegistry.clear();
    _historyManager.clear();
    context.log.dispose();
  }

  EditSessionId _generateEditSessionId() {
    final id = _editSessionSequence++;
    final sessionId = 'edit_$id';
    context.log.edit.debug('Edit session id generated', {
      'sessionId': sessionId,
    });
    return sessionId;
  }

  void _publishEditEvents(List<EditSessionEvent> events) {
    for (final event in events) {
      final operationId = switch (event) {
        EditStartFailed(:final operationId) => operationId,
        EditUpdateFailed(:final operationId) => operationId,
        EditFinishFailed(:final operationId) => operationId,
        EditCancelled(:final operationId) => operationId,
        EditCancelFailed(:final operationId) => operationId,
      };
      context.log.edit.debug('Edit session event published', {
        'event': event.runtimeType.toString(),
        'operationId': operationId,
      });
      _editEventController.add(event);
    }
  }
}
