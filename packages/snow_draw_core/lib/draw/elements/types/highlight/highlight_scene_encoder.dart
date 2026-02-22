import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/typed_element_scene_encoder.dart';
import '../shared/scene_encoder_style_utils.dart';
import 'highlight_data.dart';

/// Encodes highlight elements into backend-agnostic scene primitives.
final class HighlightSceneEncoder
    extends TypedElementSceneEncoder<HighlightData> {
  /// Creates a highlight scene encoder.
  const HighlightSceneEncoder();

  static const _kappa = 0.5522847498307936;

  @override
  RenderScene encodeTypedScene({
    required ElementState element,
    required HighlightData data,
    required double scaleFactor,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
    final fillColorArgb = applyElementOpacityToArgb(
      argb: data.color.toARGB32(),
      elementOpacity: element.opacity,
    );
    final strokeColorArgb = applyElementOpacityToArgb(
      argb: data.strokeColor.toARGB32(),
      elementOpacity: element.opacity,
    );
    final shouldFill = isArgbVisible(fillColorArgb);
    final shouldStroke = isArgbVisible(strokeColorArgb) && data.strokeWidth > 0;
    if (!shouldFill && !shouldStroke) {
      return emptyRenderScene;
    }

    final shapePath = _buildShapePath(rect: element.rect, data: data);
    final localScene = SceneBuilder();
    if (shouldFill) {
      final fillChild = SceneBuilder()
        ..addPathFill(path: shapePath, colorArgb: fillColorArgb);
      localScene.addFilterGroup(
        filterType: 'blend_multiply',
        child: fillChild.build(),
      );
    }
    if (shouldStroke) {
      localScene.addPathStroke(
        path: shapePath,
        colorArgb: strokeColorArgb,
        strokeWidth: data.strokeWidth,
      );
    }

    return composeElementScene(
      element: element,
      localScene: localScene.build(),
    );
  }

  static RenderPath _buildShapePath({
    required DrawRect rect,
    required HighlightData data,
  }) {
    final width = rect.width;
    final height = rect.height;
    final left = -width / 2;
    final top = -height / 2;
    final right = width / 2;
    final bottom = height / 2;

    return switch (data.shape) {
      HighlightShape.rectangle => RenderPath(<RenderPathCommand>[
        RenderMoveTo(DrawPoint(x: left, y: top)),
        RenderLineTo(DrawPoint(x: right, y: top)),
        RenderLineTo(DrawPoint(x: right, y: bottom)),
        RenderLineTo(DrawPoint(x: left, y: bottom)),
        const RenderClosePath(),
      ]),
      HighlightShape.ellipse => _buildEllipsePath(width: width, height: height),
    };
  }

  static RenderPath _buildEllipsePath({
    required double width,
    required double height,
  }) {
    final radiusX = width / 2;
    final radiusY = height / 2;
    final controlX = radiusX * _kappa;
    final controlY = radiusY * _kappa;
    return RenderPath(<RenderPathCommand>[
      RenderMoveTo(DrawPoint(x: 0, y: -radiusY)),
      RenderCubicTo(
        control1: DrawPoint(x: controlX, y: -radiusY),
        control2: DrawPoint(x: radiusX, y: -controlY),
        end: DrawPoint(x: radiusX, y: 0),
      ),
      RenderCubicTo(
        control1: DrawPoint(x: radiusX, y: controlY),
        control2: DrawPoint(x: controlX, y: radiusY),
        end: DrawPoint(x: 0, y: radiusY),
      ),
      RenderCubicTo(
        control1: DrawPoint(x: -controlX, y: radiusY),
        control2: DrawPoint(x: -radiusX, y: controlY),
        end: DrawPoint(x: -radiusX, y: 0),
      ),
      RenderCubicTo(
        control1: DrawPoint(x: -radiusX, y: -controlY),
        control2: DrawPoint(x: -controlX, y: -radiusY),
        end: DrawPoint(x: 0, y: -radiusY),
      ),
      const RenderClosePath(),
    ]);
  }
}
