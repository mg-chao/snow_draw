#![allow(dead_code)]

use crate::draw::config::watermark_config::WatermarkConfig;

/// Returns whether watermark configuration produces visible pixels.
pub fn is_watermark_visible(config: &WatermarkConfig) -> bool {
    if config.text.trim().is_empty() {
        return false;
    }

    // At 8-bit precision an alpha below 1/255 ~= 0.004 maps to zero.
    config.color.a() * config.opacity >= 0.004
}
