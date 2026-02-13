import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../models/element_state.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import '../../../utils/stroke_pattern_utils.dart';
import '../../core/element_renderer.dart';
import 'text_data.dart';
import 'text_layout.dart';

class TextRenderer extends ElementTypeRenderer {
  const TextRenderer();

  static const double _lineFillAngle = -math.pi / 4;
  static const double _crossLineFillAngle = math.pi / 4;

  /// Per-element cache for background text boxes (the expensive
  /// `getBoxesForRange` call). Keyed by text content, font properties,
  /// and layout width so duplicate elements share cached results.
  static final _backgroundBoxCache =
      LruCache<_BackgroundBoxKey, List<ui.TextBox>>(maxEntries: 256);

  /// Clears all static caches held by [TextRenderer].
  ///
  /// Call when switching documents or under memory pressure to
  /// release stale `ui.Paragraph` and `ui.Shader` native resources.
  static void clearCaches() {
    clearStrokePatternCaches();
    _backgroundBoxCache.clear();
    _fillParagraphCache.clear();
    _strokeParagraphCache.clear();
    _backgroundPathCache.clear();
  }

  Paint _buildLineFillPaint({
    required double spacing,
    required double lineWidth,
    required double angle,
    required Color color,
  }) => buildLineFillPaint(
    spacing: spacing,
    lineWidth: lineWidth,
    angle: angle,
    color: color,
  );

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
        'TextRenderer can only render TextData '
        '(got ${data.runtimeType})',
      );
    }

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

    // Single layout call – the Paragraph cache handles dedup.
    final layout = layoutText(
      data: data,
      maxWidth: layoutWidth,
      minWidth: layoutWidth,
      widthBasis: TextWidthBasis.parent,
      locale: locale,
    );

    final textOffset = _resolveTextOffset(
      containerSize: Size(rect.width, rect.height),
      textSize: layout.size,
      verticalAlign: data.verticalAlign,
    );

    // Background
    final backgroundHPad = shouldDrawBackground
        ? resolveTextBackgroundHorizontalPadding(layout.lineHeight)
        : 0.0;
    final backgroundVPad = shouldDrawBackground
        ? resolveTextBackgroundVerticalPadding(layout.lineHeight)
        : 0.0;
    final bgColor = data.fillColor.withValues(alpha: backgroundOpacity);
    Paint? backgroundPaint;
    Paint? crossLinePaint;
    if (shouldDrawBackground) {
      if (data.fillStyle == FillStyle.solid) {
        backgroundPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = bgColor
          ..isAntiAlias = true;
      } else {
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
          color: bgColor,
        );
        if (data.fillStyle == FillStyle.crossLine) {
          crossLinePaint = _buildLineFillPaint(
            spacing: spacing,
            lineWidth: fillLineWidth,
            angle: _crossLineFillAngle,
            color: bgColor,
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
      final boxes = _resolveBackgroundBoxes(
        paragraph: layout.paragraph,
        text: data.text,
        fontSize: data.fontSize,
        fontFamily: data.fontFamily,
        horizontalAlign: data.horizontalAlign,
        layoutWidth: layoutWidth,
      );
      _paintTextBackground(
        canvas: canvas,
        paintOffset: textOffset,
        horizontalPadding: backgroundHPad,
        verticalPadding: backgroundVPad,
        paint: backgroundPaint,
        cornerRadius: data.cornerRadius,
        boxes: boxes,
      );
      if (crossLinePaint != null) {
        _paintTextBackground(
          canvas: canvas,
          paintOffset: textOffset,
          horizontalPadding: backgroundHPad,
          verticalPadding: backgroundVPad,
          paint: crossLinePaint,
          cornerRadius: data.cornerRadius,
          boxes: boxes,
        );
      }
    }

    // Stroke pass – needs a separate Paragraph with stroke paint.
    if (shouldDrawStroke) {
      final strokeParagraph = _buildStrokeParagraph(
        data: data,
        strokeOpacity: strokeOpacity,
        align: data.horizontalAlign,
        locale: locale,
        minWidth: layoutWidth,
        maxWidth: layoutWidth,
      );
      canvas.drawParagraph(strokeParagraph, textOffset);
    }

    // Fill pass – reuse the layout paragraph when the color already
    // matches (opacity == 1.0), avoiding a redundant paragraph build.
    if (shouldDrawFill) {
      final fillParagraph = _resolveFillParagraph(
        data: data,
        textOpacity: textOpacity,
        layout: layout,
        locale: locale,
        minWidth: layoutWidth,
        maxWidth: layoutWidth,
      );
      canvas.drawParagraph(fillParagraph, textOffset);
    }

    canvas.restore();
  }

  /// Cache for fill paragraphs keyed by element-relevant properties.
  static final _fillParagraphCache = LruCache<_FillParagraphKey, ui.Paragraph>(
    maxEntries: 256,
  );

  /// Cache for stroke paragraphs.
  static final _strokeParagraphCache =
      LruCache<_StrokeParagraphKey, ui.Paragraph>(maxEntries: 128);

  /// Returns a paragraph suitable for the fill pass.
  ///
  /// When the resolved fill color matches the color already baked into
  /// the layout paragraph (common case: element opacity == 1.0), the
  /// layout paragraph is returned directly, avoiding a redundant
  /// `ParagraphBuilder` + `layout()` call.
  ui.Paragraph _resolveFillParagraph({
    required TextData data,
    required double textOpacity,
    required TextLayoutMetrics layout,
    required Locale? locale,
    required double minWidth,
    required double maxWidth,
  }) {
    final fillColor = data.color.withValues(alpha: textOpacity);
    // The layout paragraph is built with data.color (no opacity
    // adjustment). If the resolved fill color is identical, reuse it.
    if (fillColor == data.color) {
      return layout.paragraph;
    }
    final key = _FillParagraphKey(
      text: data.text.isEmpty ? ' ' : data.text,
      fontSize: data.fontSize,
      fontFamily: data.fontFamily,
      horizontalAlign: data.horizontalAlign,
      colorValue: fillColor.toARGB32(),
      maxWidth: _quantize(maxWidth),
      locale: locale,
    );
    return _fillParagraphCache.getOrCreate(
      key,
      () => _buildRawParagraph(
        text: data.text.isEmpty ? ' ' : data.text,
        data: data,
        color: fillColor,
        locale: locale,
        minWidth: minWidth,
        maxWidth: maxWidth,
      ),
    );
  }

  ui.Paragraph _buildStrokeParagraph({
    required TextData data,
    required double strokeOpacity,
    required TextHorizontalAlign align,
    required Locale? locale,
    required double minWidth,
    required double maxWidth,
  }) {
    final key = _StrokeParagraphKey(
      text: data.text.isEmpty ? ' ' : data.text,
      fontSize: data.fontSize,
      fontFamily: data.fontFamily,
      horizontalAlign: data.horizontalAlign,
      strokeColorValue: data.strokeColor
          .withValues(alpha: strokeOpacity)
          .toARGB32(),
      strokeWidth: data.strokeWidth,
      maxWidth: _quantize(maxWidth),
      locale: locale,
    );
    return _strokeParagraphCache.getOrCreate(key, () {
      final strokeColor = data.strokeColor.withValues(alpha: strokeOpacity);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = data.strokeWidth
        ..color = strokeColor
        ..isAntiAlias = true;
      return _buildRawParagraph(
        text: data.text.isEmpty ? ' ' : data.text,
        data: data,
        foreground: paint,
        locale: locale,
        minWidth: minWidth,
        maxWidth: maxWidth,
      );
    });
  }

  ui.Paragraph _buildRawParagraph({
    required String text,
    required TextData data,
    required Locale? locale,
    required double minWidth,
    required double maxWidth,
    Color? color,
    Paint? foreground,
  }) {
    final fontSize = data.fontSize;
    final fontFamily = data.fontFamily?.trim();
    final resolvedFamily = (fontFamily == null || fontFamily.isEmpty)
        ? null
        : fontFamily;

    final paragraphStyle = ui.ParagraphStyle(
      textAlign: _toFlutterAlign(data.horizontalAlign),
      textDirection: TextDirection.ltr,
      fontSize: fontSize,
      fontFamily: resolvedFamily,
      textHeightBehavior: textLayoutHeightBehavior,
      strutStyle: ui.StrutStyle(
        fontFamily: resolvedFamily,
        fontSize: fontSize,
        forceStrutHeight: true,
      ),
      locale: locale,
    );

    final uiStyle = foreground != null
        ? ui.TextStyle(
            fontSize: fontSize,
            fontFamily: resolvedFamily,
            foreground: foreground,
            locale: locale,
            textBaseline: ui.TextBaseline.alphabetic,
          )
        : ui.TextStyle(
            color: color,
            fontSize: fontSize,
            fontFamily: resolvedFamily,
            locale: locale,
            textBaseline: ui.TextBaseline.alphabetic,
          );

    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(uiStyle)
      ..addText(text)
      ..pop();

    return builder.build()..layout(ui.ParagraphConstraints(width: maxWidth));
  }

  static TextAlign _toFlutterAlign(TextHorizontalAlign align) {
    switch (align) {
      case TextHorizontalAlign.left:
        return TextAlign.left;
      case TextHorizontalAlign.center:
        return TextAlign.center;
      case TextHorizontalAlign.right:
        return TextAlign.right;
    }
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

  /// Cache for pre-built background [Path] objects, avoiding per-frame
  /// allocation in [_paintTextBackground].
  static final _backgroundPathCache = LruCache<_BackgroundPathKey, Path>(
    maxEntries: 256,
  );

  List<ui.TextBox> _resolveBackgroundBoxes({
    required ui.Paragraph paragraph,
    required String text,
    required double fontSize,
    required String? fontFamily,
    required TextHorizontalAlign horizontalAlign,
    required double layoutWidth,
  }) {
    final resolvedText = text.isEmpty ? ' ' : text;
    final key = _BackgroundBoxKey(
      text: resolvedText,
      fontSize: fontSize,
      fontFamily: fontFamily,
      horizontalAlign: horizontalAlign,
      layoutWidth: _quantize(layoutWidth),
    );
    return _backgroundBoxCache.getOrCreate(
      key,
      () => paragraph.getBoxesForRange(
        0,
        resolvedText.length,
        boxHeightStyle: ui.BoxHeightStyle.strut,
      ),
    );
  }

  void _paintTextBackground({
    required Canvas canvas,
    required Offset paintOffset,
    required double horizontalPadding,
    required double verticalPadding,
    required Paint paint,
    required double cornerRadius,
    required List<ui.TextBox> boxes,
  }) {
    if (boxes.isEmpty) {
      return;
    }
    final pathKey = _BackgroundPathKey(
      boxes: boxes,
      paintOffsetDx: paintOffset.dx,
      paintOffsetDy: paintOffset.dy,
      horizontalPadding: horizontalPadding,
      verticalPadding: verticalPadding,
      cornerRadius: cornerRadius,
    );
    final backgroundPath = _backgroundPathCache.getOrCreate(
      pathKey,
      () => _buildBackgroundPath(
        paintOffset: paintOffset,
        horizontalPadding: horizontalPadding,
        verticalPadding: verticalPadding,
        cornerRadius: cornerRadius,
        boxes: boxes,
      ),
    );
    canvas.drawPath(backgroundPath, paint);
  }

  static Path _buildBackgroundPath({
    required Offset paintOffset,
    required double horizontalPadding,
    required double verticalPadding,
    required double cornerRadius,
    required List<ui.TextBox> boxes,
  }) {
    final path = Path();
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
        path.addRect(rect);
      } else {
        path.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      }
    }
    return path;
  }

  static double _clampCornerRadius(double cornerRadius, Rect rect) {
    if (cornerRadius <= 0) {
      return 0;
    }
    final maxRadius = rect.shortestSide / 2;
    if (cornerRadius > maxRadius) {
      return maxRadius;
    }
    return cornerRadius;
  }

  static double _quantize(double value) => (value * 10).roundToDouble() / 10;
}

// ---------------------------------------------------------------------------
// Supporting types
// ---------------------------------------------------------------------------

/// Content-based key for background box caching so duplicate elements
/// with the same text and font properties share cached results.
@immutable
class _BackgroundBoxKey {
  const _BackgroundBoxKey({
    required this.text,
    required this.fontSize,
    required this.fontFamily,
    required this.horizontalAlign,
    required this.layoutWidth,
  });

  final String text;
  final double fontSize;
  final String? fontFamily;
  final TextHorizontalAlign horizontalAlign;
  final double layoutWidth;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _BackgroundBoxKey &&
          other.text == text &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.horizontalAlign == horizontalAlign &&
          other.layoutWidth == layoutWidth;

  @override
  int get hashCode =>
      Object.hash(text, fontSize, fontFamily, horizontalAlign, layoutWidth);
}

/// Cache key for pre-built background [Path] objects.
///
/// Uses identity of the [boxes] list (which comes from the box cache)
/// combined with the padding/offset/radius parameters that affect the
/// final path geometry.
@immutable
class _BackgroundPathKey {
  const _BackgroundPathKey({
    required this.boxes,
    required this.paintOffsetDx,
    required this.paintOffsetDy,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.cornerRadius,
  });

  final List<ui.TextBox> boxes;
  final double paintOffsetDx;
  final double paintOffsetDy;
  final double horizontalPadding;
  final double verticalPadding;
  final double cornerRadius;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _BackgroundPathKey &&
          identical(other.boxes, boxes) &&
          other.paintOffsetDx == paintOffsetDx &&
          other.paintOffsetDy == paintOffsetDy &&
          other.horizontalPadding == horizontalPadding &&
          other.verticalPadding == verticalPadding &&
          other.cornerRadius == cornerRadius;

  @override
  int get hashCode => Object.hash(
    identityHashCode(boxes),
    paintOffsetDx,
    paintOffsetDy,
    horizontalPadding,
    verticalPadding,
    cornerRadius,
  );
}

@immutable
class _FillParagraphKey {
  const _FillParagraphKey({
    required this.text,
    required this.fontSize,
    required this.fontFamily,
    required this.horizontalAlign,
    required this.colorValue,
    required this.maxWidth,
    required this.locale,
  });

  final String text;
  final double fontSize;
  final String? fontFamily;
  final TextHorizontalAlign horizontalAlign;
  final int colorValue;
  final double maxWidth;
  final Locale? locale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FillParagraphKey &&
          other.text == text &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.horizontalAlign == horizontalAlign &&
          other.colorValue == colorValue &&
          other.maxWidth == maxWidth &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
    text,
    fontSize,
    fontFamily,
    horizontalAlign,
    colorValue,
    maxWidth,
    locale,
  );
}

@immutable
class _StrokeParagraphKey {
  const _StrokeParagraphKey({
    required this.text,
    required this.fontSize,
    required this.fontFamily,
    required this.horizontalAlign,
    required this.strokeColorValue,
    required this.strokeWidth,
    required this.maxWidth,
    required this.locale,
  });

  final String text;
  final double fontSize;
  final String? fontFamily;
  final TextHorizontalAlign horizontalAlign;
  final int strokeColorValue;
  final double strokeWidth;
  final double maxWidth;
  final Locale? locale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _StrokeParagraphKey &&
          other.text == text &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily &&
          other.horizontalAlign == horizontalAlign &&
          other.strokeColorValue == strokeColorValue &&
          other.strokeWidth == strokeWidth &&
          other.maxWidth == maxWidth &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
    text,
    fontSize,
    fontFamily,
    horizontalAlign,
    strokeColorValue,
    strokeWidth,
    maxWidth,
    locale,
  );
}
