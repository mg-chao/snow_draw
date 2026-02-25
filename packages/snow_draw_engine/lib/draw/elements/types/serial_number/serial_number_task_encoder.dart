import '../../../models/element_state.dart';
import '../../../render/tasks/render_tasks.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../core/typed_element_render_task_encoder.dart';
import 'serial_number_data.dart';

/// Encodes serial-number elements into high-level render tasks.
final class SerialNumberTaskEncoder
    extends TypedElementRenderTaskEncoder<SerialNumberData> {
  /// Creates a serial-number task encoder.
  const SerialNumberTaskEncoder();

  @override
  List<RenderTask> encodeTypedTasks({
    required ElementState element,
    required SerialNumberData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) => <RenderTask>[
    SerialNumberRenderTask(element: element, data: data, localeTag: localeTag),
  ];
}
