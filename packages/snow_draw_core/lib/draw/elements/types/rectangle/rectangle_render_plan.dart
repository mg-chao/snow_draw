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
    final resolvedOpacity = _clampOpacity(elementOpacity);
    final fillOpacity = _clampOpacity(data.fillColor.a * resolvedOpacity);
    final strokeOpacity = _clampOpacity(data.color.a * resolvedOpacity);
    final paintFill = fillOpacity > 0;
    final paintStroke = strokeOpacity > 0 && data.strokeWidth > 0;

    final hasPatternFill = paintFill && data.fillStyle != FillStyle.solid;
    final hasPatternStroke =
        paintStroke && data.strokeStyle != StrokeStyle.solid;
    final needsPatternRendering = hasPatternFill || hasPatternStroke;

    final backend = switch ((needsPatternRendering, shaderReady)) {
      (true, true) => RectangleRenderBackend.shaderPattern,
      (true, false) => RectangleRenderBackend.cpuPattern,
      (false, _) => RectangleRenderBackend.solidFastPath,
    };

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
