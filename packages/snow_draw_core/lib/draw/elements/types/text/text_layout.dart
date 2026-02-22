import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../services/text/text_metrics_service.dart';
import '../../../types/element_style.dart';
import 'text_data.dart';

const textCursorWidth = 1.2;
const textCaretGap = 1.0;
const double textCaretMargin = textCursorWidth + textCaretGap;
const _textLayoutHorizontalPaddingFactor = 0.01;
const _textBackgroundHorizontalPaddingFactor = 0.32;
const _textBackgroundVerticalPaddingFactor = 0.1;

/// Lightweight text size snapshot in logical pixels.
@immutable
class TextLayoutSize {
  /// Creates a text size snapshot.
  const TextLayoutSize({required this.width, required this.height});

  /// Width in logical pixels.
  final double width;

  /// Height in logical pixels.
  final double height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextLayoutSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// Lightweight background box snapshot in local text coordinates.
@immutable
class TextRangeBox {
  /// Creates a text range box.
  const TextRangeBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Left edge in local text coordinates.
  final double left;

  /// Top edge in local text coordinates.
  final double top;

  /// Right edge in local text coordinates.
  final double right;

  /// Bottom edge in local text coordinates.
  final double bottom;
}

/// Core layout snapshot used by scene encoding and reducer tests.
@immutable
class TextLayoutMetrics {
  /// Creates core text layout metrics.
  const TextLayoutMetrics({
    required this.size,
    required this.lineHeight,
    required this.lineMetrics,
    required this.maxWidth,
    required this.horizontalAlign,
    required this.text,
  });

  /// Total text bounds in logical pixels.
  final TextLayoutSize size;

  /// Effective line height in logical pixels.
  final double lineHeight;

  /// Per-line metrics.
  final List<TextLineMetrics> lineMetrics;

  /// Layout max width used during measurement.
  final double maxWidth;

  /// Horizontal text alignment.
  final TextHorizontalAlign horizontalAlign;

  /// Measured text (empty text is normalized to a single space).
  final String text;
}

/// Clears any backend-provided text measurement caches.
void clearTextLayoutCaches() {
  defaultTextMetricsService.clearCaches();
}

/// Resolves horizontal background padding from line height.
double resolveTextBackgroundHorizontalPadding(double lineHeight) {
  final padding = lineHeight * _textBackgroundHorizontalPaddingFactor;
  if (padding.isNaN || padding.isInfinite) {
    return 0;
  }
  return padding;
}

/// Resolves vertical background padding from line height.
double resolveTextBackgroundVerticalPadding(double lineHeight) {
  final padding = lineHeight * _textBackgroundVerticalPaddingFactor;
  if (padding.isNaN || padding.isInfinite) {
    return 0;
  }
  return padding;
}

/// Resolves horizontal layout padding from line height.
double resolveTextLayoutHorizontalPadding(double lineHeight) {
  final padding = lineHeight * _textLayoutHorizontalPaddingFactor;
  if (padding.isNaN || padding.isInfinite) {
    return 0;
  }
  return padding;
}

/// Scene-focused text layout helper with fixed-width behavior.
TextLayoutMetrics layoutSceneText({
  required TextData data,
  required double width,
  String? localeTag,
  TextMetricsService textMetricsService = defaultTextMetricsService,
}) => layoutText(
  data: data,
  maxWidth: width,
  minWidth: width,
  localeTag: localeTag,
  textMetricsService: textMetricsService,
);

/// Measures text with backend-agnostic [TextMetricsService].
TextLayoutMetrics layoutText({
  required TextData data,
  required double maxWidth,
  double? minWidth,
  String? localeTag,
  bool isResizing = false,
  TextMetricsService textMetricsService = defaultTextMetricsService,
}) {
  final safeMaxWidth = _resolveMaxWidth(maxWidth);
  final safeMinWidth = _resolveMinWidth(minWidth, safeMaxWidth);
  final request = TextLayoutRequest(
    data: data,
    maxWidth: safeMaxWidth,
    minWidth: safeMinWidth,
    localeTag: localeTag,
    isResizing: isResizing,
  );
  final metrics = textMetricsService.measure(request);

  final lineHeight = _sanitizeExtent(metrics.lineHeight, fallback: 1);
  final width = _sanitizeExtent(
    metrics.width,
    fallback: safeMinWidth > 0 ? safeMinWidth : 1,
  );
  final height = _sanitizeExtent(metrics.height, fallback: lineHeight);

  final resolvedLines = metrics.lines.isEmpty
      ? <TextLineMetrics>[TextLineMetrics(width: width, height: lineHeight)]
      : metrics.lines
            .map(
              (line) => TextLineMetrics(
                width: _sanitizeExtent(line.width, fallback: width),
                height: _sanitizeExtent(line.height, fallback: lineHeight),
              ),
            )
            .toList(growable: false);

  return TextLayoutMetrics(
    size: TextLayoutSize(width: width, height: height),
    lineHeight: lineHeight,
    lineMetrics: List<TextLineMetrics>.unmodifiable(resolvedLines),
    maxWidth: safeMaxWidth,
    horizontalAlign: data.horizontalAlign,
    text: data.text.isEmpty ? ' ' : data.text,
  );
}

/// Resolves range boxes as pure geometry values.
///
/// The core currently uses this for full-range background rendering, so partial
/// selections are approximated by proportional glyph widths per line.
List<TextRangeBox> resolveTextRangeBoxes({
  required TextLayoutMetrics layout,
  required int start,
  required int end,
}) {
  if (end <= start) {
    return const <TextRangeBox>[];
  }
  if (layout.lineMetrics.isEmpty) {
    return const <TextRangeBox>[];
  }

  final textLength = layout.text.length;
  if (textLength <= 0) {
    return _buildFullLineBoxes(layout);
  }

  final clampedStart = start.clamp(0, textLength);
  final clampedEnd = end.clamp(0, textLength);
  if (clampedEnd <= clampedStart) {
    return const <TextRangeBox>[];
  }

  if (clampedStart == 0 && clampedEnd == textLength) {
    return _buildFullLineBoxes(layout);
  }

  final segments = _buildLineSegments(layout.text, layout.lineMetrics.length);
  final boxes = <TextRangeBox>[];
  var top = 0.0;
  for (var i = 0; i < layout.lineMetrics.length; i++) {
    final line = layout.lineMetrics[i];
    final lineHeight = _sanitizeExtent(
      line.height,
      fallback: layout.lineHeight,
    );
    final segment = segments[i];

    final overlapStart = math.max(clampedStart, segment.start);
    final overlapEnd = math.min(clampedEnd, segment.end);
    if (overlapEnd > overlapStart) {
      final charCount = math.max(1, segment.end - segment.start);
      final glyphWidth = line.width / charCount;
      final lineLeft = _resolveAlignedLineX(layout, line.width);
      final left = lineLeft + (overlapStart - segment.start) * glyphWidth;
      final right = lineLeft + (overlapEnd - segment.start) * glyphWidth;
      boxes.add(
        TextRangeBox(
          left: left,
          top: top,
          right: right,
          bottom: top + lineHeight,
        ),
      );
    }

    top += lineHeight;
  }

  return boxes;
}

List<TextRangeBox> _buildFullLineBoxes(TextLayoutMetrics layout) {
  final boxes = <TextRangeBox>[];
  var top = 0.0;
  for (final line in layout.lineMetrics) {
    final lineWidth = _sanitizeExtent(line.width, fallback: layout.size.width);
    final lineHeight = _sanitizeExtent(
      line.height,
      fallback: layout.lineHeight,
    );
    final left = _resolveAlignedLineX(layout, lineWidth);
    boxes.add(
      TextRangeBox(
        left: left,
        top: top,
        right: left + lineWidth,
        bottom: top + lineHeight,
      ),
    );
    top += lineHeight;
  }
  return boxes;
}

List<_LineSegment> _buildLineSegments(String text, int visualLineCount) {
  if (visualLineCount <= 0) {
    return const <_LineSegment>[];
  }

  final logicalLines = text.split('\n');
  final segments = <_LineSegment>[];
  var cursor = 0;
  for (var i = 0; i < logicalLines.length; i++) {
    final line = logicalLines[i];
    final start = cursor;
    final end = cursor + line.length;
    segments.add(_LineSegment(start: start, end: end));
    cursor = end;
    if (i < logicalLines.length - 1) {
      cursor += 1; // skip newline separator.
    }
  }

  if (segments.isEmpty) {
    segments.add(const _LineSegment(start: 0, end: 1));
  }

  if (segments.length >= visualLineCount) {
    return segments.take(visualLineCount).toList(growable: false);
  }

  final padded = [...segments];
  final fallback = segments.last;
  while (padded.length < visualLineCount) {
    padded.add(fallback);
  }
  return List<_LineSegment>.unmodifiable(padded);
}

double _resolveAlignedLineX(TextLayoutMetrics layout, double lineWidth) {
  if (!layout.maxWidth.isFinite) {
    return 0;
  }

  final delta = layout.maxWidth - lineWidth;
  if (!delta.isFinite || delta <= 0) {
    return 0;
  }

  return switch (layout.horizontalAlign) {
    TextHorizontalAlign.left => 0,
    TextHorizontalAlign.center => delta / 2,
    TextHorizontalAlign.right => delta,
  };
}

double _resolveMaxWidth(double maxWidth) {
  if (!maxWidth.isFinite) {
    return double.infinity;
  }
  if (maxWidth <= 0) {
    return 1;
  }
  return maxWidth;
}

double _resolveMinWidth(double? minWidth, double maxWidth) {
  if (minWidth == null ||
      minWidth <= 0 ||
      minWidth.isNaN ||
      minWidth.isInfinite) {
    return 0;
  }
  if (maxWidth.isFinite && minWidth > maxWidth) {
    return maxWidth;
  }
  return minWidth;
}

double _sanitizeExtent(double value, {required double fallback}) {
  if (value.isFinite && value > 0) {
    return value;
  }
  return fallback;
}

@immutable
class _LineSegment {
  const _LineSegment({required this.start, required this.end});

  final int start;
  final int end;
}
