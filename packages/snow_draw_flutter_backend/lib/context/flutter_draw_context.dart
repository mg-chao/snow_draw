import 'package:snow_draw_core/snow_draw_core.dart';

import '../services/text/flutter_text_metrics_service.dart';

/// Creates a [DrawContext] preconfigured for the Flutter backend.
///
/// By default this registers built-in element definitions and wires the
/// Flutter text metrics service so core reducers and scene encoders use
/// consistent layout behavior with the backend renderer.
DrawContext createFlutterDrawContext({
  DefaultElementRegistry? elementRegistry,
  IdGenerator? idGenerator,
  DrawConfig? config,
  LogService? logService,
  bool registerBuiltInElementDefinitions = true,
}) {
  final registry = elementRegistry ?? DefaultElementRegistry();
  if (registerBuiltInElementDefinitions) {
    registerBuiltInElements(registry);
  }

  return DrawContext.withDefaults(
    elementRegistry: registry,
    idGenerator: idGenerator,
    config: config,
    logService: logService,
    textMetricsService: flutterTextMetricsService,
  );
}
