import '../../../models/element_state.dart';
import '../../../render/tasks/render_tasks.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../core/typed_element_render_task_encoder.dart';
import 'free_draw_data.dart';

/// Encodes free-draw elements into high-level render tasks.
final class FreeDrawTaskEncoder
    extends TypedElementRenderTaskEncoder<FreeDrawData> {
  /// Creates a free-draw task encoder.
  const FreeDrawTaskEncoder();

  @override
  List<RenderTask> encodeTypedTasks({
    required ElementState element,
    required FreeDrawData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) => <RenderTask>[
    FreeDrawRenderTask(element: element, data: data, localeTag: localeTag),
  ];
}
