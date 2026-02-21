import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import 'text_data.dart';

/// Geometry resolved for an in-progress text draft.
///
/// Carries both the target [rect] and the text [layout] used to derive it so
/// callers can reuse metrics instead of recomputing layout again in the same
/// frame.
@immutable
class TextEditingGeometry {
  const TextEditingGeometry({required this.rect, required this.layout});

  final DrawRect rect;
  final TextMetrics layout;
}

/// Resolves the initial text editing rect for a newly created text element.
DrawRect resolveInitialTextEditingRect({
  required DrawPoint position,
  required TextData data,
  TextMetricsService textMetricsService = defaultTextMetricsService,
  String? localeTag,
}) => resolveInitialTextEditingGeometry(
  position: position,
  data: data,
  textMetricsService: textMetricsService,
  localeTag: localeTag,
).rect;

/// Resolves geometry for the initial text editing rect of a newly created text
/// element.
TextEditingGeometry resolveInitialTextEditingGeometry({
  required DrawPoint position,
  required TextData data,
  TextMetricsService textMetricsService = defaultTextMetricsService,
  String? localeTag,
}) => _resolveContentSizedTextEditingGeometry(
  origin: position,
  data: data,
  textMetricsService: textMetricsService,
  localeTag: localeTag,
);

/// Resolves the text editing rect for the next draft payload.
///
/// The width auto-resizes when [TextData.autoResize] is enabled. Height is
/// clamped to fit actual text content and optionally shrinks when
/// [allowShrinkHeight] is true.
DrawRect resolveTextEditingRect({
  required DrawPoint origin,
  required DrawRect currentRect,
  required TextData data,
  TextMetricsService textMetricsService = defaultTextMetricsService,
  bool allowShrinkHeight = false,
  String? localeTag,
}) => resolveTextEditingGeometry(
  origin: origin,
  currentRect: currentRect,
  data: data,
  textMetricsService: textMetricsService,
  allowShrinkHeight: allowShrinkHeight,
  localeTag: localeTag,
).rect;

/// Resolves geometry for an in-progress text edit draft.
///
/// The returned [TextEditingGeometry.layout] can be reused by callers that need
/// text metrics in addition to the resulting [TextEditingGeometry.rect].
TextEditingGeometry resolveTextEditingGeometry({
  required DrawPoint origin,
  required DrawRect currentRect,
  required TextData data,
  TextMetricsService textMetricsService = defaultTextMetricsService,
  bool allowShrinkHeight = false,
  String? localeTag,
}) {
  if (data.autoResize) {
    return _resolveContentSizedTextEditingGeometry(
      origin: origin,
      data: data,
      textMetricsService: textMetricsService,
      localeTag: localeTag,
    );
  }

  final layout = textMetricsService.measure(
    TextLayoutRequest(
      data: data,
      maxWidth: currentRect.width,
      localeTag: localeTag,
    ),
  );
  final contentHeight = _resolveContentHeight(layout);
  final nextHeight = allowShrinkHeight
      ? contentHeight
      : math.max(currentRect.height, contentHeight);
  return _buildTextEditingGeometry(
    origin: origin,
    width: currentRect.width,
    height: nextHeight,
    layout: layout,
  );
}

/// Resolves rect for auto-resizing text when font metrics change.
DrawRect resolveAutoResizeTextEditingRect({
  required DrawPoint origin,
  required TextData data,
  TextMetricsService textMetricsService = defaultTextMetricsService,
  String? localeTag,
}) => resolveAutoResizeTextEditingGeometry(
  origin: origin,
  data: data,
  textMetricsService: textMetricsService,
  localeTag: localeTag,
).rect;

/// Resolves geometry for auto-resizing text when font metrics change.
TextEditingGeometry resolveAutoResizeTextEditingGeometry({
  required DrawPoint origin,
  required TextData data,
  TextMetricsService textMetricsService = defaultTextMetricsService,
  String? localeTag,
}) => _resolveContentSizedTextEditingGeometry(
  origin: origin,
  data: data,
  textMetricsService: textMetricsService,
  localeTag: localeTag,
);

TextEditingGeometry _resolveContentSizedTextEditingGeometry({
  required DrawPoint origin,
  required TextData data,
  required TextMetricsService textMetricsService,
  required String? localeTag,
}) {
  final layout = textMetricsService.measure(
    TextLayoutRequest(
      data: data,
      maxWidth: double.infinity,
      localeTag: localeTag,
    ),
  );
  return _buildTextEditingGeometry(
    origin: origin,
    width: _resolveContentWidth(layout),
    height: _resolveContentHeight(layout),
    layout: layout,
  );
}

TextEditingGeometry _buildTextEditingGeometry({
  required DrawPoint origin,
  required double width,
  required double height,
  required TextMetrics layout,
}) => TextEditingGeometry(
  rect: DrawRect(
    minX: origin.x,
    minY: origin.y,
    maxX: origin.x + width,
    maxY: origin.y + height,
  ),
  layout: layout,
);

double _resolveContentWidth(TextMetrics layout) {
  final horizontalPadding = _resolveTextLayoutHorizontalPadding(
    layout.lineHeight,
  );
  return layout.width + horizontalPadding * 2;
}

double _resolveContentHeight(TextMetrics layout) =>
    math.max(layout.height, layout.lineHeight);

double _resolveTextLayoutHorizontalPadding(double lineHeight) {
  final padding = lineHeight * 0.01;
  if (padding.isNaN || padding.isInfinite) {
    return 0;
  }
  return padding;
}
