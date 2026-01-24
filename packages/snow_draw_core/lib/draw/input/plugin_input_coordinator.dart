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
  Future<PluginResult?> handleEvent(InputEvent event) async {
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
    final result = await _registry.dispatch(processedEvent, state);

    return result;
  }

  /// Reset all plugin state.
  void reset() {
    _registry.resetAll();
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await _registry.dispose();
  }

  /// Get statistics.
  Map<String, dynamic> getStats() => {
    'middlewareCount': _pipeline.middlewares.length,
    'middlewares': _pipeline.middlewares.map((m) => m.name).toList(),
    ..._registry.getStats(),
  };
}
