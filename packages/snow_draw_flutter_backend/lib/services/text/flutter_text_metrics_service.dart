import 'dart:ui' as ui;

import 'package:snow_draw_core/draw/elements/types/text/text_layout.dart';
import 'package:snow_draw_core/draw/services/text/text_metrics_service.dart';

/// Flutter-backed text metrics service used by app/backend boundaries.
final class FlutterTextMetricsService implements TextMetricsService {
  /// Creates a Flutter text metrics service.
  const FlutterTextMetricsService();

  @override
  TextMetrics measure(TextLayoutRequest request) {
    final layout = layoutText(
      data: request.data,
      maxWidth: request.maxWidth,
      minWidth: request.minWidth,
      locale: _resolveLocale(request.localeTag),
      isResizing: request.isResizing,
    );
    final lines = layout.lineMetrics
        .map((line) => TextLineMetrics(width: line.width, height: line.height))
        .toList(growable: false);

    return TextMetrics(
      width: layout.size.width,
      height: layout.size.height,
      lineHeight: layout.lineHeight,
      lines: lines,
    );
  }

  @override
  void clearCaches() {
    clearTextLayoutCaches();
  }

  static ui.Locale? _resolveLocale(String? localeTag) {
    if (localeTag == null || localeTag.isEmpty) {
      return null;
    }
    final parts = localeTag
        .split(RegExp('[-_]'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return null;
    }

    final languageCode = parts.first.toLowerCase();
    if (!RegExp(r'^[a-z]{2,8}$').hasMatch(languageCode)) {
      return null;
    }

    String? scriptCode;
    String? countryCode;
    for (final part in parts.skip(1)) {
      if (scriptCode == null && part.length == 4) {
        final normalizedScript =
            '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
        if (!RegExp(r'^[A-Z][a-z]{3}$').hasMatch(normalizedScript)) {
          return null;
        }
        scriptCode = normalizedScript;
        continue;
      }
      if (countryCode == null && (part.length == 2 || part.length == 3)) {
        final normalizedCountry = part.toUpperCase();
        if (!RegExp(r'^[A-Z]{2}$|^\d{3}$').hasMatch(normalizedCountry)) {
          return null;
        }
        countryCode = normalizedCountry;
      }
    }

    return ui.Locale.fromSubtags(
      languageCode: languageCode,
      scriptCode: scriptCode,
      countryCode: countryCode,
    );
  }
}

/// Shared default Flutter text metrics service for backend callers.
const TextMetricsService flutterTextMetricsService =
    FlutterTextMetricsService();
