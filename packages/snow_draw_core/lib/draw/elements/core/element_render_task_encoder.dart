import '../../models/element_state.dart';
import '../../render/tasks/render_tasks.dart';
import '../../services/text/text_metrics_service.dart';
import 'element_data.dart';

/// Encodes an element state into backend-executable render tasks.
abstract interface class ElementRenderTaskEncoder<T extends ElementData> {
  /// Builds render tasks for [element].
  ///
  /// [localeTag] uses BCP-47 language tag format when provided.
  List<RenderTask> encodeTasks({
    required ElementState element,
    String? localeTag,
    TextMetricsService? textMetricsService,
  });
}
