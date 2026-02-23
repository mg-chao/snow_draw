import 'package:meta/meta.dart';

import '../../models/element_state.dart';
import '../../render/tasks/render_tasks.dart';
import '../../services/text/text_metrics_service.dart';
import 'element_data.dart';
import 'element_render_task_encoder.dart';

/// Base implementation for strongly-typed render-task encoders.
abstract base class TypedElementRenderTaskEncoder<T extends ElementData>
    implements ElementRenderTaskEncoder<T> {
  const TypedElementRenderTaskEncoder();

  @override
  List<RenderTask> encodeTasks({
    required ElementState element,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
    assert(
      localeTag == null || localeTag.isNotEmpty,
      'localeTag must be null or non-empty.',
    );
    final data = element.data;
    if (data is! T) {
      throw StateError(
        '$runtimeType can only encode $T (got ${data.runtimeType})',
      );
    }
    return encodeTypedTasks(
      element: element,
      data: data,
      localeTag: localeTag,
      textMetricsService: textMetricsService,
    );
  }

  /// Encodes [element] into typed render tasks using [data].
  @protected
  List<RenderTask> encodeTypedTasks({
    required ElementState element,
    required T data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  });
}
