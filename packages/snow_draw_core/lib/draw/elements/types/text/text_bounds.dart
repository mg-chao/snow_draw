import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import 'text_data.dart';
import 'text_layout_constants.dart';

DrawRect clampTextRectToLayout({
  required DrawRect rect,
  required DrawRect startRect,
  required DrawPoint anchor,
  required TextData data,
  TextMetricsService textMetricsService = defaultTextMetricsService,
  bool keepCenter = false,
}) {
  final resolvedTextMetricsService = resolveTextMetricsService(
    textMetricsService,
  );
  final baseLayout = resolvedTextMetricsService.measure(
    TextLayoutRequest(data: data, maxWidth: rect.width),
  );
  final horizontalPadding = resolveTextLayoutHorizontalPadding(
    baseLayout.lineHeight,
  );
  final minWidth =
      _resolveMinWidth(data, textMetricsService: resolvedTextMetricsService) +
      horizontalPadding * 2;
  final shouldClampWidth = rect.width < minWidth;

  var minX = rect.minX;
  var maxX = rect.maxX;
  if (shouldClampWidth) {
    if (keepCenter) {
      final halfWidth = minWidth / 2;
      minX = rect.centerX - halfWidth;
      maxX = rect.centerX + halfWidth;
    } else if (anchor.x <= rect.minX) {
      maxX = rect.minX + minWidth;
    } else if (anchor.x >= rect.maxX) {
      minX = rect.maxX - minWidth;
    } else {
      final ratio = _anchorRatio(anchor.x, startRect.minX, startRect.maxX);
      minX = anchor.x - minWidth * ratio;
      maxX = minX + minWidth;
    }
  }

  final layout = shouldClampWidth
      ? resolvedTextMetricsService.measure(
          TextLayoutRequest(data: data, maxWidth: minWidth),
        )
      : baseLayout;
  final minHeight = resolveTextLayoutHeight(layout);

  return DrawRect(
    minX: minX,
    minY: rect.minY,
    maxX: maxX,
    maxY: rect.minY + minHeight,
  );
}

double resolveTextLayoutHeight(TextMetrics layout) => _sanitizeExtent(
  layout.lineHeight > layout.height ? layout.lineHeight : layout.height,
);

double fitTextFontSizeToHeight({
  required TextData data,
  required double targetHeight,
  required double maxWidth,
  TextMetricsService textMetricsService = defaultTextMetricsService,
  double minFontSize = 1.0,
  int maxIterations = 8,
  double tolerance = 0.01,
}) {
  final safeWidth = _sanitizeExtent(maxWidth);
  final safeTargetHeight = _sanitizeExtent(targetHeight);
  final safeMinFontSize = _sanitizeExtent(minFontSize);
  final safeMaxIterations = maxIterations < 1 ? 1 : maxIterations;
  final safeTolerance = tolerance < 0 ? 0.0 : tolerance;
  final sanitizedFontSize = _sanitizeExtent(data.fontSize);
  final baseFontSize = sanitizedFontSize < safeMinFontSize
      ? safeMinFontSize
      : sanitizedFontSize;
  final resolvedTextMetricsService = resolveTextMetricsService(
    textMetricsService,
  );

  final baseHeight = _resolveHeight(
    data: data,
    fontSize: baseFontSize,
    maxWidth: safeWidth,
    textMetricsService: resolvedTextMetricsService,
  );
  if ((baseHeight - safeTargetHeight).abs() <= safeTolerance) {
    return baseFontSize;
  }

  final lowHeight = _resolveHeight(
    data: data,
    fontSize: safeMinFontSize,
    maxWidth: safeWidth,
    textMetricsService: resolvedTextMetricsService,
  );
  if (lowHeight >= safeTargetHeight) {
    return safeMinFontSize;
  }

  var low = safeMinFontSize;
  var high = baseFontSize < safeTargetHeight ? safeTargetHeight : baseFontSize;
  var highHeight = high == baseFontSize
      ? baseHeight
      : _resolveHeight(
          data: data,
          fontSize: high,
          maxWidth: safeWidth,
          textMetricsService: resolvedTextMetricsService,
        );

  if (highHeight < safeTargetHeight) {
    var attempts = 0;
    while (highHeight < safeTargetHeight && attempts < safeMaxIterations) {
      high *= 1.5;
      highHeight = _resolveHeight(
        data: data,
        fontSize: high,
        maxWidth: safeWidth,
        textMetricsService: resolvedTextMetricsService,
      );
      attempts += 1;
    }
    if (highHeight < safeTargetHeight) {
      return high;
    }
  }

  final span = highHeight - lowHeight;
  if (span > 0) {
    final ratio = (safeTargetHeight - lowHeight) / span;
    final estimate = low + (high - low) * ratio;
    final estimateHeight = _resolveHeight(
      data: data,
      fontSize: estimate,
      maxWidth: safeWidth,
      textMetricsService: resolvedTextMetricsService,
    );
    if ((estimateHeight - safeTargetHeight).abs() <= safeTolerance) {
      return estimate;
    }
    if (estimateHeight > safeTargetHeight) {
      high = estimate;
    } else {
      low = estimate;
    }
  }

  for (var i = 0; i < safeMaxIterations; i++) {
    final mid = (low + high) / 2;
    final height = _resolveHeight(
      data: data,
      fontSize: mid,
      maxWidth: safeWidth,
      textMetricsService: resolvedTextMetricsService,
    );
    if ((height - safeTargetHeight).abs() <= safeTolerance) {
      return mid;
    }
    if (height > safeTargetHeight) {
      high = mid;
    } else {
      low = mid;
    }
  }

  return low;
}

double _resolveMinWidth(
  TextData data, {
  required TextMetricsService textMetricsService,
}) {
  final layout = textMetricsService.measure(
    TextLayoutRequest(data: data, maxWidth: 1),
  );
  var maxLineWidth = 0.0;
  for (final line in layout.lines) {
    if (line.width > maxLineWidth) {
      maxLineWidth = line.width;
    }
  }
  if (maxLineWidth <= 0 || !maxLineWidth.isFinite) {
    return _sanitizeExtent(layout.width);
  }
  return _sanitizeExtent(maxLineWidth);
}

double _anchorRatio(double anchor, double min, double max) {
  final span = max - min;
  if (span <= 0 || !span.isFinite) {
    return 0.5;
  }
  final raw = (anchor - min) / span;
  if (!raw.isFinite) {
    return 0.5;
  }
  return raw.clamp(0.0, 1.0);
}

double _sanitizeExtent(double value) =>
    value > 0 && value.isFinite ? value : 1.0;

double _resolveHeight({
  required TextData data,
  required double fontSize,
  required double maxWidth,
  required TextMetricsService textMetricsService,
}) {
  final layout = textMetricsService.measure(
    TextLayoutRequest(
      data: data.copyWith(fontSize: fontSize),
      maxWidth: maxWidth,
    ),
  );
  return resolveTextLayoutHeight(layout);
}
