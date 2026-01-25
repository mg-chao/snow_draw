import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

import '../../../types/element_style.dart';
import 'text_data.dart';

const _fallbackText = ' ';
const textLayoutHeightBehavior = TextHeightBehavior();
const TextScaler textLayoutTextScaler = TextScaler.noScaling;
const textCursorWidth = 1.2;
const textCaretGap = 1.0;
const double textCaretMargin = textCursorWidth + textCaretGap;
const _textLayoutHorizontalPaddingFactor = 0.01;
const _textBackgroundHorizontalPaddingFactor = 0.32;
const _textBackgroundVerticalPaddingFactor = 0.1;

// LRU cache for text layout metrics to avoid redundant layout calculations
final _textLayoutCache = _LruCache<_TextLayoutCacheKey, TextLayoutMetrics>(
  maxEntries: 256,
);

StrutStyle resolveTextStrutStyle(TextStyle style) =>
    StrutStyle.fromTextStyle(style, forceStrutHeight: true);

double resolveTextBackgroundHorizontalPadding(double lineHeight) {
  final padding = lineHeight * _textBackgroundHorizontalPaddingFactor;
  if (padding.isNaN || padding.isInfinite) {
    return 0;
  }
  return padding;
}

double resolveTextBackgroundVerticalPadding(double lineHeight) {
  final padding = lineHeight * _textBackgroundVerticalPaddingFactor;
  if (padding.isNaN || padding.isInfinite) {
    return 0;
  }
  return padding;
}

double resolveTextLayoutHorizontalPadding(double lineHeight) {
  final padding = lineHeight * _textLayoutHorizontalPaddingFactor;
  if (padding.isNaN || padding.isInfinite) {
    return 0;
  }
  return padding;
}

TextStyle buildTextStyle({
  required TextData data,
  Color? colorOverride,
  double? fontSizeOverride,
  Locale? locale,
}) => TextStyle(
  inherit: false,
  color: colorOverride ?? data.color,
  fontSize: fontSizeOverride ?? data.fontSize,
  fontFamily: _sanitizeFontFamily(data.fontFamily),
  locale: locale,
  textBaseline: TextBaseline.alphabetic,
);

@immutable
class TextLayoutMetrics {
  const TextLayoutMetrics({
    required this.painter,
    required this.size,
    required this.lineHeight,
    required this.lineMetrics,
    required this.baseline,
    required this.ascent,
    required this.descent,
    required this.unscaledAscent,
    required this.leading,
  });

  final TextPainter painter;
  final Size size;
  final double lineHeight;
  final List<LineMetrics> lineMetrics;
  final double baseline;
  final double ascent;
  final double descent;
  final double unscaledAscent;
  final double leading;
}

TextLayoutMetrics layoutText({
  required TextData data,
  required double maxWidth,
  double? minWidth,
  Color? colorOverride,
  TextWidthBasis widthBasis = TextWidthBasis.longestLine,
  TextStyle? styleOverride,
  Locale? locale,
}) {
  final safeMaxWidth = maxWidth <= 0 ? 1.0 : maxWidth;
  final safeMinWidth = _resolveMinWidth(minWidth, safeMaxWidth);
  final resolvedText = data.text.isEmpty ? _fallbackText : data.text;
  final resolvedStyle =
      styleOverride ??
      buildTextStyle(
        data: data,
        colorOverride: colorOverride,
        locale: locale,
      );

  // Create cache key for this layout request
  final cacheKey = _TextLayoutCacheKey(
    text: resolvedText,
    fontSize: resolvedStyle.fontSize ?? data.fontSize,
    fontFamily: resolvedStyle.fontFamily ?? data.fontFamily,
    fontWeight: resolvedStyle.fontWeight,
    fontStyle: resolvedStyle.fontStyle,
    letterSpacing: resolvedStyle.letterSpacing,
    wordSpacing: resolvedStyle.wordSpacing,
    height: resolvedStyle.height,
    textBaseline:
        resolvedStyle.textBaseline ?? TextBaseline.alphabetic,
    horizontalAlign: data.horizontalAlign,
    maxWidth: safeMaxWidth,
    minWidth: safeMinWidth,
    widthBasis: widthBasis,
    paintKey: _TextPaintKey.fromStyle(resolvedStyle),
    locale: locale,
  );

  // Try to get from cache
  return _textLayoutCache.getOrCreate(cacheKey, () {
    // Cache miss - perform layout
    final strutStyle = resolveTextStrutStyle(resolvedStyle);
    final painter = TextPainter(
      text: TextSpan(
        text: resolvedText,
        style: resolvedStyle,
      ),
      textAlign: _toFlutterAlign(data.horizontalAlign),
      textDirection: TextDirection.ltr,
      textHeightBehavior: textLayoutHeightBehavior,
      textScaler: textLayoutTextScaler,
      textWidthBasis: widthBasis,
      strutStyle: strutStyle,
      locale: locale,
    )..layout(minWidth: safeMinWidth, maxWidth: safeMaxWidth);

    final lineMetrics = painter.computeLineMetrics();
    final primaryLine = lineMetrics.isNotEmpty ? lineMetrics.first : null;
    final baseline = primaryLine?.baseline ??
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final lineHeight = primaryLine?.height ?? painter.preferredLineHeight;
    final ascent = primaryLine?.ascent ?? baseline;
    final descent = primaryLine?.descent ?? _nonNegative(lineHeight - ascent);
    final unscaledAscent = primaryLine?.unscaledAscent ?? ascent;
    final leading = primaryLine == null
        ? _nonNegative(lineHeight - ascent - descent)
        : _nonNegative(
            primaryLine.height - primaryLine.ascent - primaryLine.descent,
          );

    return TextLayoutMetrics(
      painter: painter,
      size: painter.size,
      lineHeight: lineHeight,
      lineMetrics: lineMetrics,
      baseline: baseline,
      ascent: ascent,
      descent: descent,
      unscaledAscent: unscaledAscent,
      leading: leading,
    );
  });
}

TextAlign _toFlutterAlign(TextHorizontalAlign align) {
  switch (align) {
    case TextHorizontalAlign.left:
      return TextAlign.left;
    case TextHorizontalAlign.center:
      return TextAlign.center;
    case TextHorizontalAlign.right:
      return TextAlign.right;
  }
}

double _nonNegative(double value) => value < 0 ? 0 : value;

double _resolveMinWidth(double? minWidth, double maxWidth) {
  if (minWidth == null ||
      minWidth <= 0 ||
      minWidth.isNaN ||
      minWidth.isInfinite) {
    return 0;
  }
  if (minWidth > maxWidth) {
    return maxWidth;
  }
  return minWidth;
}

String? _sanitizeFontFamily(String? fontFamily) {
  final trimmed = fontFamily?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
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
    final value = builder();
    _cache[key] = value;
    if (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return value;
  }
}

@immutable
class _TextLayoutCacheKey {
  _TextLayoutCacheKey({
    required this.text,
    required this.fontSize,
    required this.fontFamily,
    required this.fontWeight,
    required this.fontStyle,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.height,
    required this.textBaseline,
    required this.horizontalAlign,
    required double maxWidth,
    required double minWidth,
    required this.widthBasis,
    required this.paintKey,
    required this.locale,
  })  : maxWidth = _quantize(maxWidth),
        minWidth = _quantize(minWidth);

  final String text;
  final double fontSize;
  final String? fontFamily;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final double? letterSpacing;
  final double? wordSpacing;
  final double? height;
  final TextBaseline textBaseline;
  final TextHorizontalAlign horizontalAlign;
  final double maxWidth;
  final double minWidth;
  final TextWidthBasis widthBasis;
  final _TextPaintKey paintKey;
  final Locale? locale;

  static double _quantize(double value) => (value * 10).roundToDouble() / 10;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TextLayoutCacheKey &&
          other.text == text &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.fontWeight == fontWeight &&
          other.fontStyle == fontStyle &&
          other.letterSpacing == letterSpacing &&
          other.wordSpacing == wordSpacing &&
          other.height == height &&
          other.textBaseline == textBaseline &&
          other.horizontalAlign == horizontalAlign &&
          other.maxWidth == maxWidth &&
          other.minWidth == minWidth &&
          other.widthBasis == widthBasis &&
          other.paintKey == paintKey &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
        text,
        fontSize,
        fontFamily,
        fontWeight,
        fontStyle,
        letterSpacing,
        wordSpacing,
        height,
        textBaseline,
        horizontalAlign,
        maxWidth,
        minWidth,
        widthBasis,
        paintKey,
        locale,
      );
}

@immutable
class _TextPaintKey {
  const _TextPaintKey({
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

  factory _TextPaintKey.fromStyle(TextStyle style) {
    final foreground = style.foreground;
    if (foreground == null) {
      return _TextPaintKey(
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
    return _TextPaintKey(
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
      other is _TextPaintKey &&
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
