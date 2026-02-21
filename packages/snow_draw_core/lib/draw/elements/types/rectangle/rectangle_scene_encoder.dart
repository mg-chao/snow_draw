import 'dart:math' as math;

import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/element_scene_encoder.dart';
import 'rectangle_data.dart';

/// Encodes rectangle elements into backend-agnostic scene primitives.
final class RectangleSceneEncoder
    implements ElementSceneEncoder<RectangleData> {
  /// Creates a rectangle scene encoder.
  const RectangleSceneEncoder();

  static const _kappa = 0.5522847498307936;
  static const double _lineFillAngle = -math.pi / 4;
  static const _lineToSpacingRatio = 4.0;

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
    if (data is! RectangleData) {
      throw StateError(
        'RectangleSceneEncoder can only encode RectangleData (got '
        '${data.runtimeType})',
      );
    }

    final fillColorArgb = _applyElementOpacity(
      argb: data.fillColor.toARGB32(),
      elementOpacity: element.opacity,
    );
    final strokeColorArgb = _applyElementOpacity(
      argb: data.color.toARGB32(),
      elementOpacity: element.opacity,
    );
    final fillVisible = _alphaOf(fillColorArgb) > 0;
    final strokeVisible = _alphaOf(strokeColorArgb) > 0 && data.strokeWidth > 0;
    if (!fillVisible && !strokeVisible) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }

    final path = _buildRoundedRectPath(element.rect, data.cornerRadius);
    final localBuilder = SceneBuilder();
    if (fillVisible) {
      if (data.fillStyle == FillStyle.solid) {
        localBuilder.addPathFill(path: path, colorArgb: fillColorArgb);
      } else {
        final hatch = _resolveHatchStyle(strokeWidth: data.strokeWidth);
        localBuilder.addHatchPathFill(
          path: path,
          clipBounds: _localClipBounds(element.rect),
          colorArgb: fillColorArgb,
          lineWidth: hatch.lineWidth,
          spacing: hatch.spacing,
          angleRadians: _lineFillAngle,
          pattern: data.fillStyle == FillStyle.crossLine
              ? RenderHatchPattern.crossLine
              : RenderHatchPattern.line,
        );
      }
    }
    if (strokeVisible) {
      localBuilder.addPathStroke(
        path: path,
        colorArgb: strokeColorArgb,
        strokeWidth: data.strokeWidth,
        strokeCap: _strokeCapFor(data.strokeStyle),
        dashPattern: _dashPatternFor(
          strokeStyle: data.strokeStyle,
          strokeWidth: data.strokeWidth,
        ),
      );
    }

    final sceneBuilder = SceneBuilder()
      ..addTransform(
        child: localBuilder.build(),
        translate: element.center,
        rotation: element.rotation,
      );
    return sceneBuilder.build(cullRect: element.rect);
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

  static List<double>? _dashPatternFor({
    required StrokeStyle strokeStyle,
    required double strokeWidth,
  }) => switch (strokeStyle) {
    StrokeStyle.solid => null,
    StrokeStyle.dashed => <double>[strokeWidth * 2.0, strokeWidth * 2.0 * 1.2],
    StrokeStyle.dotted => <double>[
      (strokeWidth * 0.01).clamp(0.01, double.infinity),
      (strokeWidth * 2.0).clamp(0.01, double.infinity),
    ],
  };

  static RenderStrokeCap _strokeCapFor(StrokeStyle strokeStyle) =>
      strokeStyle == StrokeStyle.solid
      ? RenderStrokeCap.butt
      : RenderStrokeCap.round;

  static DrawRect _localClipBounds(DrawRect rect) => DrawRect(
    minX: -rect.width / 2,
    minY: -rect.height / 2,
    maxX: rect.width / 2,
    maxY: rect.height / 2,
  );

  static ({double lineWidth, double spacing}) _resolveHatchStyle({
    required double strokeWidth,
  }) {
    final lineWidth = (1 + (strokeWidth - 1) * 0.6).clamp(0.5, 3.0);
    final spacing = (lineWidth * _lineToSpacingRatio).clamp(3.0, 18.0);
    return (lineWidth: lineWidth, spacing: spacing);
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
