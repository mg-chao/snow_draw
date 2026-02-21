import 'dart:ui';

const _bindingHighlightStrokeWidth = 6.0;
const _bindingHighlightAlpha = 0.32;

double resolveBindingHighlightStrokeWidth(double scale) {
  final effectiveScale = scale == 0 ? 1.0 : scale;
  return _bindingHighlightStrokeWidth / effectiveScale;
}

Paint createBindingHighlightPaint({
  required Color color,
  required double scale,
}) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = resolveBindingHighlightStrokeWidth(scale)
  ..color = color.withValues(alpha: _bindingHighlightAlpha)
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

Rect resolveBindingHighlightOuterRect(Rect rect, double strokeWidth) {
  final halfStroke = strokeWidth * 0.5;
  if (halfStroke <= 0) {
    return rect;
  }
  return rect.inflate(halfStroke);
}

double resolveBindingHighlightOuterRadius(double radius, double strokeWidth) {
  final halfStroke = strokeWidth * 0.5;
  if (halfStroke <= 0) {
    return radius;
  }
  return radius + halfStroke;
}
