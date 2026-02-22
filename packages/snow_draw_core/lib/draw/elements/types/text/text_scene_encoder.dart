import 'dart:math' as math;

import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import '../../core/element_scene_encoder.dart';
import '../shared/scene_encoder_style_utils.dart';
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

  @override
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
    TextMetricsService? textMetricsService,
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

    final textColorArgb = applyElementOpacityToArgb(
      argb: data.color.toARGB32(),
      elementOpacity: element.opacity,
    );
    final backgroundColorArgb = applyElementOpacityToArgb(
      argb: data.fillColor.toARGB32(),
      elementOpacity: element.opacity,
    );
    final strokeColorArgb = applyElementOpacityToArgb(
      argb: data.strokeColor.toARGB32(),
      elementOpacity: element.opacity,
    );

    final hasBackground = isArgbVisible(backgroundColorArgb);
    final hasTextStroke =
        isArgbVisible(strokeColorArgb) && data.strokeWidth > 0;
    final hasTextFill = isArgbVisible(textColorArgb);
    if (!hasTextFill && !hasBackground && !hasTextStroke) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }

    final rect = element.rect;
    if (rect.width <= 0 || rect.height <= 0 || data.fontSize <= 0) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }

    final resolvedTextMetricsService =
        textMetricsService ?? sceneTextMetricsService;
    final layout = layoutSceneText(
      data: data,
      width: rect.width,
      localeTag: localeTag,
      textMetricsService: resolvedTextMetricsService,
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
          final hatch = resolveFontHatchStyle(fontSize: data.fontSize);
          localScene.addHatchPathFill(
            path: backgroundPath,
            clipBounds: resolveCenteredLocalClipBounds(rect),
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
    final boxes = resolveTextRangeBoxes(
      layout: layout,
      start: 0,
      end: text.length,
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
}
