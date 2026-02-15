import '../../draw/config/draw_config.dart';

enum WatermarkLayer { none, staticLayer, dynamicLayer }

WatermarkLayer resolveWatermarkLayer({
  required bool hasDynamicContent,
  required WatermarkConfig config,
}) {
  if (config.opacity <= 0) {
    return WatermarkLayer.none;
  }
  if (config.text.trim().isEmpty) {
    return WatermarkLayer.none;
  }
  if (config.color.a <= 0) {
    return WatermarkLayer.none;
  }
  return hasDynamicContent
      ? WatermarkLayer.dynamicLayer
      : WatermarkLayer.staticLayer;
}
