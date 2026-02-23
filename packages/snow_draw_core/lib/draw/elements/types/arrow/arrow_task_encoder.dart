import '../../../models/element_state.dart';
import '../../../render/tasks/render_tasks.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../core/typed_element_render_task_encoder.dart';
import 'arrow_data.dart';

/// Encodes arrows into high-level render tasks.
final class ArrowTaskEncoder extends TypedElementRenderTaskEncoder<ArrowData> {
  /// Creates an arrow task encoder.
  const ArrowTaskEncoder();

  @override
  List<RenderTask> encodeTypedTasks({
    required ElementState element,
    required ArrowData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) => <RenderTask>[
    ArrowRenderTask(element: element, data: data, localeTag: localeTag),
  ];
}
