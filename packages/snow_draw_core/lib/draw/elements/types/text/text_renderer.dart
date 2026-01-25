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
  static const _layoutWidthTolerance = 0.5;
  static const _layoutFallbackText = ' ';
  static final _lineShaderCache = _LruCache<_LineShaderKey, Shader>(
    maxEntries: 128,
  );
  static final _elementLayoutCache =
      _LruCache<String, _ElementTextLayoutCache>(maxEntries: 256);

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
    const widthBasis = TextWidthBasis.parent;
    _TextLayoutCacheEntry? fillEntry;
    _TextLayoutCacheEntry? strokeEntry;
    if (shouldDrawFill || shouldDrawBackground) {
      final fillStyle = buildTextStyle(
        data: data,
        colorOverride: data.color.withValues(alpha: textOpacity),
        locale: locale,
      );
      fillEntry = _resolveTextLayout(
        elementId: element.id,
        data: data,
        maxWidth: layoutWidth,
        minWidth: layoutWidth,
        widthBasis: widthBasis,
        locale: locale,
        style: fillStyle,
        includeBackground: shouldDrawBackground,
        variant: _TextLayoutVariant.fill,
      );
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
      strokeEntry = _resolveTextLayout(
        elementId: element.id,
        data: data,
        maxWidth: layoutWidth,
        minWidth: layoutWidth,
        widthBasis: widthBasis,
        locale: locale,
        style: strokeStyle,
        includeBackground: false,
        variant: _TextLayoutVariant.stroke,
      );
    }

    final layoutForOffset = fillEntry?.layout ?? strokeEntry?.layout;
    if (layoutForOffset == null) {
      return;
    }

    final backgroundHorizontalPadding = shouldDrawBackground
        ? resolveTextBackgroundHorizontalPadding(layoutForOffset.lineHeight)
        : 0.0;
    final backgroundVerticalPadding = shouldDrawBackground
        ? resolveTextBackgroundVerticalPadding(layoutForOffset.lineHeight)
        : 0.0;
    final textOffset = _resolveTextOffset(
      containerSize: Size(rect.width, rect.height),
      textSize: layoutForOffset.size,
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
        const lineToSpacingRatio = 4.0;
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
      final backgroundBoxes = fillEntry?.backgroundBoxes;
      _paintTextBackground(
        canvas: canvas,
        painter: fillEntry!.layout.painter,
        paintOffset: paintOffset,
        horizontalPadding: backgroundHorizontalPadding,
        verticalPadding: backgroundVerticalPadding,
        paint: backgroundPaint,
        cornerRadius: data.cornerRadius,
        boxes: backgroundBoxes,
      );
      if (crossLinePaint != null) {
        _paintTextBackground(
          canvas: canvas,
          painter: fillEntry.layout.painter,
          paintOffset: paintOffset,
          horizontalPadding: backgroundHorizontalPadding,
          verticalPadding: backgroundVerticalPadding,
          paint: crossLinePaint,
          cornerRadius: data.cornerRadius,
          boxes: backgroundBoxes,
        );
      }
    }

    if (shouldDrawStroke) {
      strokeEntry?.layout.painter.paint(canvas, paintOffset);
    }

    if (shouldDrawFill) {
      fillEntry?.layout.painter.paint(canvas, paintOffset);
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

  _TextLayoutCacheEntry _resolveTextLayout({
    required String elementId,
    required TextData data,
    required double maxWidth,
    required double minWidth,
    required TextWidthBasis widthBasis,
    required Locale? locale,
    required TextStyle style,
    required bool includeBackground,
    required _TextLayoutVariant variant,
  }) {
    final safeMaxWidth = maxWidth <= 0 ? 1.0 : maxWidth;
    final safeMinWidth = _resolveMinWidth(minWidth, safeMaxWidth);
    final cache = _elementLayoutCache.getOrCreate(
      elementId,
      _ElementTextLayoutCache.new,
    );
    final signature = _TextLayoutSignature(
      text: data.text.isEmpty ? _layoutFallbackText : data.text,
      fontSize: style.fontSize ?? data.fontSize,
      fontFamily: style.fontFamily,
      horizontalAlign: data.horizontalAlign,
      paintKey: _TextPaintSignature.fromStyle(style),
    );
    final cached = variant == _TextLayoutVariant.fill
        ? cache.fill
        : cache.stroke;
    if (cached != null &&
        cached.signature == signature &&
        cached.widthBasis == widthBasis &&
        cached.locale == locale &&
        _withinTolerance(cached.layoutWidth, safeMaxWidth) &&
        _withinTolerance(cached.minWidth, safeMinWidth)) {
      if (includeBackground && cached.backgroundBoxes == null) {
        cached.backgroundBoxes = _resolveTextBoxes(cached.layout.painter);
      }
      return cached;
    }

    final layout = layoutText(
      data: data,
      maxWidth: maxWidth,
      minWidth: minWidth,
      widthBasis: widthBasis,
      styleOverride: style,
      locale: locale,
    );
    final entry = _TextLayoutCacheEntry(
      signature: signature,
      layoutWidth: safeMaxWidth,
      minWidth: safeMinWidth,
      widthBasis: widthBasis,
      locale: locale,
      layout: layout,
      backgroundBoxes: includeBackground
          ? _resolveTextBoxes(layout.painter)
          : null,
    );
    if (variant == _TextLayoutVariant.fill) {
      cache.fill = entry;
    } else {
      cache.stroke = entry;
    }
    return entry;
  }

  List<TextBox> _resolveTextBoxes(TextPainter painter) {
    final text = painter.text?.toPlainText() ?? '';
    if (text.isEmpty) {
      return const [];
    }
    final selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    return painter.getBoxesForSelection(
      selection,
      boxHeightStyle: BoxHeightStyle.strut,
    );
  }

  bool _withinTolerance(double a, double b) {
    if (!a.isFinite || !b.isFinite) {
      return false;
    }
    return (a - b).abs() <= _layoutWidthTolerance;
  }

  double _resolveMinWidth(double minWidth, double maxWidth) {
    if (minWidth <= 0 || minWidth.isNaN || minWidth.isInfinite) {
      return 0;
    }
    if (minWidth > maxWidth) {
      return maxWidth;
    }
    return minWidth;
  }

  void _paintTextBackground({
    required Canvas canvas,
    required TextPainter painter,
    required Offset paintOffset,
    required double horizontalPadding,
    required double verticalPadding,
    required Paint paint,
    required double cornerRadius,
    List<TextBox>? boxes,
  }) {
    final resolvedBoxes = boxes ?? _resolveTextBoxes(painter);
    if (resolvedBoxes.isEmpty) {
      return;
    }
    for (final box in resolvedBoxes) {
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

enum _TextLayoutVariant { fill, stroke }

class _ElementTextLayoutCache {
  _TextLayoutCacheEntry? fill;
  _TextLayoutCacheEntry? stroke;
}

class _TextLayoutCacheEntry {
  _TextLayoutCacheEntry({
    required this.signature,
    required this.layoutWidth,
    required this.minWidth,
    required this.widthBasis,
    required this.locale,
    required this.layout,
    this.backgroundBoxes,
  });

  final _TextLayoutSignature signature;
  final double layoutWidth;
  final double minWidth;
  final TextWidthBasis widthBasis;
  final Locale? locale;
  final TextLayoutMetrics layout;
  List<TextBox>? backgroundBoxes;
}

@immutable
class _TextLayoutSignature {
  const _TextLayoutSignature({
    required this.text,
    required this.fontSize,
    required this.fontFamily,
    required this.horizontalAlign,
    required this.paintKey,
  });

  final String text;
  final double fontSize;
  final String? fontFamily;
  final TextHorizontalAlign horizontalAlign;
  final _TextPaintSignature paintKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TextLayoutSignature &&
          other.text == text &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.horizontalAlign == horizontalAlign &&
          other.paintKey == paintKey;

  @override
  int get hashCode => Object.hash(
        text,
        fontSize,
        fontFamily,
        horizontalAlign,
        paintKey,
      );
}

@immutable
class _TextPaintSignature {
  const _TextPaintSignature({
    required this.color,
    required this.paintStyle,
    required this.strokeWidth,
    required this.strokeCap,
    required this.strokeJoin,
    required this.strokeMiterLimit,
    required this.isAntiAlias,
    required this.blendMode,
    required this.shaderId,
  });

  factory _TextPaintSignature.fromStyle(TextStyle style) {
    final foreground = style.foreground;
    if (foreground == null) {
      return _TextPaintSignature(
        color: style.color,
        paintStyle: null,
        strokeWidth: null,
        strokeCap: null,
        strokeJoin: null,
        strokeMiterLimit: null,
        isAntiAlias: null,
        blendMode: null,
        shaderId: null,
      );
    }
    return _TextPaintSignature(
      color: foreground.color,
      paintStyle: foreground.style,
      strokeWidth: _quantize(foreground.strokeWidth),
      strokeCap: foreground.strokeCap,
      strokeJoin: foreground.strokeJoin,
      strokeMiterLimit: _quantize(foreground.strokeMiterLimit),
      isAntiAlias: foreground.isAntiAlias,
      blendMode: foreground.blendMode,
      shaderId: foreground.shader == null
          ? null
          : identityHashCode(foreground.shader),
    );
  }

  final Color? color;
  final PaintingStyle? paintStyle;
  final double? strokeWidth;
  final StrokeCap? strokeCap;
  final StrokeJoin? strokeJoin;
  final double? strokeMiterLimit;
  final bool? isAntiAlias;
  final BlendMode? blendMode;
  final int? shaderId;

  static double _quantize(double value) => (value * 10).roundToDouble() / 10;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TextPaintSignature &&
          other.color == color &&
          other.paintStyle == paintStyle &&
          other.strokeWidth == strokeWidth &&
          other.strokeCap == strokeCap &&
          other.strokeJoin == strokeJoin &&
          other.strokeMiterLimit == strokeMiterLimit &&
          other.isAntiAlias == isAntiAlias &&
          other.blendMode == blendMode &&
          other.shaderId == shaderId;

  @override
  int get hashCode => Object.hash(
        color,
        paintStyle,
        strokeWidth,
        strokeCap,
        strokeJoin,
        strokeMiterLimit,
        isAntiAlias,
        blendMode,
        shaderId,
      );
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
  static double _quantize(double value) => (value * 10).roundToDouble() / 10;

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
