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
  final Map<Type, List<InputPlugin>> _pluginsByEventType = {};

  var _isSorted = true;
  var _eventTypeIndexDirty = false;

  /// Get all plugins.
  List<InputPlugin> get plugins {
    _ensureSorted();
    return List.unmodifiable(_plugins);
  }

  /// Get plugin count.
  int get pluginCount => _plugins.length;

  /// Register a plugin.
  Future<void> register(InputPlugin plugin) async {
    if (_pluginMap.containsKey(plugin.id)) {
      throw StateError('Plugin with id "${plugin.id}" is already registered');
    }

    await plugin.onLoad(_context);
    _registerLoadedPlugins([plugin]);
  }

  /// Register plugins in batch.
  Future<void> registerAll(List<InputPlugin> plugins) async {
    if (plugins.isEmpty) {
      return;
    }

    _validateBatchPluginIds(plugins);

    final loadedPlugins = <InputPlugin>[];
    for (final plugin in plugins) {
      try {
        await plugin.onLoad(_context);
        loadedPlugins.add(plugin);
      } on Object {
        await _rollbackLoadedPlugins(
          failedPlugin: plugin,
          loadedPlugins: loadedPlugins,
        );
        rethrow;
      }
    }

    _registerLoadedPlugins(plugins);
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
    _eventTypeIndexDirty = true;
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
    final pluginsForEvent = _pluginsForEventType(event.runtimeType);
    if (pluginsForEvent.isEmpty) {
      return null;
    }

    PluginResult? finalResult;
    try {
      finalResult = await _dispatchToPlugins(
        event: event,
        state: state,
        pluginsForEvent: pluginsForEvent,
      );
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
    _pluginsByEventType.clear();
    _eventTypeIndexDirty = false;
  }

  /// Ensure plugins are sorted.
  void _ensureSorted() {
    if (_isSorted) {
      return;
    }
    _plugins.sort((a, b) => a.priority.compareTo(b.priority));
    _isSorted = true;
  }

  void _ensureEventTypeIndex() {
    if (!_eventTypeIndexDirty) {
      return;
    }
    _pluginsByEventType.clear();
    for (final plugin in _plugins) {
      for (final eventType in plugin.supportedEventTypes) {
        (_pluginsByEventType[eventType] ??= <InputPlugin>[]).add(plugin);
      }
    }
    _eventTypeIndexDirty = false;
  }

  List<InputPlugin> _pluginsForEventType(Type eventType) {
    _ensureEventTypeIndex();
    return _pluginsByEventType[eventType] ?? const <InputPlugin>[];
  }

  void _validateBatchPluginIds(List<InputPlugin> plugins) {
    final batchIds = <String>{};
    for (final plugin in plugins) {
      if (_pluginMap.containsKey(plugin.id)) {
        throw StateError('Plugin with id "${plugin.id}" is already registered');
      }
      if (!batchIds.add(plugin.id)) {
        throw StateError(
          'Duplicate plugin id "${plugin.id}" in batch registration',
        );
      }
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

  Future<void> _rollbackLoadedPlugins({
    required InputPlugin failedPlugin,
    required List<InputPlugin> loadedPlugins,
  }) async {
    await _rollbackPlugin(failedPlugin);
    for (final loadedPlugin in loadedPlugins.reversed) {
      await _rollbackPlugin(loadedPlugin);
    }
  }

  Future<PluginResult?> _dispatchToPlugins({
    required InputEvent event,
    required DrawState state,
    required List<InputPlugin> pluginsForEvent,
  }) async {
    if (await _isInterceptedByBeforeHooks(event, pluginsForEvent)) {
      return const PluginResult.handled(message: 'Intercepted by before hook');
    }

    PluginResult? finalResult;
    for (var i = 0; i < pluginsForEvent.length; i += 1) {
      final plugin = pluginsForEvent[i];
      final pluginState = i == 0 ? state : _context.state;
      final canHandle = _safeCanHandle(
        plugin: plugin,
        event: event,
        state: pluginState,
      );
      if (!canHandle) {
        continue;
      }

      try {
        final result = await plugin.handleEvent(event);
        finalResult = result;
        if (result.shouldStopPropagation) {
          break;
        }
      } on Object catch (e, stackTrace) {
        _safeLogInputError(
          message: 'Plugin handleEvent failed',
          error: e,
          stackTrace: stackTrace,
          metadata: {
            'plugin': plugin.name,
            'event': event.runtimeType.toString(),
          },
        );
        // Continue with the next plugin.
      }
    }
    return finalResult;
  }

  Future<bool> _isInterceptedByBeforeHooks(
    InputEvent event,
    List<InputPlugin> pluginsForEvent,
  ) async {
    for (final plugin in pluginsForEvent) {
      try {
        if (await plugin.onBeforeEvent(event)) {
          return true;
        }
      } on Object catch (e, stackTrace) {
        _safeLogInputError(
          message: 'Plugin beforeEvent failed',
          error: e,
          stackTrace: stackTrace,
          metadata: {
            'plugin': plugin.name,
            'event': event.runtimeType.toString(),
          },
        );
      }
    }
    return false;
  }

  bool _safeCanHandle({
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

  Future<void> _runAfterHooks(
    InputEvent event,
    PluginResult? result,
    List<InputPlugin> pluginsForEvent,
  ) async {
    for (final plugin in pluginsForEvent) {
      try {
        await plugin.onAfterEvent(event, result);
      } on Object catch (e, stackTrace) {
        _safeLogInputError(
          message: 'Plugin afterEvent failed',
          error: e,
          stackTrace: stackTrace,
          metadata: {
            'plugin': plugin.name,
            'event': event.runtimeType.toString(),
          },
        );
      }
    }
  }

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

  void _registerLoadedPlugins(Iterable<InputPlugin> plugins) {
    for (final plugin in plugins) {
      _plugins.add(plugin);
      _pluginMap[plugin.id] = plugin;
    }
    _markPluginGraphDirty();
  }

  void _markPluginGraphDirty() {
    _isSorted = false;
    _eventTypeIndexDirty = true;
  }

  /// Get plugin statistics.
  Map<String, dynamic> getStats() {
    _ensureSorted();
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
