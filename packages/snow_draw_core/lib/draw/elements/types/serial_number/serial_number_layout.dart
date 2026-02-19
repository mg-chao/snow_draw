import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../utils/lru_cache.dart';
import 'serial_number_data.dart';

const _serialNumberTextHeightBehavior = TextHeightBehavior();
const TextScaler _serialNumberTextScaler = TextScaler.noScaling;
const _serialNumberPaddingFactor = 0.26;
const _textGeometryCacheMaxEntries = 64;
const _textPainterCacheMaxEntries = 192;
const double _canonicalSerialNumberFontSize =
    ConfigDefaults.defaultSerialNumberFontSize;

@immutable
class SerialNumberTextLayout {
  const SerialNumberTextLayout({
    required this.painter,
    required this.size,
    required this.lineHeight,
    required this.visualBounds,
    required this.paintScale,
  });

  final TextPainter painter;
  final Size size;
  final double lineHeight;
  final Rect? visualBounds;
  final double paintScale;
}

/// Cache key for serial-number text geometry.
///
/// Color and font-size are intentionally excluded because neither affects the
/// canonical glyph geometry. Font-size is applied as a paint-time scale.
@immutable
class _TextGeometryKey {
  const _TextGeometryKey({
    required this.number,
    required this.fontFamily,
    required this.locale,
  });

  final int number;
  final String? fontFamily;
  final Locale? locale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TextGeometryKey &&
          other.number == number &&
          other.fontFamily == fontFamily &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(number, fontFamily, locale);
}

/// Cache key for color-specific [TextPainter] instances.
@immutable
class _TextPainterKey {
  const _TextPainterKey({required this.geometryKey, required this.color});

  final _TextGeometryKey geometryKey;
  final Color color;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TextPainterKey &&
          other.geometryKey == geometryKey &&
          other.color == color;

  @override
  int get hashCode => Object.hash(geometryKey, color);
}

@immutable
class _TextGeometry {
  const _TextGeometry({
    required this.size,
    required this.lineHeight,
    required this.visualBounds,
  });

  final Size size;
  final double lineHeight;
  final Rect? visualBounds;
}

final _textGeometryCache = LruCache<_TextGeometryKey, _TextGeometry>(
  maxEntries: _textGeometryCacheMaxEntries,
);
final _textPainterCache = LruCache<_TextPainterKey, TextPainter>(
  maxEntries: _textPainterCacheMaxEntries,
);

var _textGeometryBuildCount = 0;
var _textPainterBuildCount = 0;

/// Clears cached serial-number text layouts.
void clearSerialNumberTextLayoutCache() {
  _textGeometryCache.clear();
  _textPainterCache.clear();
  _textGeometryBuildCount = 0;
  _textPainterBuildCount = 0;
}

/// Cache diagnostics for serial-number text layout.
@immutable
class SerialNumberLayoutCacheStats {
  const SerialNumberLayoutCacheStats({
    required this.geometryBuildCount,
    required this.painterBuildCount,
    required this.geometryCacheEntries,
    required this.painterCacheEntries,
  });

  final int geometryBuildCount;
  final int painterBuildCount;
  final int geometryCacheEntries;
  final int painterCacheEntries;
}

@visibleForTesting
SerialNumberLayoutCacheStats debugSerialNumberLayoutCacheStats() =>
    SerialNumberLayoutCacheStats(
      geometryBuildCount: _textGeometryBuildCount,
      painterBuildCount: _textPainterBuildCount,
      geometryCacheEntries: _textGeometryCache.length,
      painterCacheEntries: _textPainterCache.length,
    );

@visibleForTesting
void resetSerialNumberLayoutCacheStats() {
  _textGeometryBuildCount = 0;
  _textPainterBuildCount = 0;
}

SerialNumberTextLayout layoutSerialNumberText({
  required SerialNumberData data,
  Color? colorOverride,
  Locale? locale,
}) {
  final sanitizedFamily = _sanitizeFontFamily(data.fontFamily);
  final fontScale = _resolveSerialNumberFontScale(data.fontSize);
  final geometryKey = _TextGeometryKey(
    number: data.number,
    fontFamily: sanitizedFamily,
    locale: locale,
  );
  final color = colorOverride ?? data.color;
  final painterKey = _TextPainterKey(geometryKey: geometryKey, color: color);

  final cachedGeometry = _textGeometryCache.get(geometryKey);
  final cachedPainter = _textPainterCache.get(painterKey);
  if (cachedGeometry != null && cachedPainter != null) {
    return _buildScaledTextLayout(
      painter: cachedPainter,
      geometry: cachedGeometry,
      fontScale: fontScale,
    );
  }

  final text = geometryKey.number.toString();
  final painter =
      cachedPainter ??
      _cacheTextPainter(
        key: painterKey,
        text: text,
        sanitizedFamily: sanitizedFamily,
        locale: geometryKey.locale,
        color: color,
      );
  final geometry =
      cachedGeometry ??
      _cacheTextGeometry(key: geometryKey, text: text, painter: painter);

  return _buildScaledTextLayout(
    painter: painter,
    geometry: geometry,
    fontScale: fontScale,
  );
}

SerialNumberTextLayout _buildScaledTextLayout({
  required TextPainter painter,
  required _TextGeometry geometry,
  required double fontScale,
}) {
  if (_doubleEquals(fontScale, 1)) {
    return SerialNumberTextLayout(
      painter: painter,
      size: geometry.size,
      lineHeight: geometry.lineHeight,
      visualBounds: geometry.visualBounds,
      paintScale: 1,
    );
  }

  return SerialNumberTextLayout(
    painter: painter,
    size: _scaleSize(geometry.size, fontScale),
    lineHeight: geometry.lineHeight * fontScale,
    visualBounds: _scaleRect(geometry.visualBounds, fontScale),
    paintScale: fontScale,
  );
}

Size _scaleSize(Size size, double scale) =>
    Size(size.width * scale, size.height * scale);

Rect? _scaleRect(Rect? rect, double scale) {
  if (rect == null) {
    return null;
  }
  return Rect.fromLTRB(
    rect.left * scale,
    rect.top * scale,
    rect.right * scale,
    rect.bottom * scale,
  );
}

_TextGeometry _cacheTextGeometry({
  required _TextGeometryKey key,
  required String text,
  required TextPainter painter,
}) {
  _textGeometryBuildCount += 1;
  final geometry = _buildTextGeometry(text: text, painter: painter);
  _textGeometryCache.put(key, geometry);
  return geometry;
}

TextPainter _cacheTextPainter({
  required _TextPainterKey key,
  required String text,
  required String? sanitizedFamily,
  required Locale? locale,
  required Color color,
}) {
  _textPainterBuildCount += 1;
  final painter = _buildTextPainter(
    text: text,
    sanitizedFamily: sanitizedFamily,
    locale: locale,
    color: color,
  );
  _textPainterCache.put(key, painter);
  return painter;
}

_TextGeometry _buildTextGeometry({
  required String text,
  required TextPainter painter,
}) {
  final metrics = painter.computeLineMetrics();
  final lineHeight = metrics.isNotEmpty
      ? metrics.first.height
      : painter.preferredLineHeight;
  return _TextGeometry(
    size: painter.size,
    lineHeight: lineHeight,
    visualBounds: _resolveVisualBounds(painter, text),
  );
}

TextPainter _buildTextPainter({
  required String text,
  required String? sanitizedFamily,
  required Locale? locale,
  required Color color,
}) {
  final style = TextStyle(
    inherit: false,
    color: color,
    fontSize: _canonicalSerialNumberFontSize,
    fontFamily: sanitizedFamily,
    locale: locale,
    textBaseline: TextBaseline.alphabetic,
  );
  return TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    textHeightBehavior: _serialNumberTextHeightBehavior,
    textScaler: _serialNumberTextScaler,
    strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
    locale: locale,
  )..layout();
}

double _resolveSerialNumberFontScale(double fontSize) {
  const baseSize = _canonicalSerialNumberFontSize;
  if (baseSize <= 0 || !baseSize.isFinite) {
    return 1;
  }
  if (!fontSize.isFinite || fontSize <= 0) {
    return 0;
  }
  return fontSize / baseSize;
}

bool _doubleEquals(double a, double b) => (a - b).abs() <= 0.0001;

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
  final boxes = painter.getBoxesForSelection(selection);
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
