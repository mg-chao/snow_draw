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

  /// Get all plugins.
  List<InputPlugin> get plugins => List<InputPlugin>.unmodifiable(_plugins);

  /// Get plugin count.
  int get pluginCount => _plugins.length;

  /// Register a plugin.
  Future<void> register(InputPlugin plugin) async {
    _assertPluginIdAvailable(plugin.id);
    await plugin.onLoad(_context);
    _insertPlugin(plugin);
  }

  /// Register plugins in batch.
  Future<void> registerAll(List<InputPlugin> plugins) async {
    if (plugins.isEmpty) {
      return;
    }

    _validateBatchPluginIds(plugins);

    final loadedPlugins = await _loadPlugins(plugins);

    for (final plugin in loadedPlugins) {
      _insertPlugin(plugin);
    }
  }

  /// Unregister a plugin.
  Future<void> unregister(String pluginId) async {
    final plugin = _pluginMap[pluginId];
    if (plugin == null) {
      throw StateError('Plugin with id "$pluginId" is not registered');
    }

    await plugin.onUnload();
    _removePlugin(plugin);
  }

  /// Check whether a plugin is registered.
  bool isRegistered(String pluginId) => _pluginMap.containsKey(pluginId);

  /// Get a plugin.
  InputPlugin? getPlugin(String pluginId) => _pluginMap[pluginId];

  /// Dispatch an event to all plugins.
  ///
  /// Runs plugins by priority until one returns handled.
  Future<PluginResult?> dispatch(InputEvent event) async {
    final pluginsForEvent = _pluginsForEvent(event);
    if (pluginsForEvent.isEmpty) {
      return null;
    }

    PluginResult? finalResult;
    try {
      if (await _isInterceptedByBeforeHooks(event, pluginsForEvent)) {
        finalResult = const PluginResult.handled(
          message: 'Intercepted by before hook',
        );
      } else {
        finalResult = await _dispatchToPlugins(
          event: event,
          pluginsForEvent: pluginsForEvent,
        );
      }
    } finally {
      await _runAfterHooks(event, finalResult, pluginsForEvent);
    }
    return finalResult;
  }

  /// Reset all plugins.
  void resetAll() {
    for (final plugin in _plugins) {
      try {
        plugin.reset();
      } on Object catch (e, stackTrace) {
        _safeLogInputError(
          message: 'Plugin reset failed',
          error: e,
          stackTrace: stackTrace,
          metadata: {'plugin': plugin.name},
        );
      }
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    for (final plugin in _plugins.toList()) {
      try {
        await plugin.onUnload();
      } on Object catch (e, stackTrace) {
        _safeLogInputError(
          message: 'Plugin unload failed',
          error: e,
          stackTrace: stackTrace,
          metadata: {'plugin': plugin.name},
        );
      }
    }
    _plugins.clear();
    _pluginMap.clear();
  }

  void _validateBatchPluginIds(List<InputPlugin> plugins) {
    final batchIds = <String>{};
    for (final plugin in plugins) {
      _assertPluginIdAvailable(plugin.id);
      if (!batchIds.add(plugin.id)) {
        throw StateError(
          'Duplicate plugin id "${plugin.id}" in batch registration',
        );
      }
    }
  }

  List<InputPlugin> _pluginsForEvent(InputEvent event) => [
    for (final plugin in _plugins)
      if (plugin.supportedEventTypes.contains(event.runtimeType)) plugin,
  ];

  void _assertPluginIdAvailable(String pluginId) {
    if (_pluginMap.containsKey(pluginId)) {
      throw StateError('Plugin with id "$pluginId" is already registered');
    }
  }

  void _insertPlugin(InputPlugin plugin) {
    final insertAt = _plugins.indexWhere(
      (candidate) => candidate.priority > plugin.priority,
    );
    if (insertAt == -1) {
      _plugins.add(plugin);
    } else {
      _plugins.insert(insertAt, plugin);
    }
    _pluginMap[plugin.id] = plugin;
  }

  void _removePlugin(InputPlugin plugin) {
    _plugins.remove(plugin);
    _pluginMap.remove(plugin.id);
  }

  Future<PluginResult?> _dispatchToPlugins({
    required InputEvent event,
    required List<InputPlugin> pluginsForEvent,
  }) async {
    PluginResult? finalResult;
    for (final plugin in pluginsForEvent) {
      final canHandle = _canHandle(
        plugin: plugin,
        event: event,
        state: _context.state,
      );
      if (!canHandle) {
        continue;
      }

      final result = await _runHandleHook(plugin: plugin, event: event);
      if (result == null) {
        continue;
      }
      finalResult = result;
      if (result.shouldStopPropagation) {
        break;
      }
    }
    return finalResult;
  }

  Future<bool> _isInterceptedByBeforeHooks(
    InputEvent event,
    List<InputPlugin> pluginsForEvent,
  ) async {
    for (final plugin in pluginsForEvent) {
      final intercepted = await _runBeforeHook(plugin: plugin, event: event);
      if (intercepted) {
        return true;
      }
    }
    return false;
  }

  bool _canHandle({
    required InputPlugin plugin,
    required InputEvent event,
    required DrawState state,
  }) {
    try {
      return plugin.canHandle(event, state);
    } on Object catch (e, stackTrace) {
      _safeLogInputError(
        message: 'Plugin canHandle failed',
        error: e,
        stackTrace: stackTrace,
        metadata: {
          'plugin': plugin.name,
          'event': event.runtimeType.toString(),
        },
      );
      return false;
    }
  }

  Future<List<InputPlugin>> _loadPlugins(List<InputPlugin> plugins) async {
    final loadedPlugins = <InputPlugin>[];
    for (final plugin in plugins) {
      try {
        await plugin.onLoad(_context);
      } on Object {
        await _rollbackLoadedPlugins(loadedPlugins: loadedPlugins);
        rethrow;
      }
      loadedPlugins.add(plugin);
    }
    return loadedPlugins;
  }

  Future<void> _rollbackLoadedPlugins({
    required List<InputPlugin> loadedPlugins,
  }) async {
    for (final loadedPlugin in loadedPlugins.reversed) {
      await _rollbackPlugin(loadedPlugin);
    }
  }

  Future<void> _rollbackPlugin(InputPlugin plugin) async {
    try {
      await plugin.onUnload();
    } on Object catch (e, stackTrace) {
      _safeLogInputError(
        message: 'Plugin rollback unload failed',
        error: e,
        stackTrace: stackTrace,
        metadata: {'plugin': plugin.name},
      );
    }
  }

  Future<bool> _runBeforeHook({
    required InputPlugin plugin,
    required InputEvent event,
  }) async {
    try {
      return await plugin.onBeforeEvent(event);
    } on Object catch (e, stackTrace) {
      _safeLogInputError(
        message: 'Plugin beforeEvent failed',
        error: e,
        stackTrace: stackTrace,
        metadata: _hookMetadata(
          plugin: plugin,
          event: event,
          hook: 'beforeEvent',
        ),
      );
      return false;
    }
  }

  Future<PluginResult?> _runHandleHook({
    required InputPlugin plugin,
    required InputEvent event,
  }) async {
    try {
      return await plugin.handleEvent(event);
    } on Object catch (e, stackTrace) {
      _safeLogInputError(
        message: 'Plugin handleEvent failed',
        error: e,
        stackTrace: stackTrace,
        metadata: _hookMetadata(
          plugin: plugin,
          event: event,
          hook: 'handleEvent',
        ),
      );
      return null;
    }
  }

  Future<void> _runAfterHooks(
    InputEvent event,
    PluginResult? result,
    List<InputPlugin> pluginsForEvent,
  ) async {
    for (final plugin in pluginsForEvent) {
      await _runAfterHook(plugin: plugin, event: event, result: result);
    }
  }

  Future<void> _runAfterHook({
    required InputPlugin plugin,
    required InputEvent event,
    required PluginResult? result,
  }) async {
    try {
      await plugin.onAfterEvent(event, result);
    } on Object catch (e, stackTrace) {
      _safeLogInputError(
        message: 'Plugin afterEvent failed',
        error: e,
        stackTrace: stackTrace,
        metadata: _hookMetadata(
          plugin: plugin,
          event: event,
          hook: 'afterEvent',
        ),
      );
    }
  }

  Map<String, dynamic> _hookMetadata({
    required InputPlugin plugin,
    required InputEvent event,
    required String hook,
  }) => {
    'plugin': plugin.name,
    'event': event.runtimeType.toString(),
    'hook': hook,
  };

  void _safeLogInputError({
    required String message,
    required Object error,
    required StackTrace stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    try {
      _context.context.log.input.error(message, error, stackTrace, metadata);
    } on Object {
      // Ignore logging failures so input dispatch remains resilient.
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
