import 'dart:async';
import 'dart:collection';

import 'input_event.dart';
import 'middleware/input_middleware.dart';
import 'plugin_core.dart';
import 'plugin_registry.dart';

/// Plugin-based input coordinator.
///
/// Core of the input architecture, combining middleware pipeline and plugin
/// registry.
class PluginInputCoordinator {
  static const _processingFailureReason = 'Input processing failed';
  static const _coalescedEventMessage = 'Event coalesced by coordinator';

  PluginInputCoordinator({
    required PluginContext pluginContext,
    List<InputMiddleware>? middlewares,
  }) : _pluginContext = pluginContext,
       _registry = PluginRegistry(context: pluginContext),
       _pipeline = InputPipeline(middlewares: middlewares ?? []);
  final PluginContext _pluginContext;
  final PluginRegistry _registry;
  final InputPipeline _pipeline;
  final _queue = Queue<_QueuedInputEvent>();

  Completer<void>? _drainCompleter;
  var _isDraining = false;
  var _isDisposed = false;
  var _coalescedEventCount = 0;

  /// Get the plugin registry.
  PluginRegistry get registry => _registry;

  /// Get the middleware pipeline.
  InputPipeline get pipeline => _pipeline;

  /// Handle an input event.
  ///
  /// Flow:
  /// 1. Preprocess through the middleware pipeline
  /// 2. Dispatch to the plugin registry
  /// 3. Return the result
  Future<PluginResult?> handleEvent(InputEvent event) {
    if (_isDisposed) {
      return Future<PluginResult?>.value(
        const PluginResult.unhandled(reason: 'Input coordinator disposed'),
      );
    }

    final queuedEvent = _QueuedInputEvent(event);
    _enqueueEvent(queuedEvent);
    if (!_isDraining) {
      unawaited(_drainQueue());
    }
    return queuedEvent.completer.future;
  }

  void _enqueueEvent(_QueuedInputEvent queuedEvent) {
    if (_tryCoalesceQueuedEvent(queuedEvent)) {
      return;
    }
    _queue.addLast(queuedEvent);
  }

  bool _tryCoalesceQueuedEvent(_QueuedInputEvent incomingEvent) {
    if (!_isDraining || _queue.isEmpty) {
      return false;
    }
    final incomingInputEvent = incomingEvent.event;
    if (!_isCoalescibleEvent(incomingInputEvent)) {
      return false;
    }
    final lastQueuedEvent = _queue.last;
    if (!_canCoalesce(lastQueuedEvent.event, incomingInputEvent)) {
      return false;
    }

    _queue.removeLast();
    lastQueuedEvent.complete(
      const PluginResult.consumed(message: _coalescedEventMessage),
    );
    _coalescedEventCount += 1;
    _queue.addLast(incomingEvent);
    return true;
  }

  bool _canCoalesce(InputEvent previousEvent, InputEvent nextEvent) =>
      previousEvent.runtimeType == nextEvent.runtimeType &&
      _isCoalescibleEvent(previousEvent) &&
      previousEvent.modifiers == nextEvent.modifiers;

  bool _isCoalescibleEvent(InputEvent event) =>
      event is PointerMoveInputEvent || event is PointerHoverInputEvent;

  Future<void> _drainQueue() async {
    if (_isDraining) {
      return;
    }
    _isDraining = true;
    final completer = Completer<void>();
    _drainCompleter = completer;

    try {
      while (_queue.isNotEmpty) {
        final queuedEvent = _queue.removeFirst();
        try {
          final result = await _processEvent(queuedEvent.event);
          queuedEvent.complete(result);
        } on Object catch (error, stackTrace) {
          _logProcessingError(
            event: queuedEvent.event,
            error: error,
            stackTrace: stackTrace,
          );
          queuedEvent.complete(
            const PluginResult.unhandled(reason: _processingFailureReason),
          );
        }
      }
    } finally {
      _isDraining = false;
      if (!completer.isCompleted) {
        completer.complete();
      }
      _drainCompleter = null;
    }
  }

  Future<PluginResult?> _processEvent(InputEvent event) async {
    final state = _pluginContext.state;

    // Create middleware context.
    final middlewareContext = MiddlewareContext(
      state: state,
      log: _pluginContext.context.log.input,
    );

    // 1. Process via middleware pipeline.
    final processedEvent = await _pipeline.execute(event, middlewareContext);

    // If middleware intercepts the event, return immediately.
    if (processedEvent == null) {
      return const PluginResult.handled(
        message: 'Event intercepted by middleware',
      );
    }

    // 2. Dispatch to plugins.
    return _registry.dispatch(processedEvent, state);
  }

  void _logProcessingError({
    required InputEvent event,
    required Object error,
    required StackTrace stackTrace,
  }) {
    try {
      _pluginContext.context.log.input.error(
        'Input event processing failed',
        error,
        stackTrace,
        {'event': event.runtimeType.toString()},
      );
    } on Object {
      // Ignore logging failures so input handling still degrades safely.
    }
  }

  /// Reset all plugin state.
  void reset() {
    _registry.resetAll();
  }

  /// Dispose resources.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;

    while (_queue.isNotEmpty) {
      _queue.removeFirst().complete(
        const PluginResult.unhandled(reason: 'Input coordinator disposed'),
      );
    }

    final drainCompleter = _drainCompleter;
    if (drainCompleter != null) {
      await drainCompleter.future;
    }

    await _registry.dispose();
  }

  /// Get statistics.
  Map<String, dynamic> getStats() => {
    'middlewareCount': _pipeline.middlewares.length,
    'middlewares': _pipeline.middlewares.map((m) => m.name).toList(),
    'queuedEvents': _queue.length,
    'isDraining': _isDraining,
    'coalescedEvents': _coalescedEventCount,
    ..._registry.getStats(),
  };
}

class _QueuedInputEvent {
  _QueuedInputEvent(this.event);

  final InputEvent event;
  final completer = Completer<PluginResult?>();

  void complete(PluginResult? result) {
    if (completer.isCompleted) {
      return;
    }
    completer.complete(result);
  }
}
