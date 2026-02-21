import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

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
  _requirePositive(spacing, name: 'spacing');
  _requireNonNegative(lineWidth, name: 'lineWidth');

  final lineStop = (lineWidth / spacing).clamp(0.0, 1.0);
  final cosAngle = math.cos(angle).abs();
  final adjustedSpacing = cosAngle > 0.01 ? spacing / cosAngle : spacing;
  final tileSize = adjustedSpacing;
  final center = Offset(tileSize / 2, tileSize / 2);
  final dx = -math.sin(angle) * tileSize;
  final dy = math.cos(angle) * tileSize;
  final start = Offset(center.dx - dx / 2, center.dy - dy / 2);
  final end = Offset(center.dx + dx / 2, center.dy + dy / 2);
  return Gradient.linear(
    start,
    end,
    const [
      Color(0xFFFFFFFF),
      Color(0xFFFFFFFF),
      Color(0x00FFFFFF),
      Color(0x00FFFFFF),
    ],
    [0.0, lineStop, lineStop, 1.0],
    TileMode.repeated,
  );
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
  _requirePositive(dashLength, name: 'dashLength');
  _requireNonNegative(gapLength, name: 'gapLength');

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
  _requirePositive(dotSpacing, name: 'dotSpacing');
  _requireNonNegative(dotRadius, name: 'dotRadius');

  final dotted = Path();
  for (final metric in basePath.computeMetrics()) {
    final dotCount = (metric.length / dotSpacing).ceil();
    for (var i = 0; i < dotCount; i++) {
      final tangent = metric.getTangentForOffset(i * dotSpacing)!;
      dotted.addOval(
        Rect.fromCircle(center: tangent.position, radius: dotRadius),
      );
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
  _requirePositive(dotSpacing, name: 'dotSpacing');

  final metrics = basePath.computeMetrics().toList(growable: false);
  var dotCount = 0;
  for (final metric in metrics) {
    dotCount += (metric.length / dotSpacing).ceil();
  }

  final positions = Float32List(dotCount * 2);
  var idx = 0;
  for (final metric in metrics) {
    final metricDotCount = (metric.length / dotSpacing).ceil();
    for (var i = 0; i < metricDotCount; i++) {
      final tangent = metric.getTangentForOffset(i * dotSpacing)!;
      positions[idx++] = tangent.position.dx;
      positions[idx++] = tangent.position.dy;
    }
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

void _requirePositive(double value, {required String name}) {
  if (value <= 0 || !value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite and > 0');
  }
}

void _requireNonNegative(double value, {required String name}) {
  if (value < 0 || !value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite and >= 0');
  }
}
