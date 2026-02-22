import 'dart:math' as math;

import '../../../config/draw_config.dart';
import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/typed_element_scene_encoder.dart';
import '../shared/scene_encoder_style_utils.dart';
import 'serial_number_data.dart';
import 'serial_number_layout.dart';

/// Encodes serial-number elements into backend-agnostic scene primitives.
///
/// Supports all current serial-number fill/stroke styles.
final class SerialNumberSceneEncoder
    extends TypedElementSceneEncoder<SerialNumberData> {
  /// Creates a serial-number scene encoder.
  const SerialNumberSceneEncoder();

  static const _kappa = 0.5522847498307936;
  static const _scaleTolerance = 0.0001;
  static const double _lineFillAngle = -math.pi / 4;

  @override
  RenderScene encodeTypedScene({
    required ElementState element,
    required SerialNumberData data,
    required double scaleFactor,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
    final fillColorArgb = applyElementOpacityToArgb(
      argb: data.fillColor.toARGB32(),
      elementOpacity: element.opacity,
    );
    final contentColorArgb = applyElementOpacityToArgb(
      argb: data.color.toARGB32(),
      elementOpacity: element.opacity,
    );
    final shouldFill = isArgbVisible(fillColorArgb);
    final shouldRenderContent = isArgbVisible(contentColorArgb);
    if (!shouldFill && !shouldRenderContent) {
      return emptyRenderScene;
    }
    final strokeWidth = resolveSerialNumberStrokeWidth(data: data);
    final shouldStroke = shouldRenderContent && strokeWidth > 0;

    final diameter = math.min(element.rect.width, element.rect.height);
    if (diameter <= 0 || !diameter.isFinite) {
      return emptyRenderScene;
    }
    final radius = diameter / 2;
    final circlePath = _buildCirclePath(radius: radius);

    final localScene = SceneBuilder();
    if (shouldFill) {
      if (data.fillStyle == FillStyle.solid) {
        localScene.addPathFill(path: circlePath, colorArgb: fillColorArgb);
      } else {
        final hatch = resolveFontHatchStyle(fontSize: data.fontSize);
        localScene.addHatchPathFill(
          path: circlePath,
          clipBounds: _localClipBounds(radius),
          colorArgb: fillColorArgb,
          lineWidth: hatch.lineWidth,
          spacing: hatch.spacing,
          angleRadians: _lineFillAngle,
          pattern: resolveHatchPattern(data.fillStyle),
        );
      }
    }
    if (shouldStroke) {
      localScene.addPathStroke(
        path: circlePath,
        colorArgb: contentColorArgb,
        strokeWidth: strokeWidth,
        strokeCap: resolveStrokeCap(data.strokeStyle),
        dashPattern: resolveStrokeDashPattern(
          strokeStyle: data.strokeStyle,
          strokeWidth: strokeWidth,
        ),
      );
    }
    if (shouldRenderContent) {
      final resolvedTextMetricsService =
          textMetricsService ?? sceneTextMetricsService;
      final textLayout = layoutSerialNumberTextForScene(
        data: data,
        colorArgb: contentColorArgb,
        localeTag: localeTag,
        textMetricsService: resolvedTextMetricsService,
      );
      final paintScale = textLayout.paintScale;
      if (paintScale > 0 && paintScale.isFinite) {
        final visualCenter = resolveSerialNumberVisualCenter(textLayout);
        final localTextOrigin = DrawPoint(
          x: -visualCenter.x / paintScale,
          y: -visualCenter.y / paintScale,
        );
        final textRunScene = SceneBuilder()
          ..addTextRun(
            text: data.number.toString(),
            origin: localTextOrigin,
            fontSize: ConfigDefaults.defaultSerialNumberFontSize,
            colorArgb: contentColorArgb,
            fontFamily: data.fontFamily,
          );
        if ((paintScale - 1).abs() <= _scaleTolerance) {
          localScene.addPrimitive(textRunScene.build().primitives.single);
        } else {
          localScene.addTransform(
            child: textRunScene.build(),
            scaleX: paintScale,
            scaleY: paintScale,
          );
        }
      }
    }

    return composeElementScene(
      element: element,
      localScene: localScene.build(),
    );
  }

  static DrawRect _localClipBounds(double radius) =>
      DrawRect(minX: -radius, minY: -radius, maxX: radius, maxY: radius);

  static RenderPath _buildCirclePath({required double radius}) {
    final control = radius * _kappa;
    return RenderPath(<RenderPathCommand>[
      RenderMoveTo(DrawPoint(x: radius, y: 0)),
      RenderCubicTo(
        control1: DrawPoint(x: radius, y: control),
        control2: DrawPoint(x: control, y: radius),
        end: DrawPoint(x: 0, y: radius),
      ),
      RenderCubicTo(
        control1: DrawPoint(x: -control, y: radius),
        control2: DrawPoint(x: -radius, y: control),
        end: DrawPoint(x: -radius, y: 0),
      ),
      RenderCubicTo(
        control1: DrawPoint(x: -radius, y: -control),
        control2: DrawPoint(x: -control, y: -radius),
        end: DrawPoint(x: 0, y: -radius),
      ),
      RenderCubicTo(
        control1: DrawPoint(x: control, y: -radius),
        control2: DrawPoint(x: radius, y: -control),
        end: DrawPoint(x: radius, y: 0),
      ),
      const RenderClosePath(),
    ]);
  }
}
