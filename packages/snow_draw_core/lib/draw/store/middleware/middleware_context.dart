import 'package:meta/meta.dart';

import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../edit/core/edit_session_id_generator.dart';
import '../../edit/core/edit_session_service.dart';
import '../../models/draw_state.dart';
import '../history_manager.dart';
import '../snapshot_builder.dart';

var _traceSequence = 0;

String _generateTraceId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final sequence = (_traceSequence++).toRadixString(16);
  return 'dispatch_${timestamp}_$sequence';
}

@immutable
class DispatchFailure {
  const DispatchFailure({
    required this.error,
    required this.stackTrace,
    required this.source,
  });

  final Object error;
  final StackTrace stackTrace;
  final String? source;
}

/// Flat dispatch context for middleware execution.
@immutable
class DispatchContext {
  const DispatchContext._({
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
    required this.shouldStop,
    required this.stopReason,
    required this.failure,
    required this.traceId,
  });

  factory DispatchContext.initial({
    required DrawAction action,
    required DrawState state,
    required InteractionReducerDeps drawContext,
    required HistoryManager historyManager,
    required SnapshotBuilder snapshotBuilder,
    required EditSessionService editSessionService,
    required EditSessionIdGenerator sessionIdGenerator,
    required bool isBatching,
    required bool includeSelectionInHistory,
    String? traceId,
  }) => DispatchContext._(
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
    shouldStop: false,
    stopReason: null,
    failure: null,
    traceId: traceId ?? _generateTraceId(),
  );
  final DrawAction action;
  final InteractionReducerDeps drawContext;
  final DrawState initialState;
  final DrawState currentState;
  final HistoryManager historyManager;
  final SnapshotBuilder snapshotBuilder;
  final EditSessionService editSessionService;
  final EditSessionIdGenerator sessionIdGenerator;
  final bool isBatching;
  final bool includeSelectionInHistory;
  final bool shouldStop;
  final String? stopReason;
  final DispatchFailure? failure;
  final String traceId;

  Object? get error => failure?.error;
  StackTrace? get stackTrace => failure?.stackTrace;
  String? get errorSource => failure?.source;

  bool get hasError => failure != null;
  bool get isTerminal => shouldStop || hasError;

  bool get hasStateChanged => currentState != initialState;

  DispatchContext withCurrentState(DrawState newState) {
    if (identical(newState, currentState)) {
      return this;
    }
    return _copy(currentState: newState);
  }

  DispatchContext withStop(String reason) =>
      _copy(shouldStop: true, stopReason: reason);

  DispatchContext withError(
    Object error,
    StackTrace stackTrace, {
    String? source,
  }) => _copy(
    shouldStop: true,
    stopReason: 'Error: $error',
    failure: DispatchFailure(
      error: error,
      stackTrace: stackTrace,
      source: source ?? errorSource,
    ),
  );

  DispatchContext _copy({
    DrawState? currentState,
    bool? shouldStop,
    String? stopReason,
    DispatchFailure? failure,
  }) => DispatchContext._(
    action: action,
    drawContext: drawContext,
    initialState: initialState,
    currentState: currentState ?? this.currentState,
    historyManager: historyManager,
    snapshotBuilder: snapshotBuilder,
    editSessionService: editSessionService,
    sessionIdGenerator: sessionIdGenerator,
    isBatching: isBatching,
    includeSelectionInHistory: includeSelectionInHistory,
    shouldStop: shouldStop ?? this.shouldStop,
    stopReason: stopReason ?? this.stopReason,
    failure: failure ?? this.failure,
    traceId: traceId,
  );

  @override
  String toString() =>
      'DispatchContext('
      'action: ${action.runtimeType}, '
      'traceId: $traceId, '
      'hasError: $hasError, '
      'isTerminal: $isTerminal, '
      'stateChanged: $hasStateChanged)';
}
