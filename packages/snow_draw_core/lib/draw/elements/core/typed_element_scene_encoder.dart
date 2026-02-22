import 'package:meta/meta.dart';

import '../../models/element_state.dart';
import '../../render/scene/render_scene.dart';
import '../../services/text/text_metrics_service.dart';
import 'element_data.dart';
import 'element_scene_encoder.dart';

/// Base implementation for strongly-typed element scene encoders.
///
/// This centralizes common argument validation and data-type checks so each
/// concrete encoder can focus on building render primitives.
abstract base class TypedElementSceneEncoder<T extends ElementData>
    implements ElementSceneEncoder<T> {
  const TypedElementSceneEncoder();

  /// Shared immutable empty scene used by encoders with no visible output.
  static const RenderScene emptyScene = RenderScene(
    primitives: <RenderPrimitive>[],
  );

  @override
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
    _validateEncodeArguments(scaleFactor: scaleFactor, localeTag: localeTag);
    final data = element.data;
    if (data is! T) {
      throw StateError(
        '$runtimeType can only encode $T (got ${data.runtimeType})',
      );
    }
    return encodeTypedScene(
      element: element,
      data: data,
      scaleFactor: scaleFactor,
      localeTag: localeTag,
      textMetricsService: textMetricsService,
    );
  }

  /// Encodes [element] into scene primitives using typed [data].
  RenderScene encodeTypedScene({
    required ElementState element,
    required T data,
    required double scaleFactor,
    String? localeTag,
    TextMetricsService? textMetricsService,
  });

  /// Wraps a local scene with element-level transform/culling metadata.
  @protected
  RenderScene composeElementScene({
    required ElementState element,
    required RenderScene localScene,
  }) {
    final sceneBuilder = SceneBuilder()
      ..addTransform(
        child: localScene,
        translate: element.center,
        rotation: element.rotation,
      );
    return sceneBuilder.build(cullRect: element.rect);
  }

  @protected
  RenderScene get emptyRenderScene => emptyScene;

  static void _validateEncodeArguments({
    required double scaleFactor,
    required String? localeTag,
  }) {
    assert(scaleFactor.isFinite, 'scaleFactor must be finite.');
    assert(
      localeTag == null || localeTag.isNotEmpty,
      'localeTag must be null or non-empty.',
    );
  }
}
