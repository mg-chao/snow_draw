import '../../../models/element_state.dart';
import '../../../render/tasks/render_tasks.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../core/typed_element_render_task_encoder.dart';
import 'text_data.dart';

/// Encodes text elements into high-level render tasks.
final class TextTaskEncoder extends TypedElementRenderTaskEncoder<TextData> {
  /// Creates a text task encoder.
  const TextTaskEncoder();

  @override
  List<RenderTask> encodeTypedTasks({
    required ElementState element,
    required TextData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) => <RenderTask>[
    TextRenderTask(element: element, data: data, localeTag: localeTag),
  ];
}
