import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextWidthBasis;

import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/element_scene_encoder.dart';
import 'text_data.dart';
import 'text_layout.dart';

/// Encodes text elements into backend-agnostic scene primitives.
///
/// Supports fill/stroke text runs and all text background fill styles.
final class TextSceneEncoder implements ElementSceneEncoder<TextData> {
  /// Creates a text scene encoder.
  const TextSceneEncoder();
  static const _kappa = 0.5522847498307936;
  static const double _lineFillAngle = -math.pi / 4;
  static const _lineToSpacingRatio = 4.0;

  @override
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
  }) {
    assert(scaleFactor.isFinite, 'scaleFactor must be finite.');
    assert(
      localeTag == null || localeTag.isNotEmpty,
      'localeTag must be null or non-empty.',
    );

    final data = element.data;
    if (data is! TextData) {
      throw StateError(
        'TextSceneEncoder can only encode TextData (got ${data.runtimeType})',
      );
    }

    final textColorArgb = _applyElementOpacity(
      argb: data.color.toARGB32(),
      elementOpacity: element.opacity,
    );
    final backgroundColorArgb = _applyElementOpacity(
      argb: data.fillColor.toARGB32(),
      elementOpacity: element.opacity,
    );
    final strokeColorArgb = _applyElementOpacity(
      argb: data.strokeColor.toARGB32(),
      elementOpacity: element.opacity,
    );

    final hasBackground = _alphaOf(backgroundColorArgb) > 0;
    final hasTextStroke = _alphaOf(strokeColorArgb) > 0 && data.strokeWidth > 0;
    final hasTextFill = _alphaOf(textColorArgb) > 0;
    if (!hasTextFill && !hasBackground && !hasTextStroke) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }

    final rect = element.rect;
    if (rect.width <= 0 || rect.height <= 0 || data.fontSize <= 0) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }

    final locale = _resolveLocale(localeTag);
    final layout = layoutText(
      data: data,
      maxWidth: rect.width,
      minWidth: rect.width,
      widthBasis: TextWidthBasis.parent,
      locale: locale,
    );
    final localOrigin = DrawPoint(
      x: -rect.width / 2,
      y:
          -rect.height / 2 +
          _resolveVerticalOffset(
            containerHeight: rect.height,
            textHeight: layout.size.height,
            verticalAlign: data.verticalAlign,
          ),
    );

    final localScene = SceneBuilder();
    final text = data.text.isEmpty ? ' ' : data.text;
    if (hasBackground) {
      final backgroundPath = _buildTextBackgroundPath(
        layout: layout,
        text: text,
        localOrigin: localOrigin,
        cornerRadius: data.cornerRadius,
      );
      if (backgroundPath.commands.isNotEmpty) {
        if (data.fillStyle == FillStyle.solid) {
          localScene.addPathFill(
            path: backgroundPath,
            colorArgb: backgroundColorArgb,
          );
        } else {
          final hatch = _resolveTextHatchStyle(fontSize: data.fontSize);
          localScene.addHatchPathFill(
            path: backgroundPath,
            clipBounds: _localClipBounds(rect),
            colorArgb: backgroundColorArgb,
            lineWidth: hatch.lineWidth,
            spacing: hatch.spacing,
            angleRadians: _lineFillAngle,
            pattern: data.fillStyle == FillStyle.crossLine
                ? RenderHatchPattern.crossLine
                : RenderHatchPattern.line,
          );
        }
      }
    }
    if (hasTextFill || hasTextStroke) {
      localScene.addTextRun(
        text: text,
        origin: localOrigin,
        fontSize: data.fontSize,
        colorArgb: textColorArgb,
        fontFamily: data.fontFamily,
        strokeColorArgb: hasTextStroke ? strokeColorArgb : null,
        strokeWidth: hasTextStroke ? data.strokeWidth : 0,
        align: _toRenderTextAlign(data.horizontalAlign),
        maxWidth: rect.width,
      );
    }

    final builder = SceneBuilder()
      ..addTransform(
        child: localScene.build(),
        translate: element.center,
        rotation: element.rotation,
      );
    return builder.build(cullRect: element.rect);
  }

  static int _alphaOf(int argb) => (argb >>> 24) & 0xFF;

  static int _applyElementOpacity({
    required int argb,
    required double elementOpacity,
  }) {
    final baseAlpha = (argb >>> 24) & 0xFF;
    final scaledAlpha = (baseAlpha * elementOpacity.clamp(0.0, 1.0))
        .round()
        .clamp(0, 255);
    return (scaledAlpha << 24) | (argb & 0x00FFFFFF);
  }

  static double _resolveVerticalOffset({
    required double containerHeight,
    required double textHeight,
    required TextVerticalAlign verticalAlign,
  }) {
    final rawOffset = switch (verticalAlign) {
      TextVerticalAlign.top => 0.0,
      TextVerticalAlign.center => (containerHeight - textHeight) / 2,
      TextVerticalAlign.bottom => containerHeight - textHeight,
    };
    if (!rawOffset.isFinite || rawOffset <= 0) {
      return 0;
    }
    return rawOffset;
  }

  static RenderPath _buildTextBackgroundPath({
    required TextLayoutMetrics layout,
    required String text,
    required DrawPoint localOrigin,
    required double cornerRadius,
  }) {
    final boxes = layout.paragraph.getBoxesForRange(
      0,
      text.length,
      boxHeightStyle: ui.BoxHeightStyle.strut,
    );
    if (boxes.isEmpty) {
      return const RenderPath(<RenderPathCommand>[]);
    }

    final horizontalPadding = resolveTextBackgroundHorizontalPadding(
      layout.lineHeight,
    );
    final verticalPadding = resolveTextBackgroundVerticalPadding(
      layout.lineHeight,
    );
    final commands = <RenderPathCommand>[];
    for (final box in boxes) {
      final left = localOrigin.x + box.left - horizontalPadding;
      final top = localOrigin.y + box.top - verticalPadding;
      final right = localOrigin.x + box.right + horizontalPadding;
      final bottom = localOrigin.y + box.bottom + verticalPadding;
      final width = right - left;
      final height = bottom - top;
      if (width <= 0 ||
          height <= 0 ||
          !width.isFinite ||
          !height.isFinite ||
          !left.isFinite ||
          !top.isFinite) {
        continue;
      }
      final radius = _clampCornerRadius(cornerRadius, width, height);
      commands.addAll(
        radius <= 0
            ? _rectPathCommands(
                left: left,
                top: top,
                right: right,
                bottom: bottom,
              )
            : _roundedRectPathCommands(
                left: left,
                top: top,
                right: right,
                bottom: bottom,
                radius: radius,
              ),
      );
    }
    if (commands.isEmpty) {
      return const RenderPath(<RenderPathCommand>[]);
    }
    return RenderPath(commands);
  }

  static double _clampCornerRadius(
    double cornerRadius,
    double width,
    double height,
  ) {
    if (cornerRadius <= 0) {
      return 0;
    }
    final maxRadius = (width < height ? width : height) / 2;
    if (cornerRadius > maxRadius) {
      return maxRadius;
    }
    return cornerRadius;
  }

  static DrawRect _localClipBounds(DrawRect rect) => DrawRect(
    minX: -rect.width / 2,
    minY: -rect.height / 2,
    maxX: rect.width / 2,
    maxY: rect.height / 2,
  );

  static ({double lineWidth, double spacing}) _resolveTextHatchStyle({
    required double fontSize,
  }) {
    final equivalentStrokeWidth = fontSize / 42;
    final lineWidth = (1 + (equivalentStrokeWidth - 1) * 0.6).clamp(0.5, 3.0);
    final spacing = (lineWidth * _lineToSpacingRatio).clamp(3.0, 18.0);
    return (lineWidth: lineWidth, spacing: spacing);
  }

  static List<RenderPathCommand> _rectPathCommands({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) => <RenderPathCommand>[
    RenderMoveTo(DrawPoint(x: left, y: top)),
    RenderLineTo(DrawPoint(x: right, y: top)),
    RenderLineTo(DrawPoint(x: right, y: bottom)),
    RenderLineTo(DrawPoint(x: left, y: bottom)),
    const RenderClosePath(),
  ];

  static List<RenderPathCommand> _roundedRectPathCommands({
    required double left,
    required double top,
    required double right,
    required double bottom,
    required double radius,
  }) {
    final controlOffset = radius * _kappa;
    return <RenderPathCommand>[
      RenderMoveTo(DrawPoint(x: left + radius, y: top)),
      RenderLineTo(DrawPoint(x: right - radius, y: top)),
      RenderCubicTo(
        control1: DrawPoint(x: right - radius + controlOffset, y: top),
        control2: DrawPoint(x: right, y: top + radius - controlOffset),
        end: DrawPoint(x: right, y: top + radius),
      ),
      RenderLineTo(DrawPoint(x: right, y: bottom - radius)),
      RenderCubicTo(
        control1: DrawPoint(x: right, y: bottom - radius + controlOffset),
        control2: DrawPoint(x: right - radius + controlOffset, y: bottom),
        end: DrawPoint(x: right - radius, y: bottom),
      ),
      RenderLineTo(DrawPoint(x: left + radius, y: bottom)),
      RenderCubicTo(
        control1: DrawPoint(x: left + radius - controlOffset, y: bottom),
        control2: DrawPoint(x: left, y: bottom - radius + controlOffset),
        end: DrawPoint(x: left, y: bottom - radius),
      ),
      RenderLineTo(DrawPoint(x: left, y: top + radius)),
      RenderCubicTo(
        control1: DrawPoint(x: left, y: top + radius - controlOffset),
        control2: DrawPoint(x: left + radius - controlOffset, y: top),
        end: DrawPoint(x: left + radius, y: top),
      ),
      const RenderClosePath(),
    ];
  }

  static RenderTextAlign _toRenderTextAlign(TextHorizontalAlign align) {
    switch (align) {
      case TextHorizontalAlign.left:
        return RenderTextAlign.left;
      case TextHorizontalAlign.center:
        return RenderTextAlign.center;
      case TextHorizontalAlign.right:
        return RenderTextAlign.right;
    }
  }

  static ui.Locale? _resolveLocale(String? localeTag) {
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

    return ui.Locale.fromSubtags(
      languageCode: languageCode,
      scriptCode: scriptCode,
      countryCode: countryCode,
    );
  }
}
