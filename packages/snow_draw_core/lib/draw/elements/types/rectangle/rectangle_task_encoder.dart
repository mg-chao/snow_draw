import '../../../models/element_state.dart';
import '../../../render/tasks/render_tasks.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../core/typed_element_render_task_encoder.dart';
import 'rectangle_data.dart';

/// Encodes rectangles into high-level render tasks.
final class RectangleTaskEncoder
    extends TypedElementRenderTaskEncoder<RectangleData> {
  /// Creates a rectangle task encoder.
  const RectangleTaskEncoder();

  @override
  List<RenderTask> encodeTypedTasks({
    required ElementState element,
    required RectangleData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) => <RenderTask>[
    RectangleRenderTask(element: element, data: data, localeTag: localeTag),
  ];
}
