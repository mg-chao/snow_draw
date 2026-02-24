import '../../utils/id_generator.dart';
import '../config/draw_config.dart';
import '../edit/edit_operation_registry_interface.dart';
import '../elements/core/element_registry_interface.dart';
import '../events/event_bus.dart';
import '../services/log/log_service.dart';
import '../services/text/text_metrics_service.dart';

/// Lightweight dependency interfaces to avoid service-locator coupling.
abstract interface class CreateElementReducerDeps {
  DrawConfig get config;
  ElementRegistry get elementRegistry;
  IdGenerator get idGenerator;
  TextMetricsService get textMetricsService;
}

abstract interface class TextEditReducerDeps {
  DrawConfig get config;
  IdGenerator get idGenerator;
  TextMetricsService get textMetricsService;
}

abstract interface class SelectionReducerDeps {
  LogService get log;
  EventBus? get eventBus;
}

abstract interface class ElementReducerDeps {
  LogService get log;
  EventBus? get eventBus;
  IdGenerator get idGenerator;
  DrawConfig get config;
  TextMetricsService get textMetricsService;
}

/// Aggregate dependencies available for interaction reducers.
abstract interface class InteractionReducerDeps
    implements
        CreateElementReducerDeps,
        TextEditReducerDeps,
        SelectionReducerDeps,
        ElementReducerDeps {
  EditOperationRegistry get editOperations;
}
