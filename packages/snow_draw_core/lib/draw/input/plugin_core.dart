import 'package:meta/meta.dart';

import '../actions/draw_actions.dart';
import '../config/draw_config.dart';
import '../core/draw_context.dart';
import '../models/draw_state.dart';
import 'input_event.dart';

/// Action dispatcher interface.
///
/// Defines action dispatch capability, decoupled from store implementations.
typedef ActionDispatcher = Future<void> Function(DrawAction action);

/// Batch action dispatcher (optional extension).
abstract interface class BatchActionDispatcher {
  Future<void> call(DrawAction action);

  /// Dispatch multiple actions in batch.
  Future<void> dispatchAll(Iterable<DrawAction> actions);
}

/// State provider for input systems.
abstract interface class StateProvider {
  DrawState get currentState;
}

/// Controller dependencies.
///
/// Encapsulates all external dependencies a controller needs for testing or
/// replacement.
class ControllerDependencies implements StateProvider {
  const ControllerDependencies({
    required ActionDispatcher dispatcher,
    required StateProvider stateProvider,
    required DrawContext Function() contextProvider,
    required SelectionConfig Function() selectionConfigProvider,
  }) : _dispatcher = dispatcher,
       _stateProvider = stateProvider,
       _contextProvider = contextProvider,
       _selectionConfigProvider = selectionConfigProvider;
  final ActionDispatcher _dispatcher;
  final StateProvider _stateProvider;
  final DrawContext Function() _contextProvider;
  final SelectionConfig Function() _selectionConfigProvider;

  Future<void> call(DrawAction action) => _dispatcher(action);

  Future<void> dispatch(DrawAction action) => call(action);

  @override
  DrawState get currentState => _stateProvider.currentState;

  /// Get the DrawContext.
  DrawContext get context => _contextProvider();

  /// Get selection configuration.
  SelectionConfig get selectionConfig => _selectionConfigProvider();
}

enum EditPointerDownBehavior { ignore, cancelEdit, commitEdit }

/// Explicit routing policy for input while editing.
class InputRoutingPolicy {
  const InputRoutingPolicy({
    this.allowSelectionWhileEditing = false,
    this.allowBoxSelectWhileEditing = false,
    this.allowCreateWhileEditing = false,
    this.editPointerDownBehavior = EditPointerDownBehavior.ignore,
  });
  final bool allowSelectionWhileEditing;
  final bool allowBoxSelectWhileEditing;
  final bool allowCreateWhileEditing;
  final EditPointerDownBehavior editPointerDownBehavior;

  static const defaultPolicy = InputRoutingPolicy();

  bool allowSelection(DrawState state) =>
      !state.application.isEditing || allowSelectionWhileEditing;

  bool allowBoxSelect(DrawState state) =>
      !state.application.isEditing || allowBoxSelectWhileEditing;

  bool allowCreate(DrawState state) =>
      !state.application.isEditing || allowCreateWhileEditing;
}

/// Plugin handling result.
@immutable
class PluginResult {
  const PluginResult._({required this.status, this.message});

  /// Event handled; stop propagation to other plugins.
  const PluginResult.handled({String? message})
    : this._(status: PluginResultStatus.handled, message: message);

  /// Event unhandled; continue propagation to the next plugin.
  const PluginResult.unhandled({String? reason})
    : this._(status: PluginResultStatus.unhandled, message: reason);

  /// Event consumed; allow others to observe (do not stop propagation).
  const PluginResult.consumed({String? message})
    : this._(status: PluginResultStatus.consumed, message: message);

  /// Handling status.
  final PluginResultStatus status;

  /// Optional message or reason.
  final String? message;

  bool get isHandled => status == PluginResultStatus.handled;
  bool get isUnhandled => status == PluginResultStatus.unhandled;
  bool get isConsumed => status == PluginResultStatus.consumed;

  /// Whether propagation should stop.
  bool get shouldStopPropagation => status == PluginResultStatus.handled;

  @override
  String toString() {
    final msg = message != null ? ': $message' : '';
    return 'PluginResult.${status.name}$msg';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginResult &&
          other.status == status &&
          other.message == message;

  @override
  int get hashCode => Object.hash(status, message);
}

/// Plugin handling status enum.
enum PluginResultStatus {
  /// Event handled; stop propagation.
  handled,

  /// Event unhandled; continue propagation.
  unhandled,

  /// Event consumed; observation allowed.
  consumed,
}

/// Plugin context.
///
/// Provides dependencies and services required by plugins.
@immutable
class PluginContext {
  const PluginContext({
    required this.stateProvider,
    required this.contextProvider,
    required this.selectionConfigProvider,
    required this.dispatcher,
    Map<Type, Object>? services,
  }) : _services = services ?? const {};

  /// State provider.
  final DrawState Function() stateProvider;

  /// DrawContext provider.
  final DrawContext Function() contextProvider;

  /// Selection configuration provider.
  final SelectionConfig Function() selectionConfigProvider;

  /// Action dispatcher.
  final ActionDispatcher dispatcher;

  /// Service locator (optional, for advanced scenarios).
  final Map<Type, Object> _services;

  /// Get the current state.
  DrawState get state => stateProvider();

  /// Get the DrawContext.
  DrawContext get context => contextProvider();

  /// Get selection configuration.
  SelectionConfig get selectionConfig => selectionConfigProvider();

  /// Dispatch an action.
  Future<void> dispatch(DrawAction action) => dispatcher(action);

  /// Register a service (for inter-plugin communication).
  PluginContext registerService<T extends Object>(T service) {
    final newServices = Map<Type, Object>.from(_services);
    newServices[T] = service;
    return PluginContext(
      stateProvider: stateProvider,
      contextProvider: contextProvider,
      selectionConfigProvider: selectionConfigProvider,
      dispatcher: dispatcher,
      services: newServices,
    );
  }

  /// Get a service.
  T? getService<T extends Object>() => _services[T] as T?;

  /// Check whether a service exists.
  bool hasService<T extends Object>() => _services.containsKey(T);

  /// Create a copy.
  PluginContext copyWith({
    DrawState Function()? stateProvider,
    DrawContext Function()? contextProvider,
    SelectionConfig Function()? selectionConfigProvider,
    ActionDispatcher? dispatcher,
    Map<Type, Object>? services,
  }) => PluginContext(
    stateProvider: stateProvider ?? this.stateProvider,
    contextProvider: contextProvider ?? this.contextProvider,
    selectionConfigProvider:
        selectionConfigProvider ?? this.selectionConfigProvider,
    dispatcher: dispatcher ?? this.dispatcher,
    services: services ?? _services,
  );
}

/// Input plugin interface.
///
/// Plugins are pluggable input handlers. Each plugin owns specific input logic.
/// Plugins can be registered/unregistered dynamically and run by priority.
abstract interface class InputPlugin {
  /// Plugin unique identifier.
  String get id;

  /// Plugin name (for debugging and logging).
  String get name;

  /// Priority (lower number means higher priority, 0-100).
  ///
  /// Suggested ranges:
  /// - 0-9: system plugins (editing, gesture recognition, and so on)
  /// - 10-19: core interaction plugins (create, select, and so on)
  /// - 20-29: utility plugins
  /// - 30+: custom plugins
  int get priority;

  /// Event types supported by the plugin.
  Set<Type> get supportedEventTypes;

  /// Lifecycle: called when the plugin loads.
  Future<void> onLoad(PluginContext context);

  /// Lifecycle: called when the plugin unloads.
  Future<void> onUnload();

  /// Determine whether the plugin can handle the current event.
  ///
  /// Returning true means [handleEvent] will be called.
  bool canHandle(InputEvent event, DrawState state);

  /// Handle an input event.
  ///
  /// Returns [PluginResult]:
  /// - handled: event handled, stop propagation
  /// - unhandled: event not handled, continue propagation
  /// - consumed: event consumed, allow other plugins to observe
  Future<PluginResult> handleEvent(InputEvent event);

  /// Pre-event hook (optional).
  ///
  /// Called before any plugin handles the event, useful for:
  /// - Event preprocessing
  /// - Logging
  /// - Performance monitoring
  ///
  /// Return true to intercept the event and stop processing.
  Future<bool> onBeforeEvent(InputEvent event) async => false;

  /// Post-event hook (optional).
  ///
  /// Called after event processing regardless of result.
  Future<void> onAfterEvent(InputEvent event, PluginResult? result) async {}

  /// Reset plugin state.
  void reset() {}
}

/// Input plugin base class.
///
/// Provides default implementations and helpers to simplify plugin development.
abstract class InputPluginBase implements InputPlugin {
  InputPluginBase({
    required String id,
    required String name,
    required int priority,
    required Set<Type> supportedEventTypes,
  }) : _id = id,
       _name = name,
       _priority = priority,
       _supportedEventTypes = supportedEventTypes;
  final String _id;
  final String _name;
  final int _priority;
  final Set<Type> _supportedEventTypes;

  PluginContext? _context;

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  int get priority => _priority;

  @override
  Set<Type> get supportedEventTypes => _supportedEventTypes;

  /// Get the plugin context.
  @protected
  PluginContext get context {
    if (_context == null) {
      throw StateError('Plugin $name has not been loaded yet');
    }
    return _context!;
  }

  /// Check whether the plugin is loaded.
  @protected
  bool get isLoaded => _context != null;

  @override
  Future<void> onLoad(PluginContext context) async {
    _context = context;
  }

  @override
  Future<void> onUnload() async {
    _context = null;
  }

  @override
  Future<bool> onBeforeEvent(InputEvent event) async => false;

  @override
  Future<void> onAfterEvent(InputEvent event, PluginResult? result) async {}

  @override
  void reset() {}

  /// Helper: create a handled result.
  @protected
  PluginResult handled({String? message}) =>
      PluginResult.handled(message: message);

  /// Helper: create an unhandled result.
  @protected
  PluginResult unhandled({String? reason}) =>
      PluginResult.unhandled(reason: reason);

  /// Helper: create a consumed result.
  @protected
  PluginResult consumed({String? message}) =>
      PluginResult.consumed(message: message);

  /// Helper: check whether the event type is supported.
  @protected
  bool isEventTypeSupported(InputEvent event) =>
      _supportedEventTypes.contains(event.runtimeType);
}

/// Base class for draw input plugins.
abstract class DrawInputPlugin extends InputPluginBase {
  DrawInputPlugin({
    required super.id,
    required super.name,
    required super.priority,
    required super.supportedEventTypes,
  });

  @protected
  DrawState get state => context.state;

  @protected
  DrawContext get drawContext => context.context;

  @protected
  SelectionConfig get selectionConfig => context.selectionConfig;

  @protected
  Future<void> dispatch(DrawAction action) => context.dispatch(action);
}
