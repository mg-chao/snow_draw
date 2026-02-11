import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import 'text_data.dart';
import 'text_layout.dart';

DrawRect clampTextRectToLayout({
  required DrawRect rect,
  required DrawRect startRect,
  required DrawPoint anchor,
  required TextData data,
  bool keepCenter = false,
}) {
  final initialLayout = layoutText(data: data, maxWidth: rect.width);
  final horizontalPadding = resolveTextLayoutHorizontalPadding(
    initialLayout.lineHeight,
  );
  final minWidth = _resolveMinWidth(data) + horizontalPadding * 2;
  final widthForLayout = rect.width < minWidth ? minWidth : rect.width;
  final layout = widthForLayout == rect.width
      ? initialLayout
      : layoutText(data: data, maxWidth: widthForLayout);
  final minHeight = resolveTextLayoutHeight(layout);

  var minX = rect.minX;
  var maxX = rect.maxX;
  var minY = rect.minY;
  var maxY = rect.maxY;

  if (rect.width < minWidth) {
    if (keepCenter) {
      final centerX = rect.centerX;
      minX = centerX - minWidth / 2;
      maxX = centerX + minWidth / 2;
    } else if (anchor.x <= rect.minX) {
      minX = rect.minX;
      maxX = rect.minX + minWidth;
    } else if (anchor.x >= rect.maxX) {
      maxX = rect.maxX;
      minX = rect.maxX - minWidth;
    } else {
      final ratio = _anchorRatio(anchor.x, startRect.minX, startRect.maxX);
      minX = anchor.x - minWidth * ratio;
      maxX = anchor.x + minWidth * (1 - ratio);
    }
  }

  if (rect.height != minHeight) {
    // Always keep the top edge fixed when height changes
    minY = rect.minY;
    maxY = rect.minY + minHeight;
  }

  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

double resolveTextLayoutHeight(TextLayoutMetrics layout) => _sanitizeExtent(
  layout.lineHeight > layout.size.height
      ? layout.lineHeight
      : layout.size.height,
);

double fitTextFontSizeToHeight({
  required TextData data,
  required double targetHeight,
  required double maxWidth,
  double minFontSize = 1.0,
  int maxIterations = 8,
  double tolerance = 0.01,
}) {
  final safeWidth = _sanitizeExtent(maxWidth);
  final safeTargetHeight = _sanitizeExtent(targetHeight);
  final safeMinFontSize = _sanitizeExtent(minFontSize);
  var baseFontSize = _sanitizeExtent(data.fontSize);
  if (baseFontSize < safeMinFontSize) {
    baseFontSize = safeMinFontSize;
  }

  final baseHeight = _resolveHeight(
    data: data,
    fontSize: baseFontSize,
    maxWidth: safeWidth,
  );
  if ((baseHeight - safeTargetHeight).abs() <= tolerance) {
    return baseFontSize;
  }

  final minHeight = _resolveHeight(
    data: data,
    fontSize: safeMinFontSize,
    maxWidth: safeWidth,
  );
  if (minHeight >= safeTargetHeight) {
    return safeMinFontSize;
  }

  // Use a linear estimate to seed the binary search with a tighter
  // initial range. Font height scales roughly linearly with font size
  // for single-line text, so this often lands close on the first try.
  var low = safeMinFontSize;
  var high = baseFontSize < safeTargetHeight ? safeTargetHeight : baseFontSize;
  var highHeight = high == baseFontSize
      ? baseHeight
      : _resolveHeight(data: data, fontSize: high, maxWidth: safeWidth);

  if (highHeight < safeTargetHeight) {
    var attempts = 0;
    while (highHeight < safeTargetHeight && attempts < maxIterations) {
      high *= 1.5;
      highHeight = _resolveHeight(
        data: data,
        fontSize: high,
        maxWidth: safeWidth,
      );
      attempts += 1;
    }
    if (highHeight < safeTargetHeight) {
      return high;
    }
  }

  final lowHeight = minHeight;
  final span = highHeight - lowHeight;
  if (span > 0) {
    final ratio = (safeTargetHeight - lowHeight) / span;
    final estimate = low + (high - low) * ratio;
    final estHeight = _resolveHeight(
      data: data,
      fontSize: estimate,
      maxWidth: safeWidth,
    );
    if ((estHeight - safeTargetHeight).abs() <= tolerance) {
      return estimate;
    }
    // Narrow the search range based on the estimate.
    if (estHeight > safeTargetHeight) {
      high = estimate;
    } else {
      low = estimate;
    }
  }

  for (var i = 0; i < maxIterations; i++) {
    final mid = (low + high) / 2;
    final height = _resolveHeight(
      data: data,
      fontSize: mid,
      maxWidth: safeWidth,
    );
    if ((height - safeTargetHeight).abs() <= tolerance) {
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

double _resolveMinWidth(TextData data) {
  final layout = layoutText(data: data, maxWidth: 1);
  var maxLineWidth = 0.0;
  for (final line in layout.lineMetrics) {
    if (line.width > maxLineWidth) {
      maxLineWidth = line.width;
    }
  }
  if (maxLineWidth.isNaN || maxLineWidth.isInfinite || maxLineWidth <= 0) {
    return _sanitizeExtent(layout.size.width);
  }
  return maxLineWidth;
}

double _anchorRatio(double anchor, double min, double max) {
  final span = max - min;
  if (span <= 0 || span.isNaN || span.isInfinite) {
    return 0.5;
  }
  final raw = (anchor - min) / span;
  if (raw.isNaN || raw.isInfinite) {
    return 0.5;
  }
  if (raw < 0) {
    return 0;
  }
  if (raw > 1) {
    return 1;
  }
  return raw;
}

double _sanitizeExtent(double value) {
  if (value <= 0 || value.isNaN || value.isInfinite) {
    return 1;
  }
  return value;
}

double _resolveHeight({
  required TextData data,
  required double fontSize,
  required double maxWidth,
}) {
  final layout = layoutText(
    data: data.copyWith(fontSize: fontSize),
    maxWidth: maxWidth,
  );
  return resolveTextLayoutHeight(layout);
}
