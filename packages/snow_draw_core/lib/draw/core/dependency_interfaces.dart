import '../../utils/id_generator.dart';
import '../config/draw_config.dart';
import '../edit/core/edit_config_provider.dart';
import '../edit/core/edit_intent_to_operation_mapper.dart';
import '../edit/edit_operation_registry_interface.dart';
import '../elements/core/element_registry_interface.dart';
import '../events/event_bus.dart';
import '../services/log/log_service.dart';
import '../services/text/text_metrics_service.dart';

/// Lightweight dependency interfaces to avoid service-locator coupling.
abstract class HasConfig {
  DrawConfig get config;
}

abstract class HasElementRegistry {
  ElementRegistry get elementRegistry;
}

abstract class HasIdGenerator {
  IdGenerator get idGenerator;
}

abstract class HasEditConfigProvider {
  EditConfigProvider get editConfigProvider;
}

abstract class HasEditIntentMapper {
  EditIntentToOperationMapper get editIntentMapper;
}

abstract class HasEditOperations {
  EditOperationRegistry get editOperations;
}

abstract class HasLogService {
  LogService get log;
}

abstract class HasEventBus {
  EventBus? get eventBus;
}

abstract class HasTextMetricsService {
  TextMetricsService get textMetricsService;
}

/// Reducer-specific dependency interfaces.
abstract class CreateElementReducerDeps
    implements HasConfig, HasElementRegistry, HasIdGenerator {}

abstract class TextEditReducerDeps
    implements HasConfig, HasIdGenerator, HasTextMetricsService {}

abstract class SelectionReducerDeps implements HasLogService, HasEventBus {}

abstract class ElementReducerDeps
    implements
        HasLogService,
        HasEventBus,
        HasIdGenerator,
        HasConfig,
        HasTextMetricsService {}

abstract class EditReducerDeps implements HasEditConfigProvider {}

abstract class EditIntentResolverDeps
    implements HasEditIntentMapper, HasEditOperations {}

abstract class CameraReducerDeps {}

/// Aggregate dependencies available on DrawContext.
abstract class DrawContextDeps
    implements
        CreateElementReducerDeps,
        TextEditReducerDeps,
        SelectionReducerDeps,
        ElementReducerDeps,
        EditReducerDeps,
        EditIntentResolverDeps {}

/// Aggregate deps for interaction state reduction.
abstract class InteractionReducerDeps
    implements DrawContextDeps, CameraReducerDeps {}
