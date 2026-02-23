import 'package:snow_draw_core/snow_draw_core.dart';

import '../services/text/flutter_text_metrics_service.dart';

/// Creates a [DrawContext] preconfigured for the Flutter backend.
///
/// By default this registers built-in element definitions and wires the
/// Flutter text metrics service so core reducers and scene encoders use
/// consistent layout behavior with the backend renderer.
///
/// Pass a custom [ElementRegistry] when consumers need full control over
/// registration. Built-in auto-registration requires
/// [MutableElementRegistry].
///
/// [textMetricsService] and [eventBus] can be overridden for tests or hosts
/// that need custom instrumentation.
DrawContext createFlutterDrawContext({
  ElementRegistry? elementRegistry,
  IdGenerator? idGenerator,
  DrawConfig? config,
  LogService? logService,
  TextMetricsService? textMetricsService,
  EventBus? eventBus,
  bool registerBuiltInElementDefinitions = true,
}) {
  final registry = resolveElementRegistry(
    elementRegistry: elementRegistry,
    registerBuiltInElementDefinitions: registerBuiltInElementDefinitions,
  );

  return DrawContext.withDefaults(
    elementRegistry: registry,
    idGenerator: idGenerator,
    config: config,
    logService: logService,
    textMetricsService: textMetricsService ?? flutterTextMetricsService,
    eventBus: eventBus,
  );
}
