import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart'
    show Alignment, GradientRotation, LinearGradient;

import '../../../../ui/canvas/rectangle_shader_manager.dart';
import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../core/element_renderer.dart';
import 'rectangle_data.dart';

class RectangleRenderer extends ElementTypeRenderer {
  const RectangleRenderer();

  // Cache expensive stroke/fill paths by size/style to avoid per-frame
  // rebuilds. Only used for CPU fallback rendering.
  static final _strokePathCache = _LruCache<_StrokePathKey, Path>(
    maxEntries: 200,
  );
  static final _lineShaderCache = _LruCache<_LineShaderKey, Shader>(
    maxEntries: 128,
  );

  @override
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  }) {
    final data = element.data;
    if (data is! RectangleData) {
      throw StateError(
        'RectangleRenderer can only render RectangleData (got '
        '${data.runtimeType})',
      );
    }

    // Try GPU shader rendering first (highest performance)
    if (_renderWithShader(canvas, element, data, scaleFactor)) {
      return;
    }

    // Fallback to CPU rendering
    _renderFallback(canvas, element, data, scaleFactor);
  }

  /// Renders the rectangle using the GPU fragment shader.
  ///
  /// Returns true if shader was used, false if fallback is needed.
  bool _renderWithShader(
    Canvas canvas,
    ElementState element,
    RectangleData data,
    double scaleFactor,
  ) {
    final shaderManager = RectangleShaderManager.instance;
    if (!shaderManager.isReady) {
      return false;
    }

    final rect = element.rect;
    final rotation = element.rotation;
    final opacity = element.opacity;
    final fillOpacity = (data.fillColor.a * opacity).clamp(0.0, 1.0);
    final strokeOpacity = (data.color.a * opacity).clamp(0.0, 1.0);

    // Calculate fill pattern parameters (matching CPU fallback logic)
    final fillLineWidth = (1 + (data.strokeWidth - 1) * 0.6).clamp(0.5, 3.0);
    const lineToSpacingRatio = 6.0;
    final fillLineSpacing =
        (fillLineWidth * lineToSpacingRatio).clamp(3.0, 18.0);

    // Calculate stroke pattern parameters (matching CPU fallback logic)
    final dashLength = (8 + data.strokeWidth * 1.5).clamp(6.0, 16.0);
    final gapLength = (5 + data.strokeWidth * 1).clamp(4.0, 10.0);
    final dotSpacing = math.max(4, data.strokeWidth * 2.5).toDouble();
    final dotRadius = math.max(1, data.strokeWidth / 2).toDouble();

    // Scale-aware anti-aliasing width
    final aaWidth = 1.5 / (scaleFactor == 0 ? 1.0 : scaleFactor);

    return shaderManager.paintRectangle(
      canvas: canvas,
      center: Offset(rect.centerX, rect.centerY),
      size: Size(rect.width, rect.height),
      rotation: rotation,
      cornerRadius: data.cornerRadius,
      fillStyle: data.fillStyle,
      fillColor: data.fillColor.withValues(alpha: fillOpacity),
      fillLineWidth: fillLineWidth,
      fillLineSpacing: fillLineSpacing,
      strokeStyle: data.strokeStyle,
      strokeColor: data.color.withValues(alpha: strokeOpacity),
      strokeWidth: data.strokeWidth,
      dashLength: dashLength,
      gapLength: gapLength,
      dotSpacing: dotSpacing,
      dotRadius: dotRadius,
      aaWidth: aaWidth,
    );
  }

  /// CPU fallback rendering for platforms without shader support.
  void _renderFallback(
    Canvas canvas,
    ElementState element,
    RectangleData data,
    double scaleFactor,
  ) {
    final _ = scaleFactor;

    final rect = element.rect;
    final rotation = element.rotation;
    final opacity = element.opacity;
    final fillOpacity = (data.fillColor.a * opacity).clamp(0.0, 1.0);
    final strokeOpacity = (data.color.a * opacity).clamp(0.0, 1.0);

    canvas.save();

    final size = Size(rect.width, rect.height);
    final rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, rect.width, rect.height),
      Radius.circular(data.cornerRadius),
    );

    if (rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }

    canvas.translate(rect.minX, rect.minY);

    if (fillOpacity > 0) {
      if (data.fillStyle == FillStyle.solid) {
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = data.fillColor.withValues(alpha: fillOpacity)
          ..isAntiAlias = true;
        canvas.drawRRect(rRect, paint);
      } else {
        final fillLineWidth =
            (1 + (data.strokeWidth - 1) * 0.6).clamp(0.5, 3.0);
        const lineToSpacingRatio = 6.0;
        final spacing = (fillLineWidth * lineToSpacingRatio).clamp(3.0, 18.0);
        const lineAngle = -math.pi / 4;
        const crossLineAngle = math.pi / 4;
        final fillPaint = Paint()
          ..style = PaintingStyle.fill
          ..shader = _lineShaderCache.getOrCreate(
            _LineShaderKey(
              spacing: spacing,
              lineWidth: fillLineWidth,
              angle: lineAngle,
            ),
            () => _buildLineShader(
              spacing: spacing,
              lineWidth: fillLineWidth,
              angle: lineAngle,
            ),
          )
          ..colorFilter = ColorFilter.mode(
            data.fillColor.withValues(alpha: fillOpacity),
            BlendMode.modulate,
          )
          ..isAntiAlias = true;
        canvas.drawRRect(rRect, fillPaint);
        if (data.fillStyle == FillStyle.crossLine) {
          fillPaint.shader = _lineShaderCache.getOrCreate(
            _LineShaderKey(
              spacing: spacing,
              lineWidth: fillLineWidth,
              angle: crossLineAngle,
            ),
            () => _buildLineShader(
              spacing: spacing,
              lineWidth: fillLineWidth,
              angle: crossLineAngle,
            ),
          );
          canvas.drawRRect(rRect, fillPaint);
        }
      }
    }

    if (strokeOpacity > 0 && data.strokeWidth > 0) {
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = data.strokeWidth
        ..color = data.color.withValues(alpha: strokeOpacity)
        ..isAntiAlias = true;

      if (data.strokeStyle == StrokeStyle.solid) {
        canvas.drawRRect(rRect, strokePaint);
      } else {
        if (data.strokeStyle == StrokeStyle.dashed) {
          final dashLength = (8 + data.strokeWidth * 1.5).clamp(6.0, 16.0);
          final gapLength = (5 + data.strokeWidth * 1).clamp(4.0, 10.0);
          final key = _StrokePathKey(
            width: size.width,
            height: size.height,
            cornerRadius: data.cornerRadius,
            strokeStyle: StrokeStyle.dashed,
            patternPrimary: dashLength,
            patternSecondary: gapLength,
          );
          final dashedPath = _strokePathCache.getOrCreate(
            key,
            () => _buildDashedPath(
              Path()..addRRect(rRect),
              dashLength,
              gapLength,
            ),
          );
          canvas.drawPath(dashedPath, strokePaint);
        } else {
          final dotPaint = Paint()
            ..style = PaintingStyle.fill
            ..color = strokePaint.color
            ..isAntiAlias = true;
          final dotSpacing = math.max(4, data.strokeWidth * 2.5).toDouble();
          final dotRadius = math.max(1, data.strokeWidth / 2).toDouble();
          final key = _StrokePathKey(
            width: size.width,
            height: size.height,
            cornerRadius: data.cornerRadius,
            strokeStyle: StrokeStyle.dotted,
            patternPrimary: dotSpacing,
            patternSecondary: dotRadius,
          );
          final dottedPath = _strokePathCache.getOrCreate(
            key,
            () => _buildDottedPath(
              Path()..addRRect(rRect),
              dotSpacing,
              dotRadius,
            ),
          );
          canvas.drawPath(dottedPath, dotPaint);
        }
      }
    }

    canvas.restore();
  }

  Shader _buildLineShader({
    required double spacing,
    required double lineWidth,
    required double angle,
  }) {
    final safeSpacing = spacing <= 0 ? 1.0 : spacing;
    final lineStop = (lineWidth / safeSpacing).clamp(0.0, 1.0);
    // For rotated gradients, scale the shader rect to ensure seamless tiling.
    // The perpendicular spacing changes by cos(angle), so we compensate.
    final cosAngle = math.cos(angle).abs();
    final adjustedSpacing =
        cosAngle > 0.01 ? safeSpacing / cosAngle : safeSpacing;
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

  Path _buildDashedPath(Path basePath, double dashLength, double gapLength) {
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

  Path _buildDottedPath(Path basePath, double dotSpacing, double dotRadius) {
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
}

class _LruCache<K, V> {
  _LruCache({required this.maxEntries});

  final int maxEntries;
  final _cache = <K, V>{};

  V getOrCreate(K key, V Function() builder) {
    final existing = _cache.remove(key);
    if (existing != null) {
      _cache[key] = existing;
      return existing;
    }
    final path = builder();
    _cache[key] = path;
    if (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return path;
  }
}

@immutable
class _StrokePathKey {
  _StrokePathKey({
    required double width,
    required double height,
    required double cornerRadius,
    required this.strokeStyle,
    required double patternPrimary,
    required double patternSecondary,
  })  : width = _quantize(width),
        height = _quantize(height),
        cornerRadius = _quantize(cornerRadius),
        patternPrimary = _quantize(patternPrimary),
        patternSecondary = _quantize(patternSecondary);

  final double width;
  final double height;
  final double cornerRadius;
  final StrokeStyle strokeStyle;
  // Dash length/gap length for dashed, dot spacing/radius for dotted.
  final double patternPrimary;
  final double patternSecondary;

  /// Quantize to 1 decimal place to improve cache hit rate
  /// by reducing floating-point precision variations
  static double _quantize(double value) {
    return (value * 10).roundToDouble() / 10;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _StrokePathKey &&
          other.width == width &&
          other.height == height &&
          other.cornerRadius == cornerRadius &&
          other.strokeStyle == strokeStyle &&
          other.patternPrimary == patternPrimary &&
          other.patternSecondary == patternSecondary;

  @override
  int get hashCode => Object.hash(
        width,
        height,
        cornerRadius,
        strokeStyle,
        patternPrimary,
        patternSecondary,
      );
}

@immutable
class _LineShaderKey {
  _LineShaderKey({
    required double spacing,
    required double lineWidth,
    required this.angle,
  })  : spacing = _quantize(spacing),
        lineWidth = _quantize(lineWidth);

  final double spacing;
  final double lineWidth;
  final double angle;

  /// Quantize to 1 decimal place to improve cache hit rate
  /// by reducing floating-point precision variations
  static double _quantize(double value) {
    return (value * 10).roundToDouble() / 10;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LineShaderKey &&
          other.spacing == spacing &&
          other.lineWidth == lineWidth &&
          other.angle == angle;

  @override
  int get hashCode => Object.hash(spacing, lineWidth, angle);
}
