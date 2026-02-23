import '../../config/draw_config.dart';

/// Whether [config] produces visible watermark pixels.
bool isWatermarkVisible(WatermarkConfig config) {
  if (config.text.trim().isEmpty) {
    return false;
  }

  // At 8-bit precision an alpha below 1/255 ~= 0.004 maps to zero.
  return config.color.a * config.opacity >= 0.004;
}
