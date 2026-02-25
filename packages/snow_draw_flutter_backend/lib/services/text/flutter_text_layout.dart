import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:snow_draw_core/snow_draw_engine.dart';

const _fallbackText = ' ';
const _fontMetricsProbeText = 'Mg';
const textLayoutHeightBehavior = TextHeightBehavior();
const TextScaler textLayoutTextScaler = TextScaler.noScaling;

/// Lightweight layout result using `dart:ui.Paragraph` directly.
///
/// Avoids the overhead of `TextPainter` for callers that only need
/// metrics (size, line height, baseline). The [paragraph] can still
/// be drawn with `canvas.drawParagraph` or queried for positions.
///
/// [lineMetrics] is computed lazily to keep the hot render/layout path cheap.
@immutable
class FlutterTextLayoutMetrics {
  FlutterTextLayoutMetrics({
    required this.paragraph,
    required this.size,
    required this.lineHeight,
    required List<ui.LineMetrics>? lineMetrics,
    required this.baseline,
    required this.ascent,
    required this.descent,
    required this.unscaledAscent,
    required this.leading,
  }) : _lineMetrics = lineMetrics;

  /// The laid-out paragraph. Use for painting via
  /// `canvas.drawParagraph` or querying glyph positions.
  final ui.Paragraph paragraph;
  final Size size;
  final double lineHeight;
  final List<ui.LineMetrics>? _lineMetrics;
  late final List<ui.LineMetrics> lineMetrics =
      _lineMetrics ?? paragraph.computeLineMetrics();
  final double baseline;
  final double ascent;
  final double descent;
  final double unscaledAscent;
  final double leading;

  /// Wraps this result in a [TextPainter]-backed
  /// [FlutterPainterTextLayoutMetrics].
  ///
  /// Only call this when you need `TextPainter` APIs such as
  /// `getPositionForOffset` or `getBoxesForSelection`. The painter
  /// is created lazily and cached.
  FlutterPainterTextLayoutMetrics toPainterMetrics({
    required TextData data,
    required double maxWidth,
    double? minWidth,
    TextWidthBasis widthBasis = TextWidthBasis.longestLine,
    TextStyle? styleOverride,
    Locale? locale,
  }) => layoutTextWithPainter(
    data: data,
    maxWidth: maxWidth,
    minWidth: minWidth,
    widthBasis: widthBasis,
    styleOverride: styleOverride,
    locale: locale,
  );
}

/// Extended layout result that includes a [TextPainter].
///
/// Use only when `TextPainter`-specific APIs are needed (cursor
/// positioning, selection boxes, etc.). Prefer [FlutterTextLayoutMetrics]
/// for all other cases.
@immutable
class FlutterPainterTextLayoutMetrics extends FlutterTextLayoutMetrics {
  FlutterPainterTextLayoutMetrics({
    required this.painter,
    required super.paragraph,
    required super.size,
    required super.lineHeight,
    required super.lineMetrics,
    required super.baseline,
    required super.ascent,
    required super.descent,
    required super.unscaledAscent,
    required super.leading,
  });

  /// The [TextPainter] for APIs like `getPositionForOffset`.
  final TextPainter painter;
}

/// Primary layout cache keyed on text + font + width.
final _paragraphCache = LruCache<_LayoutCacheKey, FlutterTextLayoutMetrics>(
  maxEntries: 256,
);

/// Font-metrics cache (width-independent) for better hit rates during
/// resize operations.
final _fontMetricsCache = LruCache<_FontMetricsCacheKey, _FontMetrics>(
  maxEntries: 64,
);

/// Painter cache for the rare paths that need `TextPainter`.
final _painterCache =
    LruCache<_PainterCacheKey, FlutterPainterTextLayoutMetrics>(maxEntries: 64);

/// Clears all text layout caches.
///
/// Call when switching documents or under memory pressure to
/// release stale `ui.Paragraph` native resources.
void clearTextLayoutCaches() {
  _paragraphCache.clear();
  _fontMetricsCache.clear();
  _painterCache.clear();
}

StrutStyle resolveTextStrutStyle(TextStyle style) =>
    StrutStyle.fromTextStyle(style, forceStrutHeight: true);

TextStyle buildTextStyle({
  required TextData data,
  Color? colorOverride,
  double? fontSizeOverride,
  Locale? locale,
}) => TextStyle(
  inherit: false,
  color: colorOverride ?? Color(data.color.toARGB32()),
  fontSize: fontSizeOverride ?? data.fontSize,
  fontFamily: _sanitizeFontFamily(data.fontFamily),
  locale: locale,
  textBaseline: TextBaseline.alphabetic,
);

/// Resolves a BCP-47 locale tag into a Flutter [Locale].
///
/// Returns null when [localeTag] is null, empty, or invalid.
Locale? resolveTextLocale(String? localeTag) {
  if (localeTag == null || localeTag.isEmpty) {
    return null;
  }
  final parts = localeTag
      .split(RegExp('[-_]'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return null;
  }

  final languageCode = parts.first.toLowerCase();
  if (!RegExp(r'^[a-z]{2,8}$').hasMatch(languageCode)) {
    return null;
  }

  String? scriptCode;
  String? countryCode;
  for (final part in parts.skip(1)) {
    if (scriptCode == null && part.length == 4) {
      final normalizedScript =
          '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
      if (!RegExp(r'^[A-Z][a-z]{3}$').hasMatch(normalizedScript)) {
        return null;
      }
      scriptCode = normalizedScript;
      continue;
    }
    if (countryCode == null && (part.length == 2 || part.length == 3)) {
      final normalizedCountry = part.toUpperCase();
      if (!RegExp(r'^[A-Z]{2}$|^\d{3}$').hasMatch(normalizedCountry)) {
        return null;
      }
      countryCode = normalizedCountry;
    }
  }

  return Locale.fromSubtags(
    languageCode: languageCode,
    scriptCode: scriptCode,
    countryCode: countryCode,
  );
}

/// Scene-focused text layout helper with fixed-width paragraph behavior.
FlutterTextLayoutMetrics layoutSceneText({
  required TextData data,
  required double width,
  String? localeTag,
}) => layoutText(
  data: data,
  maxWidth: width,
  minWidth: width,
  widthBasis: TextWidthBasis.parent,
  locale: resolveTextLocale(localeTag),
);

/// Lays out text and returns lightweight [FlutterTextLayoutMetrics].
///
/// This is the hot path used by renderers, bounds calculations, and
/// reducers. It bypasses `TextPainter` entirely and works with
/// `dart:ui.ParagraphBuilder` for lower overhead.
FlutterTextLayoutMetrics layoutText({
  required TextData data,
  required double maxWidth,
  double? minWidth,
  Color? colorOverride,
  TextWidthBasis widthBasis = TextWidthBasis.longestLine,
  TextStyle? styleOverride,
  Locale? locale,
  bool isResizing = false,
}) {
  final safeMaxWidth = maxWidth <= 0 ? 1.0 : maxWidth;
  final safeMinWidth = _resolveMinWidth(minWidth, safeMaxWidth);
  final resolvedText = data.text.isEmpty ? _fallbackText : data.text;
  final resolvedStyle =
      styleOverride ??
      buildTextStyle(data: data, colorOverride: colorOverride, locale: locale);

  final cacheKey = _LayoutCacheKey(
    text: resolvedText,
    fontSize: resolvedStyle.fontSize ?? data.fontSize,
    fontFamily: resolvedStyle.fontFamily ?? data.fontFamily,
    fontWeight: resolvedStyle.fontWeight,
    fontStyle: resolvedStyle.fontStyle,
    letterSpacing: resolvedStyle.letterSpacing,
    wordSpacing: resolvedStyle.wordSpacing,
    height: resolvedStyle.height,
    horizontalAlign: data.horizontalAlign,
    maxWidth: safeMaxWidth,
    minWidth: safeMinWidth,
    widthBasis: widthBasis,
    paintKey: _TextPaintKey.fromStyle(resolvedStyle),
    locale: locale,
    isResizing: isResizing,
  );

  return _paragraphCache.getOrCreate(cacheKey, () {
    final paragraph = _buildParagraph(
      text: resolvedText,
      style: resolvedStyle,
      align: data.horizontalAlign,
      locale: locale,
      maxWidth: safeMaxWidth,
    );

    final fontMetricsKey = _FontMetricsCacheKey(
      fontSize: resolvedStyle.fontSize ?? data.fontSize,
      fontFamily: resolvedStyle.fontFamily ?? data.fontFamily,
      fontWeight: resolvedStyle.fontWeight,
      fontStyle: resolvedStyle.fontStyle,
      letterSpacing: resolvedStyle.letterSpacing,
      wordSpacing: resolvedStyle.wordSpacing,
      height: resolvedStyle.height,
      locale: locale,
    );

    final fontMetrics = _fontMetricsCache.getOrCreate(
      fontMetricsKey,
      () => _measureFontMetrics(style: resolvedStyle, locale: locale),
    );

    return FlutterTextLayoutMetrics(
      paragraph: paragraph,
      size: Size(paragraph.longestLine, paragraph.height),
      lineHeight: fontMetrics.lineHeight,
      lineMetrics: null,
      baseline: fontMetrics.baseline,
      ascent: fontMetrics.ascent,
      descent: fontMetrics.descent,
      unscaledAscent: fontMetrics.unscaledAscent,
      leading: fontMetrics.leading,
    );
  });
}

/// Lays out text and returns [FlutterPainterTextLayoutMetrics] with a
/// [TextPainter].
///
/// Use only when you need `TextPainter`-specific APIs such as
/// `getPositionForOffset` or `getBoxesForSelection`.
FlutterPainterTextLayoutMetrics layoutTextWithPainter({
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
      buildTextStyle(data: data, colorOverride: colorOverride, locale: locale);

  final cacheKey = _PainterCacheKey(
    text: resolvedText,
    fontSize: resolvedStyle.fontSize ?? data.fontSize,
    fontFamily: resolvedStyle.fontFamily ?? data.fontFamily,
    horizontalAlign: data.horizontalAlign,
    maxWidth: _quantize(safeMaxWidth),
    minWidth: _quantize(safeMinWidth),
    widthBasis: widthBasis,
    paintKey: _TextPaintKey.fromStyle(resolvedStyle),
    locale: locale,
  );

  return _painterCache.getOrCreate(cacheKey, () {
    final strutStyle = resolveTextStrutStyle(resolvedStyle);
    final painter = TextPainter(
      text: TextSpan(text: resolvedText, style: resolvedStyle),
      textAlign: _toFlutterAlign(data.horizontalAlign),
      textDirection: TextDirection.ltr,
      textHeightBehavior: textLayoutHeightBehavior,
      textScaler: textLayoutTextScaler,
      textWidthBasis: widthBasis,
      strutStyle: strutStyle,
      locale: locale,
    )..layout(minWidth: safeMinWidth, maxWidth: safeMaxWidth);

    final lineMetrics = painter.computeLineMetrics();
    final fm = _extractFontMetricsFromPainter(painter, lineMetrics);

    // Reuse the paragraph from the fast layout path when possible,
    // avoiding a redundant ParagraphBuilder + layout call.
    final fastLayout = layoutText(
      data: data,
      maxWidth: safeMaxWidth,
      minWidth: safeMinWidth,
      colorOverride: colorOverride,
      widthBasis: widthBasis,
      styleOverride: resolvedStyle,
      locale: locale,
    );

    return FlutterPainterTextLayoutMetrics(
      painter: painter,
      paragraph: fastLayout.paragraph,
      size: painter.size,
      lineHeight: fm.lineHeight,
      lineMetrics: lineMetrics,
      baseline: fm.baseline,
      ascent: fm.ascent,
      descent: fm.descent,
      unscaledAscent: fm.unscaledAscent,
      leading: fm.leading,
    );
  });
}

ui.Paragraph _buildParagraph({
  required String text,
  required TextStyle style,
  required TextHorizontalAlign align,
  required Locale? locale,
  required double maxWidth,
}) {
  // Build strut-equivalent line height via ParagraphStyle.
  final fontSize = style.fontSize ?? 14.0;
  final paragraphStyle = ui.ParagraphStyle(
    textAlign: _toFlutterAlign(align),
    textDirection: ui.TextDirection.ltr,
    fontSize: fontSize,
    fontFamily: style.fontFamily,
    fontWeight: style.fontWeight,
    fontStyle: style.fontStyle,
    height: style.height,
    textHeightBehavior: textLayoutHeightBehavior,
    strutStyle: ui.StrutStyle(
      fontFamily: style.fontFamily,
      fontSize: fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      height: style.height,
      forceStrutHeight: true,
    ),
    locale: locale,
  );

  final textStyle = ui.TextStyle(
    color: style.color,
    fontSize: fontSize,
    fontFamily: style.fontFamily,
    fontWeight: style.fontWeight,
    fontStyle: style.fontStyle,
    letterSpacing: style.letterSpacing,
    wordSpacing: style.wordSpacing,
    height: style.height,
    locale: locale,
    textBaseline: ui.TextBaseline.alphabetic,
  );

  final builder = ui.ParagraphBuilder(paragraphStyle)
    ..pushStyle(textStyle)
    ..addText(text)
    ..pop();

  return builder.build()..layout(ui.ParagraphConstraints(width: maxWidth));
}

_FontMetrics _measureFontMetrics({
  required TextStyle style,
  required Locale? locale,
}) {
  final probeParagraph = _buildParagraph(
    text: _fontMetricsProbeText,
    style: style,
    align: TextHorizontalAlign.left,
    locale: locale,
    maxWidth: 4096,
  );
  final probeLineMetrics = probeParagraph.computeLineMetrics();
  return _extractFontMetricsFromParagraph(probeParagraph, probeLineMetrics);
}

_FontMetrics _extractFontMetricsFromPainter(
  TextPainter painter,
  List<ui.LineMetrics> lineMetrics,
) => _extractFontMetrics(
  lineMetrics: lineMetrics,
  fallbackBaseline: painter.computeDistanceToActualBaseline(
    TextBaseline.alphabetic,
  ),
  fallbackLineHeight: painter.preferredLineHeight,
);

_FontMetrics _extractFontMetricsFromParagraph(
  ui.Paragraph paragraph,
  List<ui.LineMetrics> lineMetrics,
) {
  final fallbackLineHeight = lineMetrics.isNotEmpty
      ? lineMetrics.first.height
      : (paragraph.height > 0 ? paragraph.height : 14.0);
  return _extractFontMetrics(
    lineMetrics: lineMetrics,
    fallbackBaseline: paragraph.alphabeticBaseline,
    fallbackLineHeight: fallbackLineHeight,
  );
}

_FontMetrics _extractFontMetrics({
  required List<ui.LineMetrics> lineMetrics,
  required double fallbackBaseline,
  required double fallbackLineHeight,
}) {
  final primaryLine = lineMetrics.isNotEmpty ? lineMetrics.first : null;

  final baseline = primaryLine?.baseline ?? fallbackBaseline;
  final lineHeight = primaryLine?.height ?? fallbackLineHeight;
  final ascent = primaryLine?.ascent ?? baseline;
  final descent = primaryLine?.descent ?? _nonNegative(lineHeight - ascent);
  final unscaledAscent = primaryLine?.unscaledAscent ?? ascent;
  final leading = primaryLine == null
      ? _nonNegative(lineHeight - ascent - descent)
      : _nonNegative(
          primaryLine.height - primaryLine.ascent - primaryLine.descent,
        );

  return _FontMetrics(
    lineHeight: lineHeight,
    baseline: baseline,
    ascent: ascent,
    descent: descent,
    unscaledAscent: unscaledAscent,
    leading: leading,
  );
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

/// Fine quantization (0.1 px).
double _quantize(double value) => (value * 10).roundToDouble() / 10;

/// Cache key for the fast [layoutText] path.
///
/// Includes paint attributes because callers may draw the cached
/// `ui.Paragraph` directly (not just consume geometry).
@immutable
class _LayoutCacheKey {
  _LayoutCacheKey({
    required this.text,
    required this.fontSize,
    required this.fontFamily,
    required this.fontWeight,
    required this.fontStyle,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.height,
    required this.horizontalAlign,
    required double maxWidth,
    required double minWidth,
    required this.widthBasis,
    required this.paintKey,
    required this.locale,
    required bool isResizing,
  }) : maxWidth = isResizing ? _quantizeCoarse(maxWidth) : _quantize(maxWidth),
       minWidth = isResizing ? _quantizeCoarse(minWidth) : _quantize(minWidth);

  final String text;
  final double fontSize;
  final String? fontFamily;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final double? letterSpacing;
  final double? wordSpacing;
  final double? height;
  final TextHorizontalAlign horizontalAlign;
  final double maxWidth;
  final double minWidth;
  final TextWidthBasis widthBasis;
  final _TextPaintKey paintKey;
  final Locale? locale;

  static double _quantizeCoarse(double value) =>
      (value / 5).roundToDouble() * 5;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LayoutCacheKey &&
          other.text == text &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.fontWeight == fontWeight &&
          other.fontStyle == fontStyle &&
          other.letterSpacing == letterSpacing &&
          other.wordSpacing == wordSpacing &&
          other.height == height &&
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
    horizontalAlign,
    maxWidth,
    minWidth,
    widthBasis,
    paintKey,
    locale,
  );
}

/// Cache key for [layoutTextWithPainter] (includes paint properties).
@immutable
class _PainterCacheKey {
  const _PainterCacheKey({
    required this.text,
    required this.fontSize,
    required this.fontFamily,
    required this.horizontalAlign,
    required this.maxWidth,
    required this.minWidth,
    required this.widthBasis,
    required this.paintKey,
    required this.locale,
  });

  final String text;
  final double fontSize;
  final String? fontFamily;
  final TextHorizontalAlign horizontalAlign;
  final double maxWidth;
  final double minWidth;
  final TextWidthBasis widthBasis;
  final _TextPaintKey paintKey;
  final Locale? locale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PainterCacheKey &&
          other.text == text &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
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
      strokeWidth: _quantizePaint(foreground.strokeWidth),
      strokeCap: foreground.strokeCap,
      strokeJoin: foreground.strokeJoin,
      strokeMiterLimit: _quantizePaint(foreground.strokeMiterLimit),
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

  static double _quantizePaint(double value) =>
      (value * 10).roundToDouble() / 10;

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

/// Width-independent font metrics for two-tier caching.
@immutable
class _FontMetrics {
  const _FontMetrics({
    required this.lineHeight,
    required this.baseline,
    required this.ascent,
    required this.descent,
    required this.unscaledAscent,
    required this.leading,
  });

  final double lineHeight;
  final double baseline;
  final double ascent;
  final double descent;
  final double unscaledAscent;
  final double leading;
}

/// Cache key for width-independent font metrics.
@immutable
class _FontMetricsCacheKey {
  const _FontMetricsCacheKey({
    required this.fontSize,
    required this.fontFamily,
    required this.fontWeight,
    required this.fontStyle,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.height,
    required this.locale,
  });

  final double fontSize;
  final String? fontFamily;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final double? letterSpacing;
  final double? wordSpacing;
  final double? height;
  final Locale? locale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FontMetricsCacheKey &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.fontWeight == fontWeight &&
          other.fontStyle == fontStyle &&
          other.letterSpacing == letterSpacing &&
          other.wordSpacing == wordSpacing &&
          other.height == height &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
    fontSize,
    fontFamily,
    fontWeight,
    fontStyle,
    letterSpacing,
    wordSpacing,
    height,
    locale,
  );
}
