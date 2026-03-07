import 'package:snow_draw_engine/snow_draw_engine.dart';

import 'flutter_text_layout.dart';

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
      locale: resolveTextLocale(request.localeTag),
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
}

/// Shared default Flutter text metrics service for backend callers.
const TextMetricsService flutterTextMetricsService =
    FlutterTextMetricsService();
