import '../../../models/element_state.dart';
import '../../../render/tasks/render_tasks.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../core/typed_element_render_task_encoder.dart';
import 'highlight_data.dart';

/// Encodes highlight elements into high-level render tasks.
final class HighlightTaskEncoder
    extends TypedElementRenderTaskEncoder<HighlightData> {
  /// Creates a highlight task encoder.
  const HighlightTaskEncoder();

  @override
  List<RenderTask> encodeTypedTasks({
    required ElementState element,
    required HighlightData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) => <RenderTask>[
    HighlightRenderTask(element: element, data: data, localeTag: localeTag),
  ];
}
