import '../models/draw_state.dart';
import 'input_event.dart';
import 'plugin_core.dart';

/// Plugin registry.
///
/// Manages registered plugins, their lifecycle, and event dispatch.
class PluginRegistry {
  PluginRegistry({required PluginContext context}) : _context = context;
  final PluginContext _context;
  final List<InputPlugin> _plugins = [];
  final Map<String, InputPlugin> _pluginMap = {};

  var _isSorted = true;

  /// Get all plugins.
  List<InputPlugin> get plugins => List.unmodifiable(_plugins);

  /// Get plugin count.
  int get pluginCount => _plugins.length;

  /// Register a plugin.
  Future<void> register(InputPlugin plugin) async {
    if (_pluginMap.containsKey(plugin.id)) {
      throw StateError('Plugin with id "${plugin.id}" is already registered');
    }

    await plugin.onLoad(_context);
    _plugins.add(plugin);
    _pluginMap[plugin.id] = plugin;
    _isSorted = false;

    _sortPlugins();
  }

  /// Register plugins in batch.
  Future<void> registerAll(List<InputPlugin> plugins) async {
    for (final plugin in plugins) {
      await register(plugin);
    }
  }

  /// Unregister a plugin.
  Future<void> unregister(String pluginId) async {
    final plugin = _pluginMap[pluginId];
    if (plugin == null) {
      throw StateError('Plugin with id "$pluginId" is not registered');
    }

    await plugin.onUnload();
    _plugins.remove(plugin);
    _pluginMap.remove(pluginId);
  }

  /// Check whether a plugin is registered.
  bool isRegistered(String pluginId) => _pluginMap.containsKey(pluginId);

  /// Get a plugin.
  InputPlugin? getPlugin(String pluginId) => _pluginMap[pluginId];

  /// Dispatch an event to all plugins.
  ///
  /// Runs plugins by priority until one returns handled.
  Future<PluginResult?> dispatch(InputEvent event, DrawState state) async {
    _ensureSorted();

    PluginResult? lastResult;

    // Before hooks
    for (final plugin in _plugins) {
      if (await plugin.onBeforeEvent(event)) {
        // A plugin intercepted the event.
        return const PluginResult.handled(
          message: 'Intercepted by before hook',
        );
      }
    }

    // Main event handling
    for (final plugin in _plugins) {
      // Check whether the plugin supports this event type.
      if (!plugin.supportedEventTypes.contains(event.runtimeType)) {
        continue;
      }

      // Check whether the plugin can handle this event.
      if (!plugin.canHandle(event, state)) {
        continue;
      }

      try {
        final result = await plugin.handleEvent(event);
        lastResult = result;

        // After hook
        await plugin.onAfterEvent(event, result);

        // Stop propagation if the plugin handled the event.
        if (result.shouldStopPropagation) {
          break;
        }
      } on Object catch (e, stackTrace) {
        _context.context.log.input.error(
          'Plugin handleEvent failed',
          e,
          stackTrace,
          {'plugin': plugin.name, 'event': event.runtimeType.toString()},
        );
        // Continue with the next plugin.
      }
    }

    // After hooks for all plugins
    for (final plugin in _plugins) {
      try {
        await plugin.onAfterEvent(event, lastResult);
      } on Object catch (e, stackTrace) {
        _context.context.log.input.error(
          'Plugin afterEvent failed',
          e,
          stackTrace,
          {'plugin': plugin.name, 'event': event.runtimeType.toString()},
        );
      }
    }

    return lastResult;
  }

  /// Reset all plugins.
  void resetAll() {
    for (final plugin in _plugins) {
      try {
        plugin.reset();
      } on Object catch (e, stackTrace) {
        _context.context.log.input.error('Plugin reset failed', e, stackTrace, {
          'plugin': plugin.name,
        });
      }
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    for (final plugin in _plugins.toList()) {
      try {
        await plugin.onUnload();
      } on Object catch (e, stackTrace) {
        _context.context.log.input.error(
          'Plugin unload failed',
          e,
          stackTrace,
          {'plugin': plugin.name},
        );
      }
    }
    _plugins.clear();
    _pluginMap.clear();
  }

  /// Sort plugins by priority.
  void _sortPlugins() {
    if (_isSorted) {
      return;
    }

    _plugins.sort((a, b) => a.priority.compareTo(b.priority));
    _isSorted = true;
  }

  /// Ensure plugins are sorted.
  void _ensureSorted() {
    if (!_isSorted) {
      _sortPlugins();
    }
  }

  /// Get plugin statistics.
  Map<String, dynamic> getStats() {
    final eventTypeCount = <Type, int>{};
    for (final plugin in _plugins) {
      for (final type in plugin.supportedEventTypes) {
        eventTypeCount[type] = (eventTypeCount[type] ?? 0) + 1;
      }
    }

    return {
      'totalPlugins': _plugins.length,
      'pluginsByPriority': _plugins
          .map((p) => {'id': p.id, 'name': p.name, 'priority': p.priority})
          .toList(),
      'eventTypeHandlers': eventTypeCount.map(
        (type, count) => MapEntry(type.toString(), count),
      ),
    };
  }
}
