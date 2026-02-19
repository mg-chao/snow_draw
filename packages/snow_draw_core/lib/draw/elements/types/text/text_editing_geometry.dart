import 'dart:math' as math;
import 'dart:ui' show Locale;

import 'package:meta/meta.dart';

import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import 'text_data.dart';
import 'text_layout.dart';

/// Geometry resolved for an in-progress text draft.
///
/// Carries both the target [rect] and the text [layout] used to derive it so
/// callers can reuse metrics instead of recomputing layout again in the same
/// frame.
@immutable
class TextEditingGeometry {
  const TextEditingGeometry({required this.rect, required this.layout});

  final DrawRect rect;
  final TextLayoutMetrics layout;
}

/// Resolves the initial text editing rect for a newly created text element.
DrawRect resolveInitialTextEditingRect({
  required DrawPoint position,
  required TextData data,
  Locale? locale,
}) => resolveInitialTextEditingGeometry(
  position: position,
  data: data,
  locale: locale,
).rect;

/// Resolves geometry for the initial text editing rect of a newly created text
/// element.
TextEditingGeometry resolveInitialTextEditingGeometry({
  required DrawPoint position,
  required TextData data,
  Locale? locale,
}) {
  final layout = layoutText(
    data: data,
    maxWidth: double.infinity,
    locale: locale,
  );
  final horizontalPadding = resolveTextLayoutHorizontalPadding(
    layout.lineHeight,
  );
  final width = layout.size.width + horizontalPadding * 2;
  final height = math.max(layout.size.height, layout.lineHeight);
  return TextEditingGeometry(
    rect: DrawRect(
      minX: position.x,
      minY: position.y,
      maxX: position.x + width,
      maxY: position.y + height,
    ),
    layout: layout,
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
  Locale? locale,
}) => resolveTextEditingGeometry(
  origin: origin,
  currentRect: currentRect,
  data: data,
  allowShrinkHeight: allowShrinkHeight,
  locale: locale,
).rect;

/// Resolves geometry for an in-progress text edit draft.
///
/// The returned [TextEditingGeometry.layout] can be reused by callers that need
/// text metrics in addition to the resulting [TextEditingGeometry.rect].
TextEditingGeometry resolveTextEditingGeometry({
  required DrawPoint origin,
  required DrawRect currentRect,
  required TextData data,
  bool allowShrinkHeight = false,
  Locale? locale,
}) {
  final autoResize = data.autoResize;
  final maxWidth = autoResize ? double.infinity : currentRect.width;
  final layout = layoutText(data: data, maxWidth: maxWidth, locale: locale);
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

  return TextEditingGeometry(
    rect: DrawRect(
      minX: origin.x,
      minY: origin.y,
      maxX: origin.x + nextWidth,
      maxY: origin.y + nextHeight,
    ),
    layout: layout,
  );
}

/// Resolves rect for auto-resizing text when font metrics change.
DrawRect resolveAutoResizeTextEditingRect({
  required DrawPoint origin,
  required TextData data,
  Locale? locale,
}) => resolveAutoResizeTextEditingGeometry(
  origin: origin,
  data: data,
  locale: locale,
).rect;

/// Resolves geometry for auto-resizing text when font metrics change.
TextEditingGeometry resolveAutoResizeTextEditingGeometry({
  required DrawPoint origin,
  required TextData data,
  Locale? locale,
}) {
  final layout = layoutText(
    data: data,
    maxWidth: double.infinity,
    locale: locale,
  );
  final horizontalPadding = resolveTextLayoutHorizontalPadding(
    layout.lineHeight,
  );
  final height = math.max(layout.lineHeight, layout.size.height);
  final width = layout.size.width + horizontalPadding * 2;
  return TextEditingGeometry(
    rect: DrawRect(
      minX: origin.x,
      minY: origin.y,
      maxX: origin.x + width,
      maxY: origin.y + height,
    ),
    layout: layout,
  );
}
