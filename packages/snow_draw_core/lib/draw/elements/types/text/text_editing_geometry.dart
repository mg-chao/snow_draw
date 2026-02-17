import 'dart:math' as math;

import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import 'text_data.dart';
import 'text_layout.dart';

/// Resolves the initial text editing rect for a newly created text element.
DrawRect resolveInitialTextEditingRect({
  required DrawPoint position,
  required TextData data,
}) {
  final layout = layoutText(data: data, maxWidth: double.infinity);
  final horizontalPadding = resolveTextLayoutHorizontalPadding(
    layout.lineHeight,
  );
  final width = layout.size.width + horizontalPadding * 2;
  final height = math.max(layout.size.height, layout.lineHeight);
  return DrawRect(
    minX: position.x,
    minY: position.y,
    maxX: position.x + width,
    maxY: position.y + height,
  );
}

/// Resolves the text editing rect for the next draft payload.
///
/// The width auto-resizes when [TextData.autoResize] is enabled. Height is
/// clamped to fit actual text content and optionally shrinks when
/// [allowShrinkHeight] is true.
DrawRect resolveTextEditingRect({
  required DrawPoint origin,
  required DrawRect currentRect,
  required TextData data,
  bool allowShrinkHeight = false,
}) {
  final autoResize = data.autoResize;
  final maxWidth = autoResize ? double.infinity : currentRect.width;
  final layout = layoutText(data: data, maxWidth: maxWidth);
  final horizontalPadding = resolveTextLayoutHorizontalPadding(
    layout.lineHeight,
  );
  final minHeight = math.max(layout.lineHeight, layout.size.height);
  final nextWidth = autoResize
      ? layout.size.width + horizontalPadding * 2
      : currentRect.width;
  final shouldShrinkHeight = autoResize || allowShrinkHeight;
  final nextHeight = shouldShrinkHeight
      ? minHeight
      : math.max(currentRect.height, minHeight);

  return DrawRect(
    minX: origin.x,
    minY: origin.y,
    maxX: origin.x + nextWidth,
    maxY: origin.y + nextHeight,
  );
}

/// Resolves rect for auto-resizing text when font metrics change.
DrawRect resolveAutoResizeTextEditingRect({
  required DrawPoint origin,
  required TextData data,
}) {
  final layout = layoutText(data: data, maxWidth: double.infinity);
  final horizontalPadding = resolveTextLayoutHorizontalPadding(
    layout.lineHeight,
  );
  final height = math.max(layout.lineHeight, layout.size.height);
  final width = layout.size.width + horizontalPadding * 2;
  return DrawRect(
    minX: origin.x,
    minY: origin.y,
    maxX: origin.x + width,
    maxY: origin.y + height,
  );
}
