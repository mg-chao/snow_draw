import 'dart:math' as math;

import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/typed_element_scene_encoder.dart';
import '../shared/scene_encoder_style_utils.dart';
import 'rectangle_data.dart';

/// Encodes rectangle elements into backend-agnostic scene primitives.
final class RectangleSceneEncoder
    extends TypedElementSceneEncoder<RectangleData> {
  /// Creates a rectangle scene encoder.
  const RectangleSceneEncoder();

  static const _kappa = 0.5522847498307936;
  static const double _lineFillAngle = -math.pi / 4;
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

    final path = _buildRoundedRectPath(element.rect, data.cornerRadius);
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
          angleRadians: _lineFillAngle,
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

  static RenderPath _buildRoundedRectPath(DrawRect rect, double cornerRadius) {
    final width = rect.width;
    final height = rect.height;
    final left = -width / 2;
    final top = -height / 2;
    final right = width / 2;
    final bottom = height / 2;

    final maxRadius = math.min(width, height) / 2;
    final radius = cornerRadius.clamp(0.0, maxRadius);
    if (radius == 0) {
      return RenderPath(<RenderPathCommand>[
        RenderMoveTo(DrawPoint(x: left, y: top)),
        RenderLineTo(DrawPoint(x: right, y: top)),
        RenderLineTo(DrawPoint(x: right, y: bottom)),
        RenderLineTo(DrawPoint(x: left, y: bottom)),
        const RenderClosePath(),
      ]);
    }

    final controlOffset = radius * _kappa;
    return RenderPath(<RenderPathCommand>[
      RenderMoveTo(DrawPoint(x: left + radius, y: top)),
      RenderLineTo(DrawPoint(x: right - radius, y: top)),
      RenderCubicTo(
        control1: DrawPoint(x: right - radius + controlOffset, y: top),
        control2: DrawPoint(x: right, y: top + radius - controlOffset),
        end: DrawPoint(x: right, y: top + radius),
      ),
      RenderLineTo(DrawPoint(x: right, y: bottom - radius)),
      RenderCubicTo(
        control1: DrawPoint(x: right, y: bottom - radius + controlOffset),
        control2: DrawPoint(x: right - radius + controlOffset, y: bottom),
        end: DrawPoint(x: right - radius, y: bottom),
      ),
      RenderLineTo(DrawPoint(x: left + radius, y: bottom)),
      RenderCubicTo(
        control1: DrawPoint(x: left + radius - controlOffset, y: bottom),
        control2: DrawPoint(x: left, y: bottom - radius + controlOffset),
        end: DrawPoint(x: left, y: bottom - radius),
      ),
      RenderLineTo(DrawPoint(x: left, y: top + radius)),
      RenderCubicTo(
        control1: DrawPoint(x: left, y: top + radius - controlOffset),
        control2: DrawPoint(x: left + radius - controlOffset, y: top),
        end: DrawPoint(x: left + radius, y: top),
      ),
      const RenderClosePath(),
    ]);
  }
}
