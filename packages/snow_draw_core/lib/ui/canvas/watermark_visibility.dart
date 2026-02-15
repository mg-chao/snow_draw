import '../../draw/config/draw_config.dart';

/// Which canvas layer renders the watermark overlay.
enum WatermarkLayer { none, staticLayer, dynamicLayer }

/// Decides which canvas layer should render the watermark.
///
/// Returns [WatermarkLayer.none] when the watermark is effectively
/// invisible (empty text, zero opacity, or imperceptible alpha).
/// This avoids entering the paint path at all for disabled configs.
WatermarkLayer resolveWatermarkLayer({
  required bool hasDynamicContent,
  required WatermarkConfig config,
}) {
  if (config.text.trim().isEmpty) {
    return WatermarkLayer.none;
  }
  if (config.opacity <= 0) {
    return WatermarkLayer.none;
  }
  if (config.color.a <= 0) {
    return WatermarkLayer.none;
  }

  // At 8-bit precision an alpha below 1/255 ≈ 0.004 maps to zero.
  final effectiveAlpha = config.color.a * config.opacity;
  if (effectiveAlpha < 0.004) {
    return WatermarkLayer.none;
  }

  return hasDynamicContent
      ? WatermarkLayer.dynamicLayer
      : WatermarkLayer.staticLayer;
}
