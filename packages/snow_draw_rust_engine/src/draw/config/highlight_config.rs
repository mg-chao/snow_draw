#![allow(dead_code)]

use crate::draw::types::draw_color::DrawColor;
use serde::{Deserialize, Serialize};
use std::fmt;

/// Global highlight mask configuration.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct HighlightMaskConfig {
    /// Mask color applied to the canvas.
    pub mask_color: DrawColor,

    /// Mask opacity multiplier applied to `mask_color` (`0.0..=1.0`).
    pub mask_opacity: f64,
}

impl HighlightMaskConfig {
    /// Mirrors `ConfigDefaults.defaultMaskColor` from the Dart engine.
    pub const DEFAULT_MASK_COLOR: DrawColor = DrawColor::new(0xFF1E_1E1E);

    /// Mirrors default `maskOpacity` from the Dart engine.
    pub const DEFAULT_MASK_OPACITY: f64 = 0.0;

    pub fn new(mask_color: DrawColor, mask_opacity: f64) -> Self {
        assert!(
            mask_opacity >= 0.0 && mask_opacity <= 1.0,
            "mask_opacity must be in [0, 1]"
        );

        Self {
            mask_color,
            mask_opacity,
        }
    }

    pub fn copy_with(self, mask_color: Option<DrawColor>, mask_opacity: Option<f64>) -> Self {
        let next_mask_color = mask_color.unwrap_or(self.mask_color);
        let next_mask_opacity = mask_opacity.unwrap_or(self.mask_opacity);

        if next_mask_color == self.mask_color && next_mask_opacity == self.mask_opacity {
            return self;
        }

        Self::new(next_mask_color, next_mask_opacity)
    }
}

impl Default for HighlightMaskConfig {
    fn default() -> Self {
        Self::new(Self::DEFAULT_MASK_COLOR, Self::DEFAULT_MASK_OPACITY)
    }
}

impl fmt::Display for HighlightMaskConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "HighlightMaskConfig(maskColor: {}, maskOpacity: {})",
            self.mask_color, self.mask_opacity
        )
    }
}
