import '../../utils/id_generator.dart';
import '../config/config_manager.dart';
import '../config/draw_config.dart';
import '../edit/core/edit_intent_to_operation_mapper.dart';
import '../edit/edit_operation_registry_interface.dart';
import '../edit/edit_operations.dart';
import '../elements/core/element_registry_interface.dart';
import '../elements/registration.dart';
import '../events/event_bus.dart';
import '../services/log/log_service.dart';
import '../services/text/text_metrics_service.dart';
import 'dependency_interfaces.dart';

/// Canvas context holding all injectable dependencies.
///
/// This replaces global singletons and enables testability and multi-canvas
/// isolation.
class DrawContext implements InteractionReducerDeps {
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

  factory DrawContext.withDefaults({
    ElementRegistry? elementRegistry,
    EditOperationRegistry? editOperations,
    IdGenerator? idGenerator,
    EditIntentToOperationMapper? editIntentMapper,
    ConfigManager? configManager,
    LogService? logService,
    TextMetricsService? textMetricsService,
    EventBus? eventBus,
  }) {
    final resolvedRegistry = resolveElementRegistry(
      elementRegistry: elementRegistry,
    );
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
  @override
  final ElementRegistry elementRegistry;
  @override
  final EditOperationRegistry editOperations;
  @override
  final IdGenerator idGenerator;

  /// Configuration manager (single source of truth).
  final ConfigManager configManager;
  @override
  final EditIntentToOperationMapper editIntentMapper;

  /// Logging service.
  ///
  /// Provides unified logging with modular logs and multiple outputs.
  @override
  final LogService log;

  /// Text metrics service used by core text geometry reducers.
  @override
  final TextMetricsService textMetricsService;

  /// Event bus for UI-facing diagnostics and errors.
  @override
  final EventBus? eventBus;

  /// Convenient access to the current configuration.
  @override
  DrawConfig get config => configManager.current;

  /// Configuration change stream.
  Stream<DrawConfig> get configStream => configManager.stream;

  DrawContext copyWith({
    ElementRegistry? elementRegistry,
    EditOperationRegistry? editOperations,
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
