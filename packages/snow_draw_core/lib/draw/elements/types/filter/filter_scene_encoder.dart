import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../core/element_scene_encoder.dart';
import 'filter_data.dart';

/// Encodes filter elements into backend-agnostic scene primitives.
///
/// Filter elements are composed by the backend scene compositor, not by per-
/// element draw primitives. This encoder intentionally emits an empty scene
/// to keep the scene path compatible with existing behavior.
final class FilterSceneEncoder implements ElementSceneEncoder<FilterData> {
  /// Creates a filter scene encoder.
  const FilterSceneEncoder();

  @override
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
    assert(scaleFactor.isFinite, 'scaleFactor must be finite.');
    assert(
      localeTag == null || localeTag.isNotEmpty,
      'localeTag must be null or non-empty.',
    );

    final data = element.data;
    if (data is! FilterData) {
      throw StateError(
        'FilterSceneEncoder can only encode FilterData (got '
        '${data.runtimeType})',
      );
    }
    return const RenderScene(primitives: <RenderPrimitive>[]);
  }
}
