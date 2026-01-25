import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../core/element_renderer.dart';
import 'text_data.dart';
import 'text_layout.dart';

class TextRenderer extends ElementTypeRenderer {
  const TextRenderer();

  static const double _lineFillAngle = -math.pi / 4;
  static const double _crossLineFillAngle = math.pi / 4;
  static final _lineShaderCache = _LruCache<_LineShaderKey, Shader>(
    maxEntries: 128,
  );

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

  Paint _buildLineFillPaint({
    required double spacing,
    required double lineWidth,
    required double angle,
    required Color color,
  }) => Paint()
    ..style = PaintingStyle.fill
    ..shader = _lineShaderCache.getOrCreate(
      _LineShaderKey(spacing: spacing, lineWidth: lineWidth, angle: angle),
      () => _buildLineShader(
        spacing: spacing,
        lineWidth: lineWidth,
        angle: angle,
      ),
    )
    ..colorFilter = ColorFilter.mode(color, BlendMode.modulate)
    ..isAntiAlias = true;

  @override
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  }) {
    final data = element.data;
    if (data is! TextData) {
      throw StateError(
        'TextRenderer can only render TextData (got ${data.runtimeType})',
      );
    }
    final _ = scaleFactor;

    final rect = element.rect;
    final rotation = element.rotation;
    final opacity = element.opacity;
    final textOpacity = (data.color.a * opacity).clamp(0.0, 1.0);
    final strokeOpacity = (data.strokeColor.a * opacity).clamp(0.0, 1.0);
    final backgroundOpacity = (data.fillColor.a * opacity).clamp(0.0, 1.0);
    final shouldDrawBackground = backgroundOpacity > 0;

    final shouldDrawStroke = data.strokeWidth > 0 && strokeOpacity > 0;
    final shouldDrawFill = textOpacity > 0;
    if (!shouldDrawBackground && !shouldDrawStroke && !shouldDrawFill) {
      return;
    }

    final layoutWidth = rect.width;
    final layout = layoutText(
      data: data,
      maxWidth: layoutWidth,
      minWidth: layoutWidth,
      colorOverride: data.color.withValues(alpha: textOpacity),
      widthBasis: TextWidthBasis.parent,
      locale: locale,
    );
    final backgroundHorizontalPadding = shouldDrawBackground
        ? resolveTextBackgroundHorizontalPadding(layout.lineHeight)
        : 0.0;
    final backgroundVerticalPadding = shouldDrawBackground
        ? resolveTextBackgroundVerticalPadding(layout.lineHeight)
        : 0.0;
    final textOffset = _resolveTextOffset(
      containerSize: Size(rect.width, rect.height),
      textSize: layout.size,
      verticalAlign: data.verticalAlign,
    );
    final paintOffset = textOffset;
    final backgroundColor = data.fillColor.withValues(alpha: backgroundOpacity);
    Paint? backgroundPaint;
    Paint? crossLinePaint;
    if (shouldDrawBackground) {
      if (data.fillStyle == FillStyle.solid) {
        backgroundPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = backgroundColor
          ..isAntiAlias = true;
      } else {
        // Calculate line fill spacing based on font size
        // Conversion ratio: fontSize / rectangleStrokeWidth = 10
        final equivalentStrokeWidth = data.fontSize / 42;
        final fillLineWidth = (1 + (equivalentStrokeWidth - 1) * 0.6).clamp(
          0.5,
          3.0,
        );
        const lineToSpacingRatio = 6.0;
        final spacing = (fillLineWidth * lineToSpacingRatio).clamp(3.0, 18.0);
        backgroundPaint = _buildLineFillPaint(
          spacing: spacing,
          lineWidth: fillLineWidth,
          angle: _lineFillAngle,
          color: backgroundColor,
        );
        if (data.fillStyle == FillStyle.crossLine) {
          crossLinePaint = _buildLineFillPaint(
            spacing: spacing,
            lineWidth: fillLineWidth,
            angle: _crossLineFillAngle,
            color: backgroundColor,
          );
        }
      }
    }

    canvas.save();
    if (rotation != 0) {
      canvas
        ..translate(rect.centerX, rect.centerY)
        ..rotate(rotation)
        ..translate(-rect.centerX, -rect.centerY);
    }

    canvas.translate(rect.minX, rect.minY);
    if (shouldDrawBackground && backgroundPaint != null) {
      _paintTextBackground(
        canvas: canvas,
        painter: layout.painter,
        paintOffset: paintOffset,
        horizontalPadding: backgroundHorizontalPadding,
        verticalPadding: backgroundVerticalPadding,
        paint: backgroundPaint,
        cornerRadius: data.cornerRadius,
      );
      if (crossLinePaint != null) {
        _paintTextBackground(
          canvas: canvas,
          painter: layout.painter,
          paintOffset: paintOffset,
          horizontalPadding: backgroundHorizontalPadding,
          verticalPadding: backgroundVerticalPadding,
          paint: crossLinePaint,
          cornerRadius: data.cornerRadius,
        );
      }
    }

    if (shouldDrawStroke) {
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = data.strokeWidth
        ..color = data.strokeColor.withValues(alpha: strokeOpacity)
        ..isAntiAlias = true;
      final strokeStyle = buildTextStyle(
        data: data,
        locale: locale,
      ).copyWith(foreground: strokePaint);
      final strokeLayout = layoutText(
        data: data,
        maxWidth: layoutWidth,
        minWidth: layoutWidth,
        widthBasis: TextWidthBasis.parent,
        styleOverride: strokeStyle,
        locale: locale,
      );
      strokeLayout.painter.paint(canvas, paintOffset);
    }

    if (shouldDrawFill) {
      layout.painter.paint(canvas, paintOffset);
    }

    canvas.restore();
  }

  Offset _resolveTextOffset({
    required Size containerSize,
    required Size textSize,
    required TextVerticalAlign verticalAlign,
  }) {
    var dy = 0.0;

    switch (verticalAlign) {
      case TextVerticalAlign.top:
        dy = 0;
      case TextVerticalAlign.center:
        dy = (containerSize.height - textSize.height) / 2;
      case TextVerticalAlign.bottom:
        dy = containerSize.height - textSize.height;
    }

    if (dy.isNaN || dy.isInfinite || dy < 0) {
      dy = 0;
    }

    return Offset(0, dy);
  }

  void _paintTextBackground({
    required Canvas canvas,
    required TextPainter painter,
    required Offset paintOffset,
    required double horizontalPadding,
    required double verticalPadding,
    required Paint paint,
    required double cornerRadius,
  }) {
    final text = painter.text?.toPlainText() ?? '';
    if (text.isEmpty) {
      return;
    }
    final selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    final boxes = painter.getBoxesForSelection(
      selection,
      boxHeightStyle: BoxHeightStyle.strut,
    );
    if (boxes.isEmpty) {
      return;
    }
    for (final box in boxes) {
      final rect = Rect.fromLTRB(
        box.left - horizontalPadding,
        box.top - verticalPadding,
        box.right + horizontalPadding,
        box.bottom + verticalPadding,
      ).shift(paintOffset);
      if (rect.isEmpty) {
        continue;
      }
      final radius = _clampCornerRadius(cornerRadius, rect);
      if (radius <= 0) {
        canvas.drawRect(rect, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(radius)),
          paint,
        );
      }
    }
  }

  double _clampCornerRadius(double cornerRadius, Rect rect) {
    if (cornerRadius <= 0) {
      return 0;
    }
    final maxRadius = rect.shortestSide / 2;
    if (cornerRadius > maxRadius) {
      return maxRadius;
    }
    return cornerRadius;
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
class _LineShaderKey {
  _LineShaderKey({
    required double spacing,
    required double lineWidth,
    required this.angle,
  }) : spacing = _quantize(spacing),
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
