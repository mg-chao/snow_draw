import '../../../models/element_state.dart';
import '../../../render/tasks/render_tasks.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../core/typed_element_render_task_encoder.dart';
import 'filter_data.dart';

/// Encodes filter elements into high-level render tasks.
final class FilterTaskEncoder
    extends TypedElementRenderTaskEncoder<FilterData> {
  /// Creates a filter task encoder.
  const FilterTaskEncoder();

  @override
  List<RenderTask> encodeTypedTasks({
    required ElementState element,
    required FilterData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) => <RenderTask>[
    FilterRenderTask(element: element, data: data, localeTag: localeTag),
  ];
}
