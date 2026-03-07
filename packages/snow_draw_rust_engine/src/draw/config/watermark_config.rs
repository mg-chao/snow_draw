#![allow(dead_code)]

use crate::draw::types::draw_color::DrawColor;
use serde::{Deserialize, Serialize};
use std::fmt;

/// Global watermark configuration.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct WatermarkConfig {
    /// Base text color.
    pub color: DrawColor,

    /// Watermark label. Empty text disables rendering.
    pub text: String,

    /// Font size in logical pixels.
    pub font_size: f64,

    /// Font family name. Empty string uses system fallback fonts.
    pub font_family: String,

    /// Clockwise text rotation angle in degrees.
    pub angle: f64,

    /// Gap between tiled watermark labels.
    pub gap: f64,

    /// Opacity multiplier applied on top of `color` alpha.
    pub opacity: f64,
}

impl WatermarkConfig {
    /// Mirrors `ConfigDefaults.defaultWatermarkColor`.
    pub const DEFAULT_COLOR: DrawColor = DrawColor::new(0xFF1E_1E1E);

    /// Mirrors `ConfigDefaults.defaultWatermarkText`.
    pub const DEFAULT_TEXT: &'static str = "";

    /// Mirrors `ConfigDefaults.defaultWatermarkFontSize`.
    pub const DEFAULT_FONT_SIZE: f64 = 16.0;

    /// Mirrors `ConfigDefaults.defaultWatermarkFontFamily`.
    pub const DEFAULT_FONT_FAMILY: &'static str = "";

    /// Mirrors `ConfigDefaults.defaultWatermarkAngle`.
    pub const DEFAULT_ANGLE: f64 = 30.0;

    /// Mirrors `ConfigDefaults.defaultWatermarkGap`.
    pub const DEFAULT_GAP: f64 = 56.0;

    /// Mirrors `ConfigDefaults.minWatermarkGap`.
    pub const MIN_GAP: f64 = 10.0;

    /// Mirrors `ConfigDefaults.maxWatermarkGap`.
    pub const MAX_GAP: f64 = 200.0;

    /// Mirrors `ConfigDefaults.defaultWatermarkOpacity`.
    pub const DEFAULT_OPACITY: f64 = 0.16;

    pub fn new(
        color: DrawColor,
        text: String,
        font_size: f64,
        font_family: String,
        angle: f64,
        gap: f64,
        opacity: f64,
    ) -> Self {
        assert!(font_size > 0.0, "font_size must be > 0");
        assert!(
            gap >= Self::MIN_GAP && gap <= Self::MAX_GAP,
            "gap must be in [{}, {}]",
            Self::MIN_GAP,
            Self::MAX_GAP
        );
        assert!(
            opacity >= 0.0 && opacity <= 1.0,
            "opacity must be in [0, 1]"
        );

        Self {
            color,
            text,
            font_size,
            font_family,
            angle,
            gap,
            opacity,
        }
    }

    pub fn copy_with(
        &self,
        color: Option<DrawColor>,
        text: Option<String>,
        font_size: Option<f64>,
        font_family: Option<String>,
        angle: Option<f64>,
        gap: Option<f64>,
        opacity: Option<f64>,
    ) -> Self {
        if color.is_none()
            && text.is_none()
            && font_size.is_none()
            && font_family.is_none()
            && angle.is_none()
            && gap.is_none()
            && opacity.is_none()
        {
            return self.clone();
        }

        let next = Self::new(
            color.unwrap_or(self.color),
            text.unwrap_or_else(|| self.text.clone()),
            font_size.unwrap_or(self.font_size),
            font_family.unwrap_or_else(|| self.font_family.clone()),
            angle.unwrap_or(self.angle),
            gap.unwrap_or(self.gap),
            opacity.unwrap_or(self.opacity),
        );

        if next == *self {
            self.clone()
        } else {
            next
        }
    }
}

impl Default for WatermarkConfig {
    fn default() -> Self {
        Self::new(
            Self::DEFAULT_COLOR,
            Self::DEFAULT_TEXT.to_string(),
            Self::DEFAULT_FONT_SIZE,
            Self::DEFAULT_FONT_FAMILY.to_string(),
            Self::DEFAULT_ANGLE,
            Self::DEFAULT_GAP,
            Self::DEFAULT_OPACITY,
        )
    }
}

impl fmt::Display for WatermarkConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "WatermarkConfig(color: {}, text: {}, fontSize: {}, fontFamily: {}, angle: {}, gap: {}, opacity: {})",
            self.color,
            self.text,
            self.font_size,
            self.font_family,
            self.angle,
            self.gap,
            self.opacity
        )
    }
}
