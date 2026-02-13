import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart'
    show Alignment, GradientRotation, LinearGradient;
import 'package:meta/meta.dart';

import 'lru_cache.dart';

/// Shared cache for line-fill gradient shaders.
///
/// All renderers that draw hatched/cross-hatched fills share this
/// single cache, improving hit rates and reducing native `Shader`
/// allocations compared to per-renderer private caches.
final lineShaderCache = LruCache<LineShaderKey, Shader>(maxEntries: 128);

/// Builds a repeating-gradient [Shader] for hatched line fills.
Shader buildLineShader({
  required double spacing,
  required double lineWidth,
  required double angle,
}) {
  final safeSpacing = spacing <= 0 ? 1.0 : spacing;
  final lineStop = (lineWidth / safeSpacing).clamp(0.0, 1.0);
  final cosAngle = math.cos(angle).abs();
  final adjustedSpacing = cosAngle > 0.01
      ? safeSpacing / cosAngle
      : safeSpacing;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    tileMode: TileMode.repeated,
    colors: const [
      Color(0xFFFFFFFF),
      Color(0xFFFFFFFF),
      Color(0x00FFFFFF),
      Color(0x00FFFFFF),
    ],
    stops: [0.0, lineStop, lineStop, 1.0],
    transform: GradientRotation(angle),
  ).createShader(Rect.fromLTWH(0, 0, adjustedSpacing, adjustedSpacing));
}

/// Builds a [Paint] for hatched line fills using the shared cache.
Paint buildLineFillPaint({
  required double spacing,
  required double lineWidth,
  required double angle,
  required Color color,
}) => Paint()
  ..style = PaintingStyle.fill
  ..shader = lineShaderCache.getOrCreate(
    LineShaderKey(spacing: spacing, lineWidth: lineWidth, angle: angle),
    () => buildLineShader(spacing: spacing, lineWidth: lineWidth, angle: angle),
  )
  ..colorFilter = ColorFilter.mode(color, BlendMode.modulate)
  ..isAntiAlias = true;

/// Builds a dashed version of [basePath].
Path buildDashedPath(Path basePath, double dashLength, double gapLength) {
  final dashed = Path();
  for (final metric in basePath.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + dashLength, metric.length);
      dashed.addPath(metric.extractPath(distance, next), Offset.zero);
      distance = next + gapLength;
    }
  }
  return dashed;
}

/// Builds a dotted version of [basePath] using oval shapes.
///
/// For higher-performance dotted rendering, prefer pre-computing
/// dot positions as a `Float32List` and using
/// `Canvas.drawRawPoints` with `PointMode.points`.
Path buildDottedPath(Path basePath, double dotSpacing, double dotRadius) {
  final dotted = Path();
  for (final metric in basePath.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final tangent = metric.getTangentForOffset(distance);
      if (tangent != null) {
        dotted.addOval(
          Rect.fromCircle(center: tangent.position, radius: dotRadius),
        );
      }
      distance += dotSpacing;
    }
  }
  return dotted;
}

/// Builds a [Float32List] of dot center positions along [basePath].
///
/// Returns (x, y) pairs suitable for [Canvas.drawRawPoints], which
/// batches all dots into a single GPU draw call. This is faster
/// than building a [Path] of individual ovals because Impeller
/// does not need to tessellate each oval separately.
Float32List buildDotPositions(Path basePath, double dotSpacing) {
  final metrics = basePath.computeMetrics().toList(growable: false);

  // Count dots first to pre-allocate the Float32List.
  var dotCount = 0;
  for (final metric in metrics) {
    if (metric.length <= 0) {
      continue;
    }
    dotCount += (metric.length / dotSpacing).floor() + 1;
  }

  final positions = Float32List(dotCount * 2);
  var idx = 0;
  for (final metric in metrics) {
    var distance = 0.0;
    while (distance < metric.length) {
      final tangent = metric.getTangentForOffset(distance);
      if (tangent != null) {
        positions[idx++] = tangent.position.dx;
        positions[idx++] = tangent.position.dy;
      }
      distance += dotSpacing;
    }
  }

  // Trim if we over-estimated (e.g. getTangentForOffset returned null).
  if (idx < positions.length) {
    return Float32List.sublistView(positions, 0, idx);
  }
  return positions;
}

/// Clears the shared line shader cache.
///
/// Call when switching documents or under memory pressure.
void clearStrokePatternCaches() {
  lineShaderCache.clear();
}

/// Content-based key for the shared line shader cache.
@immutable
class LineShaderKey {
  /// Creates a key with quantized spacing, line width, and angle.
  LineShaderKey({
    required double spacing,
    required double lineWidth,
    required double angle,
  }) : spacing = _quantize(spacing),
       lineWidth = _quantize(lineWidth),
       angle = _quantize(angle);

  /// Quantized spacing value.
  final double spacing;

  /// Quantized line width value.
  final double lineWidth;

  /// Rotation angle in radians.
  final double angle;

  static double _quantize(double value) => (value * 10).roundToDouble() / 10;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineShaderKey &&
          other.spacing == spacing &&
          other.lineWidth == lineWidth &&
          other.angle == angle;

  @override
  int get hashCode => Object.hash(spacing, lineWidth, angle);
}
