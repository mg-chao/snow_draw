import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/element_scene_encoder.dart';
import 'highlight_data.dart';

/// Encodes highlight elements into backend-agnostic scene primitives.
final class HighlightSceneEncoder
    implements ElementSceneEncoder<HighlightData> {
  /// Creates a highlight scene encoder.
  const HighlightSceneEncoder();

  static const _kappa = 0.5522847498307936;

  @override
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
  }) {
    assert(scaleFactor.isFinite, 'scaleFactor must be finite.');
    assert(
      localeTag == null || localeTag.isNotEmpty,
      'localeTag must be null or non-empty.',
    );

    final data = element.data;
    if (data is! HighlightData) {
      throw StateError(
        'HighlightSceneEncoder can only encode HighlightData (got '
        '${data.runtimeType})',
      );
    }

    final fillColorArgb = _applyElementOpacity(
      argb: data.color.toARGB32(),
      elementOpacity: element.opacity,
    );
    final strokeColorArgb = _applyElementOpacity(
      argb: data.strokeColor.toARGB32(),
      elementOpacity: element.opacity,
    );
    final shouldFill = _alphaOf(fillColorArgb) > 0;
    final shouldStroke = _alphaOf(strokeColorArgb) > 0 && data.strokeWidth > 0;
    if (!shouldFill && !shouldStroke) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
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

    final builder = SceneBuilder()
      ..addTransform(
        child: localScene.build(),
        translate: element.center,
        rotation: element.rotation,
      );
    return builder.build(cullRect: element.rect);
  }

  static int _alphaOf(int argb) => (argb >>> 24) & 0xFF;

  static int _applyElementOpacity({
    required int argb,
    required double elementOpacity,
  }) {
    final baseAlpha = (argb >>> 24) & 0xFF;
    final scaledAlpha = (baseAlpha * elementOpacity.clamp(0.0, 1.0))
        .round()
        .clamp(0, 255);
    return (scaledAlpha << 24) | (argb & 0x00FFFFFF);
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
