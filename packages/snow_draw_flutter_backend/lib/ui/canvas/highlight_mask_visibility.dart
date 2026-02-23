import 'package:snow_draw_core/snow_draw_core.dart';

enum HighlightMaskLayer { none, dynamicLayer }

HighlightMaskLayer resolveHighlightMaskLayer({
  required bool hasHighlights,
  required HighlightMaskConfig config,
}) {
  if (!hasHighlights || config.maskOpacity <= 0) {
    return HighlightMaskLayer.none;
  }
  return HighlightMaskLayer.dynamicLayer;
}
