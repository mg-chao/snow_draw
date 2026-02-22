import 'dart:math' as math;

import '../../../render/scene/render_scene.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';

/// Default hatch angle shared by built-in scene encoders.
const double defaultHatchAngleRadians = -math.pi / 4;

/// Returns the alpha channel for packed ARGB32 color values.
int alphaChannelOfArgb(int argb) => (argb >>> 24) & 0xFF;

/// Applies [elementOpacity] to a packed ARGB32 color.
int applyElementOpacityToArgb({
  required int argb,
  required double elementOpacity,
}) {
  final baseAlpha = alphaChannelOfArgb(argb);
  final scaledAlpha = (baseAlpha * elementOpacity.clamp(0.0, 1.0))
      .round()
      .clamp(0, 255);
  return (scaledAlpha << 24) | (argb & 0x00FFFFFF);
}

/// Returns whether a packed ARGB32 color has non-zero opacity.
bool isArgbVisible(int argb) => alphaChannelOfArgb(argb) > 0;

/// Resolves stroke dash pattern for [strokeStyle].
List<double>? resolveStrokeDashPattern({
  required StrokeStyle strokeStyle,
  required double strokeWidth,
}) => switch (strokeStyle) {
  StrokeStyle.solid => null,
  StrokeStyle.dashed => <double>[strokeWidth * 2.0, strokeWidth * 2.0 * 1.2],
  StrokeStyle.dotted => <double>[
    math.max(0.01, strokeWidth * 0.01),
    math.max(strokeWidth * 2.0, strokeWidth * 0.01),
  ],
};

/// Resolves stroke cap for [strokeStyle].
RenderStrokeCap resolveStrokeCap(StrokeStyle strokeStyle) =>
    strokeStyle == StrokeStyle.solid
    ? RenderStrokeCap.butt
    : RenderStrokeCap.round;

/// Resolves local clip bounds centered at origin for [rect].
DrawRect resolveCenteredLocalClipBounds(DrawRect rect) => DrawRect(
  minX: -rect.width / 2,
  minY: -rect.height / 2,
  maxX: rect.width / 2,
  maxY: rect.height / 2,
);

/// Resolves hatch line style from [strokeWidth].
({double lineWidth, double spacing}) resolveStrokeHatchStyle({
  required double strokeWidth,
  double lineToSpacingRatio = 4.0,
}) {
  final lineWidth = (1 + (strokeWidth - 1) * 0.6).clamp(0.5, 3.0);
  final spacing = (lineWidth * lineToSpacingRatio).clamp(3.0, 18.0);
  return (lineWidth: lineWidth, spacing: spacing);
}

/// Resolves hatch line style from [fontSize].
({double lineWidth, double spacing}) resolveFontHatchStyle({
  required double fontSize,
  double lineToSpacingRatio = 4.0,
}) {
  final equivalentStrokeWidth = fontSize / 42;
  return resolveStrokeHatchStyle(
    strokeWidth: equivalentStrokeWidth,
    lineToSpacingRatio: lineToSpacingRatio,
  );
}

/// Resolves render hatch pattern for [fillStyle].
RenderHatchPattern resolveHatchPattern(FillStyle fillStyle) =>
    fillStyle == FillStyle.crossLine
    ? RenderHatchPattern.crossLine
    : RenderHatchPattern.line;
