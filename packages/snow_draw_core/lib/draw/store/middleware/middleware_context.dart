import 'package:meta/meta.dart';

import '../../actions/draw_actions.dart';
import '../../core/draw_context.dart';
import '../../edit/core/edit_event_factory.dart';
import '../../edit/core/edit_session_id_generator.dart';
import '../../edit/core/edit_session_service.dart';
import '../../models/draw_state.dart';
import '../../reducers/interaction/interaction_state_machine.dart';
import '../history_manager.dart';
import '../snapshot_builder.dart';

var _traceSequence = 0;

String _generateTraceId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final sequence = (_traceSequence++).toRadixString(16);
  return 'dispatch_${timestamp}_$sequence';
}

/// Flat dispatch context for middleware execution.
@immutable
class DispatchContext {
  const DispatchContext({
    required this.action,
    required this.drawContext,
    required this.initialState,
    required this.currentState,
    required this.historyManager,
    required this.snapshotBuilder,
    required this.editSessionService,
    required this.sessionIdGenerator,
    required this.isBatching,
    required this.includeSelectionInHistory,
    required this.events,
    required this.metadata,
    required this.shouldStop,
    required this.stopReason,
    required this.error,
    required this.stackTrace,
    required this.errorSource,
    required this.traceId,
  });

  factory DispatchContext.initial({
    required DrawAction action,
    required DrawState state,
    required DrawContext drawContext,
    required HistoryManager historyManager,
    required SnapshotBuilder snapshotBuilder,
    required EditSessionService editSessionService,
    required EditSessionIdGenerator sessionIdGenerator,
    required bool isBatching,
    required bool includeSelectionInHistory,
    String? traceId,
  }) => DispatchContext(
    action: action,
    drawContext: drawContext,
    initialState: state,
    currentState: state,
    historyManager: historyManager,
    snapshotBuilder: snapshotBuilder,
    editSessionService: editSessionService,
    sessionIdGenerator: sessionIdGenerator,
    isBatching: isBatching,
    includeSelectionInHistory: includeSelectionInHistory,
    events: const [],
    metadata: const {},
    shouldStop: false,
    stopReason: null,
    error: null,
    stackTrace: null,
    errorSource: null,
    traceId: traceId ?? _generateTraceId(),
  );
  final DrawAction action;
  final DrawContext drawContext;
  final DrawState initialState;
  final DrawState currentState;
  final HistoryManager historyManager;
  final SnapshotBuilder snapshotBuilder;
  final EditSessionService editSessionService;
  final EditSessionIdGenerator sessionIdGenerator;
  final bool isBatching;
  final bool includeSelectionInHistory;
  final List<EditSessionEvent> events;
  final Map<String, dynamic> metadata;
  final bool shouldStop;
  final String? stopReason;
  final Object? error;
  final StackTrace? stackTrace;
  final String? errorSource;
  final String traceId;

  DispatchContext copyWith({
    DrawAction? action,
    DrawContext? drawContext,
    DrawState? initialState,
    DrawState? currentState,
    HistoryManager? historyManager,
    SnapshotBuilder? snapshotBuilder,
    EditSessionService? editSessionService,
    EditSessionIdGenerator? sessionIdGenerator,
    bool? isBatching,
    bool? includeSelectionInHistory,
    List<EditSessionEvent>? events,
    Map<String, dynamic>? metadata,
    bool? shouldStop,
    String? stopReason,
    Object? error,
    StackTrace? stackTrace,
    String? errorSource,
    String? traceId,
  }) => DispatchContext(
    action: action ?? this.action,
    drawContext: drawContext ?? this.drawContext,
    initialState: initialState ?? this.initialState,
    currentState: currentState ?? this.currentState,
    historyManager: historyManager ?? this.historyManager,
    snapshotBuilder: snapshotBuilder ?? this.snapshotBuilder,
    editSessionService: editSessionService ?? this.editSessionService,
    sessionIdGenerator: sessionIdGenerator ?? this.sessionIdGenerator,
    isBatching: isBatching ?? this.isBatching,
    includeSelectionInHistory:
        includeSelectionInHistory ?? this.includeSelectionInHistory,
    events: events ?? this.events,
    metadata: metadata ?? this.metadata,
    shouldStop: shouldStop ?? this.shouldStop,
    stopReason: stopReason ?? this.stopReason,
    error: error ?? this.error,
    stackTrace: stackTrace ?? this.stackTrace,
    errorSource: errorSource ?? this.errorSource,
    traceId: traceId ?? this.traceId,
  );

  HistoryAvailability get historyAvailability => HistoryAvailability(
    canUndo: historyManager.canUndo,
    canRedo: historyManager.canRedo,
  );

  bool get hasError => error != null;

  bool get hasStateChanged => currentState != initialState;

  T? getMetadata<T>(String key) => metadata[key] as T?;

  DispatchContext withCurrentState(DrawState newState) =>
      copyWith(currentState: newState);

  DispatchContext withInitialState(DrawState newState) =>
      copyWith(initialState: newState);

  DispatchContext withEvents(List<EditSessionEvent> newEvents) {
    if (newEvents.isEmpty) {
      return this;
    }
    return copyWith(events: [...events, ...newEvents]);
  }

  DispatchContext withEvent(EditSessionEvent event) =>
      copyWith(events: [...events, event]);

  DispatchContext withStop(String reason) =>
      copyWith(shouldStop: true, stopReason: reason);

  DispatchContext withError(
    Object error,
    StackTrace stackTrace, {
    String? source,
  }) => copyWith(
    error: error,
    stackTrace: stackTrace,
    errorSource: source ?? errorSource,
    shouldStop: true,
    stopReason: 'Error: $error',
  );

  DispatchContext withMetadata(String key, dynamic value) {
    final updated = Map<String, dynamic>.from(metadata)..[key] = value;
    return copyWith(metadata: updated);
  }

  @override
  String toString() =>
      'DispatchContext('
      'action: ${action.runtimeType}, '
      'traceId: $traceId, '
      'hasError: $hasError, '
      'shouldStop: $shouldStop, '
      'stateChanged: $hasStateChanged, '
      'events: ${events.length})';
}
