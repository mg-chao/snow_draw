import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../core/typed_element_scene_encoder.dart';
import 'filter_data.dart';

/// Encodes filter elements into backend-agnostic scene primitives.
///
/// Filter elements are composed by the backend scene compositor, not by per-
/// element draw primitives. This encoder intentionally emits an empty scene
/// to keep the scene path compatible with existing behavior.
final class FilterSceneEncoder extends TypedElementSceneEncoder<FilterData> {
  /// Creates a filter scene encoder.
  const FilterSceneEncoder();

  @override
  RenderScene encodeTypedScene({
    required ElementState element,
    required FilterData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) => emptyRenderScene;
}
