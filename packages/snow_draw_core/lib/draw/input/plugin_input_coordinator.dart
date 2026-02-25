import 'dart:async';
import 'dart:collection';

import 'input_event.dart';
import 'middleware/input_middleware.dart';
import 'plugin_engine.dart';
import 'plugin_registry.dart';

/// Plugin-based input coordinator.
///
/// Engine center of the input architecture, combining middleware pipeline and
/// plugin registry.
class PluginInputCoordinator {
  static const _processingFailureReason = 'Input processing failed';
  static const _disposedReason = 'Input coordinator disposed';
  static const _coalescedEventMessage = 'Event coalesced by coordinator';
  static const _pressureCoalescingTolerance = 1e-4;

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

  Future<void>? _drainFuture;
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
        const PluginResult.unhandled(reason: _disposedReason),
      );
    }

    final queuedEvent = _QueuedInputEvent(event);
    _enqueue(queuedEvent);
    _ensureDraining();
    return queuedEvent.completer.future;
  }

  void _enqueue(_QueuedInputEvent incomingEvent) {
    if (_tryCoalesce(incomingEvent)) {
      return;
    }
    _queue.addLast(incomingEvent);
  }

  void _ensureDraining() {
    _drainFuture ??= _drainQueue();
  }

  bool _tryCoalesce(_QueuedInputEvent incomingEvent) {
    if (_drainFuture == null || _queue.isEmpty) {
      return false;
    }

    final incomingInput = incomingEvent.event;
    if (!_isCoalescibleEvent(incomingInput)) {
      return false;
    }

    final lastQueuedEvent = _queue.last;
    if (!_canCoalesce(lastQueuedEvent.event, incomingInput)) {
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
      previousEvent.modifiers == nextEvent.modifiers &&
      _isPressureCompatible(previousEvent, nextEvent);

  bool _isPressureCompatible(InputEvent previousEvent, InputEvent nextEvent) {
    final previousPressure = previousEvent.pressure;
    final nextPressure = nextEvent.pressure;
    if (previousPressure == 0 || nextPressure == 0) {
      return previousPressure == nextPressure;
    }
    return (previousPressure - nextPressure).abs() <=
        _pressureCoalescingTolerance;
  }

  bool _isCoalescibleEvent(InputEvent event) =>
      event is PointerMoveInputEvent || event is PointerHoverInputEvent;

  Future<void> _drainQueue() async {
    try {
      while (_queue.isNotEmpty) {
        await _drainNextQueuedEvent();
      }
    } finally {
      _drainFuture = null;
    }
  }

  Future<void> _drainNextQueuedEvent() async {
    final queuedEvent = _queue.removeFirst();
    try {
      queuedEvent.complete(await _processEvent(queuedEvent.event));
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

  Future<PluginResult?> _processEvent(InputEvent event) async {
    final middlewareContext = MiddlewareContext(
      state: _pluginContext.state,
      log: _pluginContext.context.log.input,
    );

    final processedEvent = await _pipeline.execute(event, middlewareContext);
    if (processedEvent == null) {
      return const PluginResult.handled(
        message: 'Event intercepted by middleware',
      );
    }

    return _registry.dispatch(processedEvent);
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

    _completeQueuedEvents(
      const PluginResult.unhandled(reason: _disposedReason),
    );

    final drainFuture = _drainFuture;
    if (drainFuture != null) {
      await drainFuture;
    }

    await _registry.dispose();
  }

  void _completeQueuedEvents(PluginResult result) {
    while (_queue.isNotEmpty) {
      _queue.removeFirst().complete(result);
    }
  }

  /// Get statistics.
  Map<String, dynamic> getStats() => {
    'middlewareCount': _pipeline.middlewares.length,
    'middlewares': _pipeline.middlewares.map((m) => m.name).toList(),
    'queuedEvents': _queue.length,
    'isDraining': _drainFuture != null,
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
