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
    _queue.addLast(queuedEvent);
    if (!_isDraining) {
      unawaited(_drainQueue());
    }
    return queuedEvent.completer.future;
  }

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
          queuedEvent.completeError(error, stackTrace);
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

  void completeError(Object error, StackTrace stackTrace) {
    if (completer.isCompleted) {
      return;
    }
    completer.completeError(error, stackTrace);
  }
}
