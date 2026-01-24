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
  final style =
      styleOverride ??
      buildTextStyle(
        data: data,
        colorOverride: colorOverride,
        locale: locale,
      );
  final strutStyle = resolveTextStrutStyle(style);
  final painter = TextPainter(
    text: TextSpan(
      text: data.text.isEmpty ? _fallbackText : data.text,
      style: style,
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
