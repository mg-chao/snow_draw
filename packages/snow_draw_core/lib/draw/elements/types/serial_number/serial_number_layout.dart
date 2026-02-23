import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../../utils/lru_cache.dart';
import '../text/text_data.dart';
import 'serial_number_data.dart';

const _serialNumberPaddingFactor = 0.26;
const _textGeometryCacheMaxEntries = 64;
const _textPainterCacheMaxEntries = 192;
const double _canonicalSerialNumberFontSize =
    ConfigDefaults.defaultSerialNumberFontSize;

/// Lightweight serial-number text size snapshot.
@immutable
class SerialNumberLayoutSize {
  /// Creates a serial-number size snapshot.
  const SerialNumberLayoutSize({required this.width, required this.height});

  /// Width in logical pixels.
  final double width;

  /// Height in logical pixels.
  final double height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SerialNumberLayoutSize &&
          other.width == width &&
          other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// Lightweight visual bounds snapshot in local text coordinates.
@immutable
class SerialNumberVisualBounds {
  /// Creates visual bounds.
  const SerialNumberVisualBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Left edge in local text coordinates.
  final double left;

  /// Top edge in local text coordinates.
  final double top;

  /// Right edge in local text coordinates.
  final double right;

  /// Bottom edge in local text coordinates.
  final double bottom;

  /// Horizontal center in local coordinates.
  double get centerX => (left + right) / 2;

  /// Vertical center in local coordinates.
  double get centerY => (top + bottom) / 2;
}

@immutable
class SerialNumberTextLayout {
  /// Creates serial-number text layout metrics.
  const SerialNumberTextLayout({
    required this.painter,
    required this.size,
    required this.lineHeight,
    required this.visualBounds,
    required this.paintScale,
  });

  /// Stable layout token used for cache identity checks.
  final Object painter;

  /// Unscaled layout size.
  final SerialNumberLayoutSize size;

  /// Unscaled line height.
  final double lineHeight;

  /// Optional visual glyph bounds.
  final SerialNumberVisualBounds? visualBounds;

  /// Paint scale relative to canonical font size.
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
    required this.localeTag,
  });

  final int number;
  final String? fontFamily;
  final String? localeTag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TextGeometryKey &&
          other.number == number &&
          other.fontFamily == fontFamily &&
          other.localeTag == localeTag;

  @override
  int get hashCode => Object.hash(number, fontFamily, localeTag);
}

/// Cache key for color-specific layout tokens.
@immutable
class _TextPainterKey {
  const _TextPainterKey({required this.geometryKey, required this.colorArgb});

  final _TextGeometryKey geometryKey;
  final int colorArgb;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TextPainterKey &&
          other.geometryKey == geometryKey &&
          other.colorArgb == colorArgb;

  @override
  int get hashCode => Object.hash(geometryKey, colorArgb);
}

@immutable
class _TextGeometry {
  const _TextGeometry({
    required this.size,
    required this.lineHeight,
    required this.visualBounds,
  });

  final SerialNumberLayoutSize size;
  final double lineHeight;
  final SerialNumberVisualBounds? visualBounds;
}

final _textGeometryCache = LruCache<_TextGeometryKey, _TextGeometry>(
  maxEntries: _textGeometryCacheMaxEntries,
);
final _textPainterCache = LruCache<_TextPainterKey, Object>(
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
  /// Creates cache stats.
  const SerialNumberLayoutCacheStats({
    required this.geometryBuildCount,
    required this.painterBuildCount,
    required this.geometryCacheEntries,
    required this.painterCacheEntries,
  });

  /// Number of geometry cache misses.
  final int geometryBuildCount;

  /// Number of painter-token cache misses.
  final int painterBuildCount;

  /// Number of geometry cache entries.
  final int geometryCacheEntries;

  /// Number of painter-token cache entries.
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

/// Measures serial-number text with backend-agnostic metrics.
SerialNumberTextLayout layoutSerialNumberText({
  required SerialNumberData data,
  int? colorArgbOverride,
  String? localeTag,
  TextMetricsService textMetricsService = defaultTextMetricsService,
}) {
  final sanitizedFamily = _sanitizeFontFamily(data.fontFamily);
  final resolvedLocaleTag = _normalizeLocaleTag(localeTag);
  final fontScale = _resolveSerialNumberFontScale(data.fontSize);
  final geometryKey = _TextGeometryKey(
    number: data.number,
    fontFamily: sanitizedFamily,
    localeTag: resolvedLocaleTag,
  );
  final colorArgb = colorArgbOverride ?? data.color.toARGB32();
  final painterKey = _TextPainterKey(
    geometryKey: geometryKey,
    colorArgb: colorArgb,
  );
  final painterToken = _textPainterCache.getOrCreate(painterKey, () {
    _textPainterBuildCount += 1;
    return Object();
  });

  final geometry = _textGeometryCache.getOrCreate(geometryKey, () {
    _textGeometryBuildCount += 1;
    return _buildTextGeometry(
      data: data,
      localeTag: resolvedLocaleTag,
      textMetricsService: textMetricsService,
    );
  });

  return _buildScaledTextLayout(
    painterToken: painterToken,
    geometry: geometry,
    fontScale: fontScale,
  );
}

/// Scene-focused serial-number text layout helper.
SerialNumberTextLayout layoutSerialNumberTextForScene({
  required SerialNumberData data,
  required int colorArgb,
  String? localeTag,
  TextMetricsService textMetricsService = defaultTextMetricsService,
}) => layoutSerialNumberText(
  data: data,
  colorArgbOverride: colorArgb,
  localeTag: localeTag,
  textMetricsService: textMetricsService,
);

/// Resolves the visual center of the laid-out serial-number glyphs.
DrawPoint resolveSerialNumberVisualCenter(SerialNumberTextLayout layout) {
  final bounds = layout.visualBounds;
  if (bounds == null) {
    return DrawPoint(x: layout.size.width / 2, y: layout.size.height / 2);
  }
  return DrawPoint(x: bounds.centerX, y: bounds.centerY);
}

SerialNumberTextLayout _buildScaledTextLayout({
  required Object painterToken,
  required _TextGeometry geometry,
  required double fontScale,
}) {
  if (_doubleEquals(fontScale, 1)) {
    return SerialNumberTextLayout(
      painter: painterToken,
      size: geometry.size,
      lineHeight: geometry.lineHeight,
      visualBounds: geometry.visualBounds,
      paintScale: 1,
    );
  }

  return SerialNumberTextLayout(
    painter: painterToken,
    size: _scaleSize(geometry.size, fontScale),
    lineHeight: geometry.lineHeight * fontScale,
    visualBounds: _scaleVisualBounds(geometry.visualBounds, fontScale),
    paintScale: fontScale,
  );
}

SerialNumberLayoutSize _scaleSize(SerialNumberLayoutSize size, double scale) =>
    SerialNumberLayoutSize(
      width: size.width * scale,
      height: size.height * scale,
    );

SerialNumberVisualBounds? _scaleVisualBounds(
  SerialNumberVisualBounds? bounds,
  double scale,
) {
  if (bounds == null) {
    return null;
  }
  return SerialNumberVisualBounds(
    left: bounds.left * scale,
    top: bounds.top * scale,
    right: bounds.right * scale,
    bottom: bounds.bottom * scale,
  );
}

_TextGeometry _buildTextGeometry({
  required SerialNumberData data,
  required String? localeTag,
  required TextMetricsService textMetricsService,
}) {
  final metrics = textMetricsService.measure(
    TextLayoutRequest(
      data: TextData(
        text: data.number.toString(),
        fontSize: _canonicalSerialNumberFontSize,
        fontFamily: _sanitizeFontFamily(data.fontFamily),
        horizontalAlign: TextHorizontalAlign.center,
      ),
      maxWidth: double.infinity,
      localeTag: localeTag,
    ),
  );

  final width = _sanitizeExtent(metrics.width, fallback: 1);
  final lineHeight = _sanitizeExtent(metrics.lineHeight, fallback: 1);
  final height = _sanitizeExtent(metrics.height, fallback: lineHeight);

  return _TextGeometry(
    size: SerialNumberLayoutSize(width: width, height: height),
    lineHeight: lineHeight,
    visualBounds: SerialNumberVisualBounds(
      left: 0,
      top: 0,
      right: width,
      bottom: height,
    ),
  );
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

double _sanitizeExtent(double value, {required double fallback}) {
  if (value.isFinite && value > 0) {
    return value;
  }
  return fallback;
}

double resolveSerialNumberDiameter({
  required SerialNumberData data,
  double minDiameter = 0,
  TextMetricsService textMetricsService = defaultTextMetricsService,
}) {
  final layout = layoutSerialNumberText(
    data: data,
    textMetricsService: textMetricsService,
  );
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
  const baseFontSize = _canonicalSerialNumberFontSize;
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
  TextMetricsService textMetricsService = defaultTextMetricsService,
}) {
  final diameter = resolveSerialNumberDiameter(
    data: data,
    minDiameter: minDiameter,
    textMetricsService: textMetricsService,
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

String? _normalizeLocaleTag(String? localeTag) {
  if (localeTag == null || localeTag.isEmpty) {
    return null;
  }
  final normalized = localeTag.trim();
  if (normalized.isEmpty) {
    return null;
  }
  return normalized;
}
