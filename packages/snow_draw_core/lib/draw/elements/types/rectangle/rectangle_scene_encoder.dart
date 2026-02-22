import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/element_style.dart';
import '../../core/typed_element_scene_encoder.dart';
import '../shared/scene_encoder_path_utils.dart';
import '../shared/scene_encoder_style_utils.dart';
import 'rectangle_data.dart';

/// Encodes rectangle elements into backend-agnostic scene primitives.
final class RectangleSceneEncoder
    extends TypedElementSceneEncoder<RectangleData> {
  /// Creates a rectangle scene encoder.
  const RectangleSceneEncoder();

  @override
  RenderScene encodeTypedScene({
    required ElementState element,
    required RectangleData data,
    required double scaleFactor,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
    final fillColorArgb = applyElementOpacityToArgb(
      argb: data.fillColor.toARGB32(),
      elementOpacity: element.opacity,
    );
    final strokeColorArgb = applyElementOpacityToArgb(
      argb: data.color.toARGB32(),
      elementOpacity: element.opacity,
    );
    final fillVisible = isArgbVisible(fillColorArgb);
    final strokeVisible =
        isArgbVisible(strokeColorArgb) && data.strokeWidth > 0;
    if (!fillVisible && !strokeVisible) {
      return emptyRenderScene;
    }

    final path = buildCenteredRoundedRectPath(
      rect: element.rect,
      cornerRadius: data.cornerRadius,
    );
    final localBuilder = SceneBuilder();
    if (fillVisible) {
      if (data.fillStyle == FillStyle.solid) {
        localBuilder.addPathFill(path: path, colorArgb: fillColorArgb);
      } else {
        final hatch = resolveStrokeHatchStyle(strokeWidth: data.strokeWidth);
        localBuilder.addHatchPathFill(
          path: path,
          clipBounds: resolveCenteredLocalClipBounds(element.rect),
          colorArgb: fillColorArgb,
          lineWidth: hatch.lineWidth,
          spacing: hatch.spacing,
          angleRadians: defaultHatchAngleRadians,
          pattern: resolveHatchPattern(data.fillStyle),
        );
      }
    }
    if (strokeVisible) {
      localBuilder.addPathStroke(
        path: path,
        colorArgb: strokeColorArgb,
        strokeWidth: data.strokeWidth,
        strokeCap: resolveStrokeCap(data.strokeStyle),
        dashPattern: resolveStrokeDashPattern(
          strokeStyle: data.strokeStyle,
          strokeWidth: data.strokeWidth,
        ),
      );
    }

    return composeElementScene(
      element: element,
      localScene: localBuilder.build(),
    );
  }
}
