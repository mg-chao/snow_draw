import 'package:snow_draw_core/draw/config/draw_config.dart';

enum HighlightMaskLayer { none, staticLayer, dynamicLayer }

HighlightMaskLayer resolveHighlightMaskLayer({
  required bool hasHighlights,
  required bool hasDynamicContent,
  required bool hasDynamicHighlights,
  required HighlightMaskConfig config,
}) {
  if (!hasHighlights || config.maskOpacity <= 0) {
    return HighlightMaskLayer.none;
  }

  if (hasDynamicContent || hasDynamicHighlights) {
    return HighlightMaskLayer.dynamicLayer;
  }

  return HighlightMaskLayer.staticLayer;
}
