import '../../models/element_state.dart';
import '../../render/scene/render_scene.dart';
import 'element_data.dart';

/// Encodes an element state into backend-agnostic scene primitives.
abstract interface class ElementSceneEncoder<T extends ElementData> {
  /// Builds a [RenderScene] for [element].
  ///
  /// [localeTag] uses BCP-47 language tag format when provided.
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
  });
}
