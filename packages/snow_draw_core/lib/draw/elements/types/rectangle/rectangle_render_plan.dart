import 'dart:ui';

import 'package:meta/meta.dart';

import '../../../types/element_style.dart';
import 'rectangle_data.dart';

/// Rendering backends for rectangle drawing.
///
/// - [solidFastPath]: Built-in Canvas primitives for simple solid styles.
/// - [shaderPattern]: Fragment shader path for patterned fill/stroke.
/// - [cpuPattern]: CPU fallback for patterned styles when shaders are
///   unavailable.
enum RectangleRenderBackend { solidFastPath, shaderPattern, cpuPattern }

/// Precomputed rectangle rendering plan.
///
/// Consolidates style visibility, opacity, and backend selection so the
/// renderer avoids recomputing the same decisions on every frame.
@immutable
class RectangleRenderPlan {
  const RectangleRenderPlan._({
    required this.backend,
    required this.paintFill,
    required this.paintStroke,
    required this.fillColor,
    required this.strokeColor,
  });

  /// Resolves the optimal rendering plan for the provided style and opacity.
  factory RectangleRenderPlan.resolve({
    required RectangleData data,
    required double elementOpacity,
    required bool shaderReady,
  }) {
    final opacity = _clampOpacity(elementOpacity);
    final fillOpacity = _clampOpacity(data.fillColor.a * opacity);
    final strokeOpacity = _clampOpacity(data.color.a * opacity);
    final paintFill = fillOpacity > 0;
    final paintStroke = strokeOpacity > 0 && data.strokeWidth > 0;

    final needsPatternRendering =
        (paintFill && data.fillStyle != FillStyle.solid) ||
        (paintStroke && data.strokeStyle != StrokeStyle.solid);
    final RectangleRenderBackend backend;
    if (!needsPatternRendering) {
      backend = RectangleRenderBackend.solidFastPath;
    } else if (shaderReady) {
      backend = RectangleRenderBackend.shaderPattern;
    } else {
      backend = RectangleRenderBackend.cpuPattern;
    }

    return RectangleRenderPlan._(
      backend: backend,
      paintFill: paintFill,
      paintStroke: paintStroke,
      fillColor: data.fillColor.withValues(alpha: fillOpacity),
      strokeColor: data.color.withValues(alpha: strokeOpacity),
    );
  }

  final RectangleRenderBackend backend;
  final bool paintFill;
  final bool paintStroke;
  final Color fillColor;
  final Color strokeColor;

  static double _clampOpacity(double value) => value.clamp(0.0, 1.0);

  bool get shouldUseShader => backend == RectangleRenderBackend.shaderPattern;
  bool get shouldUseSolidFastPath =>
      backend == RectangleRenderBackend.solidFastPath;
}
