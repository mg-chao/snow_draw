import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import 'serial_number_data.dart';

const _serialNumberTextHeightBehavior = TextHeightBehavior();
const TextScaler _serialNumberTextScaler = TextScaler.noScaling;
const _serialNumberPaddingFactor = 0.26;

@immutable
class SerialNumberTextLayout {
  const SerialNumberTextLayout({
    required this.painter,
    required this.size,
    required this.lineHeight,
    required this.visualBounds,
  });

  final TextPainter painter;
  final Size size;
  final double lineHeight;
  final Rect? visualBounds;
}

SerialNumberTextLayout layoutSerialNumberText({
  required SerialNumberData data,
  Color? colorOverride,
  Locale? locale,
}) {
  final text = data.number.toString();
  final style = TextStyle(
    inherit: false,
    color: colorOverride ?? data.color,
    fontSize: data.fontSize,
    fontFamily: _sanitizeFontFamily(data.fontFamily),
    locale: locale,
    textBaseline: TextBaseline.alphabetic,
  );
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    textHeightBehavior: _serialNumberTextHeightBehavior,
    textScaler: _serialNumberTextScaler,
    strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
    locale: locale,
  )..layout();
  final metrics = painter.computeLineMetrics();
  final lineHeight = metrics.isNotEmpty
      ? metrics.first.height
      : painter.preferredLineHeight;
  final visualBounds = _resolveVisualBounds(painter, text);
  return SerialNumberTextLayout(
    painter: painter,
    size: painter.size,
    lineHeight: lineHeight,
    visualBounds: visualBounds,
  );
}

double resolveSerialNumberDiameter({
  required SerialNumberData data,
  double minDiameter = 0,
}) {
  final layout = layoutSerialNumberText(data: data);
  final textHeight = math.max(layout.size.height, layout.lineHeight);
  final baseSize = math.max(layout.size.width, textHeight);
  final padding = layout.lineHeight * _serialNumberPaddingFactor;
  final diameter = baseSize + padding * 2;
  if (diameter.isNaN || diameter.isInfinite) {
    return minDiameter;
  }
  return math.max(diameter, minDiameter);
}

double resolveSerialNumberStrokeWidth({
  required SerialNumberData data,
  double minStrokeWidth = 0,
}) {
  const baseFontSize = ConfigDefaults.defaultSerialNumberFontSize;
  if (baseFontSize <= 0) {
    return math.max(data.strokeWidth, minStrokeWidth);
  }
  final scaled = data.strokeWidth * (data.fontSize / baseFontSize);
  if (scaled.isNaN || scaled.isInfinite) {
    return minStrokeWidth;
  }
  return math.max(scaled, minStrokeWidth);
}

DrawRect resolveSerialNumberRect({
  required DrawPoint origin,
  required SerialNumberData data,
  double minDiameter = 0,
}) {
  final diameter = resolveSerialNumberDiameter(
    data: data,
    minDiameter: minDiameter,
  );
  return DrawRect(
    minX: origin.x,
    minY: origin.y,
    maxX: origin.x + diameter,
    maxY: origin.y + diameter,
  );
}

String? _sanitizeFontFamily(String? fontFamily) {
  final trimmed = fontFamily?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

Rect? _resolveVisualBounds(TextPainter painter, String text) {
  if (text.isEmpty) {
    return null;
  }
  final selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  final boxes = painter.getBoxesForSelection(
    selection,
  );
  if (boxes.isEmpty) {
    return null;
  }
  var left = boxes.first.left;
  var top = boxes.first.top;
  var right = boxes.first.right;
  var bottom = boxes.first.bottom;
  for (var i = 1; i < boxes.length; i++) {
    final box = boxes[i];
    left = math.min(left, box.left);
    top = math.min(top, box.top);
    right = math.max(right, box.right);
    bottom = math.max(bottom, box.bottom);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}
