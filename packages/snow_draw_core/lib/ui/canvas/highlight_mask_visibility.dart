import '../../draw/config/draw_config.dart';

enum HighlightMaskLayer { none, staticLayer, dynamicLayer }

HighlightMaskLayer resolveHighlightMaskLayer({
  required bool hasHighlights,
  required bool hasDynamicContent,
  required HighlightMaskConfig config,
}) {
  if (!hasHighlights) {
    return HighlightMaskLayer.none;
  }
  if (config.maskOpacity <= 0) {
    return HighlightMaskLayer.none;
  }
  return hasDynamicContent
      ? HighlightMaskLayer.dynamicLayer
      : HighlightMaskLayer.staticLayer;
}
