import '../../utils/id_generator.dart';
import '../config/config_manager.dart';
import '../config/draw_config.dart';
import '../edit/core/edit_intent_to_operation_mapper.dart';
import '../edit/edit_operations.dart';
import '../elements/core/element_registry.dart';
import '../elements/registration.dart';
import '../events/event_bus.dart';
import '../services/log/log_service.dart';
import '../services/text/text_metrics_service.dart';

/// Canvas context holding all injectable dependencies.
///
/// This replaces global singletons and enables testability and multi-canvas
/// isolation.
class DrawContext {
  DrawContext({
    required this.elementRegistry,
    required this.editOperations,
    required this.idGenerator,
    EditIntentToOperationMapper? editIntentMapper,
    ConfigManager? configManager,
    LogService? logService,
    TextMetricsService? textMetricsService,
    this.eventBus,
  }) : configManager = configManager ?? ConfigManager(DrawConfig.defaultConfig),
       editIntentMapper =
           editIntentMapper ?? EditIntentToOperationMapper.withDefaults(),
       log = logService ?? LogService(),
       textMetricsService = textMetricsService ?? defaultTextMetricsService;

  /// Creates a context with built-in defaults.
  ///
  /// If [elementRegistry] is omitted, a new registry is created and seeded
  /// with built-in element definitions. A provided [elementRegistry] is used
  /// as-is without additional registration.
  factory DrawContext.withDefaults({
    DefaultElementRegistry? elementRegistry,
    DefaultEditOperationRegistry? editOperations,
    IdGenerator? idGenerator,
    EditIntentToOperationMapper? editIntentMapper,
    ConfigManager? configManager,
    LogService? logService,
    TextMetricsService? textMetricsService,
    EventBus? eventBus,
  }) {
    final resolvedRegistry = elementRegistry ?? resolveElementRegistry();
    return DrawContext(
      elementRegistry: resolvedRegistry,
      editOperations:
          editOperations ?? DefaultEditOperationRegistry.withDefaults(),
      idGenerator: idGenerator ?? RandomStringIdGenerator().call,
      editIntentMapper: editIntentMapper,
      configManager: configManager,
      logService: logService,
      textMetricsService: textMetricsService,
      eventBus: eventBus,
    );
  }
  final DefaultElementRegistry elementRegistry;
  final DefaultEditOperationRegistry editOperations;
  final IdGenerator idGenerator;

  /// Configuration manager (single source of truth).
  final ConfigManager configManager;
  final EditIntentToOperationMapper editIntentMapper;

  /// Logging service.
  ///
  /// Provides unified logging with modular logs and multiple outputs.
  final LogService log;

  /// Text metrics service used by engine text geometry reducers.
  final TextMetricsService textMetricsService;

  /// Event bus for UI-facing diagnostics and errors.
  final EventBus? eventBus;

  /// Convenient access to the current configuration.
  DrawConfig get config => configManager.current;

  /// Configuration change stream.
  Stream<DrawConfig> get configStream => configManager.stream;

  DrawContext copyWith({
    DefaultElementRegistry? elementRegistry,
    DefaultEditOperationRegistry? editOperations,
    IdGenerator? idGenerator,
    EditIntentToOperationMapper? editIntentMapper,
    ConfigManager? configManager,
    LogService? logService,
    TextMetricsService? textMetricsService,
    EventBus? eventBus,
  }) => DrawContext(
    elementRegistry: elementRegistry ?? this.elementRegistry,
    editOperations: editOperations ?? this.editOperations,
    idGenerator: idGenerator ?? this.idGenerator,
    editIntentMapper: editIntentMapper ?? this.editIntentMapper,
    configManager: configManager ?? this.configManager,
    logService: logService ?? log,
    textMetricsService: textMetricsService ?? this.textMetricsService,
    eventBus: eventBus ?? this.eventBus,
  );
}
