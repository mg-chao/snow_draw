import '../../utils/id_generator.dart';
import '../config/config_manager.dart';
import '../config/draw_config.dart';
import '../edit/core/edit_config.dart';
import '../edit/core/edit_config_provider.dart';
import '../edit/core/edit_intent_to_operation_mapper.dart';
import '../edit/edit_operation_registry_interface.dart';
import '../edit/edit_operations.dart';
import '../elements/core/element_registry.dart';
import '../elements/core/element_registry_interface.dart';
import '../events/event_bus.dart';
import '../services/log/log_service.dart';
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
    DrawConfig? config,
    ConfigManager? configManager,
    this.editConfigProvider = StaticEditConfigProvider.defaults,
    LogService? logService,
    this.eventBus,
  }) : configManager =
           configManager ?? ConfigManager(config ?? DrawConfig.defaultConfig),
       editIntentMapper =
           editIntentMapper ?? EditIntentToOperationMapper.withDefaults(),
       log = logService ?? LogService() {
    if (configManager != null &&
        config != null &&
        config != this.configManager.current) {
      this.configManager.update(config);
    }
  }

  factory DrawContext.withDefaults({
    ElementRegistry? elementRegistry,
    EditOperationRegistry? editOperations,
    IdGenerator? idGenerator,
    EditIntentToOperationMapper? editIntentMapper,
    DrawConfig? config,
    ConfigManager? configManager,
    EditConfigProvider? editConfigProvider,
    LogService? logService,
    EventBus? eventBus,
  }) => DrawContext(
    elementRegistry: elementRegistry ?? DefaultElementRegistry(),
    editOperations:
        editOperations ?? DefaultEditOperationRegistry.withDefaults(),
    idGenerator: idGenerator ?? RandomStringIdGenerator().call,
    editIntentMapper: editIntentMapper,
    config: config,
    configManager: configManager,
    editConfigProvider: editConfigProvider ?? StaticEditConfigProvider.defaults,
    logService: logService,
    eventBus: eventBus,
  );

  factory DrawContext.defaultContext() => DrawContext.withDefaults();
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

  /// Edit configuration provider.
  @override
  final EditConfigProvider editConfigProvider;

  /// Logging service.
  ///
  /// Provides unified logging with modular logs and multiple outputs.
  @override
  final LogService log;

  /// Event bus for UI-facing diagnostics and errors.
  @override
  final EventBus? eventBus;

  /// Convenient access to edit configuration.
  EditConfig get editConfig => editConfigProvider.editConfig;

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
    DrawConfig? config,
    ConfigManager? configManager,
    EditConfigProvider? editConfigProvider,
    LogService? logService,
    EventBus? eventBus,
  }) {
    final hasEquivalentConfig =
        config != null && config == this.configManager.current;
    final resolvedConfigManager =
        configManager ??
        (config == null || hasEquivalentConfig
            ? this.configManager
            : ConfigManager(config));
    return DrawContext(
      elementRegistry: elementRegistry ?? this.elementRegistry,
      editOperations: editOperations ?? this.editOperations,
      idGenerator: idGenerator ?? this.idGenerator,
      editIntentMapper: editIntentMapper ?? this.editIntentMapper,
      config: config,
      configManager: resolvedConfigManager,
      editConfigProvider: editConfigProvider ?? this.editConfigProvider,
      logService: logService ?? log,
      eventBus: eventBus ?? this.eventBus,
    );
  }
}
