import '../../../models/element_state.dart';
import '../../../render/tasks/render_tasks.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../core/typed_element_render_task_encoder.dart';
import 'line_data.dart';

/// Encodes lines into high-level render tasks.
final class LineTaskEncoder extends TypedElementRenderTaskEncoder<LineData> {
  /// Creates a line task encoder.
  const LineTaskEncoder();

  @override
  List<RenderTask> encodeTypedTasks({
    required ElementState element,
    required LineData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) => <RenderTask>[
    LineRenderTask(element: element, data: data, localeTag: localeTag),
  ];
}
