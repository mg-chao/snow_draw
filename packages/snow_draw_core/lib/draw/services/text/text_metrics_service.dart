import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../elements/types/text/text_data.dart';

/// Request payload for text metric computation.
@immutable
class TextLayoutRequest {
  /// Creates a text layout request.
  const TextLayoutRequest({
    required this.data,
    required this.maxWidth,
    this.minWidth,
    this.localeTag,
    this.isResizing = false,
  });

  /// Text style and content to measure.
  final TextData data;

  /// Maximum layout width in logical pixels.
  final double maxWidth;

  /// Optional minimum layout width in logical pixels.
  final double? minWidth;

  /// Optional BCP-47 locale tag.
  final String? localeTag;

  /// Whether measurement is part of a live resize operation.
  final bool isResizing;
}

/// Per-line text metric snapshot.
@immutable
class TextLineMetrics {
  /// Creates text line metrics.
  const TextLineMetrics({required this.width, required this.height});

  /// Line width in logical pixels.
  final double width;

  /// Line height in logical pixels.
  final double height;
}

/// Text metric snapshot used by core geometry logic.
@immutable
class TextMetrics {
  /// Creates text metrics.
  const TextMetrics({
    required this.width,
    required this.height,
    required this.lineHeight,
    required this.lines,
  });

  /// Total laid out width in logical pixels.
  final double width;

  /// Total laid out height in logical pixels.
  final double height;

  /// Effective single-line height in logical pixels.
  final double lineHeight;

  /// Per-line metrics.
  final List<TextLineMetrics> lines;
}

/// Backend-provided text metrics service for geometry-only calculations.
abstract interface class TextMetricsService {
  /// Resolves text metrics for [request].
  TextMetrics measure(TextLayoutRequest request);

  /// Clears cached internal state, if any.
  void clearCaches();
}

/// Pure-Dart fallback used when no backend text metrics service is injected.
///
/// This implementation prioritizes deterministic geometry over typographic
/// fidelity so reducers and tests can run without Flutter text APIs.
final class FallbackTextMetricsService implements TextMetricsService {
  /// Creates a fallback text metrics service.
  const FallbackTextMetricsService();

  static const _defaultFontSize = 14.0;
  static const _lineHeightFactor = 1.2;
  static const _glyphWidthFactor = 0.6;

  @override
  TextMetrics measure(TextLayoutRequest request) {
    final fontSize = _sanitizePositive(
      request.data.fontSize,
      fallback: _defaultFontSize,
    );
    final lineHeight = fontSize * _lineHeightFactor;
    final glyphWidth = math.max(1, fontSize * _glyphWidthFactor).toDouble();
    final text = request.data.text.isEmpty ? ' ' : request.data.text;
    final maxWidth = _resolveMaxWidth(request.maxWidth);

    final lineMetrics = <TextLineMetrics>[];
    for (final line in text.split('\n')) {
      _appendLineMetrics(
        lineMetrics: lineMetrics,
        line: line,
        glyphWidth: glyphWidth,
        lineHeight: lineHeight,
        maxWidth: maxWidth,
      );
    }
    if (lineMetrics.isEmpty) {
      lineMetrics.add(TextLineMetrics(width: glyphWidth, height: lineHeight));
    }

    var width = 0.0;
    for (final line in lineMetrics) {
      if (line.width > width) {
        width = line.width;
      }
    }

    final minWidth = request.minWidth;
    if (minWidth != null && minWidth.isFinite && minWidth > 0) {
      final cappedMinWidth = maxWidth.isFinite
          ? math.min(minWidth, maxWidth)
          : minWidth;
      if (width < cappedMinWidth) {
        width = cappedMinWidth;
      }
    }
    width = _sanitizePositive(width, fallback: glyphWidth);

    final height = _sanitizePositive(
      lineHeight * lineMetrics.length,
      fallback: lineHeight,
    );

    return TextMetrics(
      width: width,
      height: height,
      lineHeight: lineHeight,
      lines: List<TextLineMetrics>.unmodifiable(lineMetrics),
    );
  }

  @override
  void clearCaches() {
    // No-op: fallback metrics service does not allocate native/layout caches.
  }

  static void _appendLineMetrics({
    required List<TextLineMetrics> lineMetrics,
    required String line,
    required double glyphWidth,
    required double lineHeight,
    required double maxWidth,
  }) {
    final graphemeCount = line.isEmpty ? 1 : line.runes.length;
    final rawWidth = _sanitizePositive(
      graphemeCount * glyphWidth,
      fallback: glyphWidth,
    );

    if (!maxWidth.isFinite) {
      lineMetrics.add(TextLineMetrics(width: rawWidth, height: lineHeight));
      return;
    }

    final wraps = math.max(1, (rawWidth / maxWidth).ceil());
    for (var i = 0; i < wraps; i++) {
      final remaining = rawWidth - (maxWidth * i);
      final lineWidth = i == wraps - 1
          ? _sanitizePositive(remaining, fallback: math.min(rawWidth, maxWidth))
          : maxWidth;
      lineMetrics.add(TextLineMetrics(width: lineWidth, height: lineHeight));
    }
  }

  static double _resolveMaxWidth(double maxWidth) {
    if (!maxWidth.isFinite) {
      return double.infinity;
    }
    if (maxWidth <= 0) {
      return 1;
    }
    return maxWidth;
  }

  static double _sanitizePositive(double value, {required double fallback}) {
    if (value.isFinite && value > 0) {
      return value;
    }
    return fallback;
  }
}

/// Shared default text metrics service used by core reducers.
const TextMetricsService defaultTextMetricsService =
    FallbackTextMetricsService();

TextMetricsService _sceneTextMetricsService = defaultTextMetricsService;

/// Shared text metrics service used by scene encoders.
///
/// Defaults to [defaultTextMetricsService]. Integrations can override this
/// to keep scene text placement aligned with runtime renderer metrics.
TextMetricsService get sceneTextMetricsService => _sceneTextMetricsService;

/// Configures [sceneTextMetricsService].
///
/// Use this when the runtime renderer has a more accurate metrics service
/// than the pure-Dart fallback.
void configureSceneTextMetricsService(TextMetricsService textMetricsService) {
  _sceneTextMetricsService = textMetricsService;
}

/// Resets [sceneTextMetricsService] back to the default fallback service.
void resetSceneTextMetricsService() {
  _sceneTextMetricsService = defaultTextMetricsService;
}
