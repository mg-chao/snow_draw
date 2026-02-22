import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import '../../core/typed_element_scene_encoder.dart';
import '../shared/scene_encoder_path_utils.dart';
import '../shared/scene_encoder_style_utils.dart';
import 'text_data.dart';
import 'text_layout.dart';

/// Encodes text elements into backend-agnostic scene primitives.
///
/// Supports fill/stroke text runs and all text background fill styles.
final class TextSceneEncoder extends TypedElementSceneEncoder<TextData> {
  /// Creates a text scene encoder.
  const TextSceneEncoder();

  @override
  RenderScene encodeTypedScene({
    required ElementState element,
    required TextData data,
    String? localeTag,
    TextMetricsService? textMetricsService,
  }) {
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
      return emptyRenderScene;
    }

    final rect = element.rect;
    if (rect.width <= 0 || rect.height <= 0 || data.fontSize <= 0) {
      return emptyRenderScene;
    }

    final layout = layoutSceneText(
      data: data,
      width: rect.width,
      localeTag: localeTag,
      textMetricsService: textMetricsService ?? defaultTextMetricsService,
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
            angleRadians: defaultHatchAngleRadians,
            pattern: resolveHatchPattern(data.fillStyle),
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

    return composeElementScene(
      element: element,
      localScene: localScene.build(),
    );
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
      final radius = clampRoundedRectCornerRadius(
        cornerRadius: cornerRadius,
        width: width,
        height: height,
      );
      commands.addAll(
        radius <= 0
            ? buildRectPathCommands(
                left: left,
                top: top,
                right: right,
                bottom: bottom,
              )
            : buildRoundedRectPathCommands(
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
