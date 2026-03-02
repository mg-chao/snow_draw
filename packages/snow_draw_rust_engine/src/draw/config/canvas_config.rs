#![allow(dead_code)]

use crate::draw::types::draw_color::DrawColor;
use serde::{Deserialize, Serialize};
use std::fmt;

/// Canvas-level configuration.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct CanvasConfig {
    /// Background color of the canvas.
    pub background_color: DrawColor,
}

impl CanvasConfig {
    /// Mirrors `ConfigDefaults.backgroundColor` from the Dart engine.
    pub const DEFAULT_BACKGROUND_COLOR: DrawColor = DrawColor::new(0xFFFF_FFFF);

    pub const fn new(background_color: DrawColor) -> Self {
        Self { background_color }
    }

    pub fn copy_with(self, background_color: Option<DrawColor>) -> Self {
        match background_color {
            None => self,
            Some(value) if value == self.background_color => self,
            Some(value) => Self::new(value),
        }
    }
}

impl Default for CanvasConfig {
    fn default() -> Self {
        Self::new(Self::DEFAULT_BACKGROUND_COLOR)
    }
}

impl fmt::Display for CanvasConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "CanvasConfig(backgroundColor: {})",
            self.background_color
        )
    }
}

/// Configuration for box selection (marquee selection).
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct BoxSelectionConfig {
    /// Fill color of the selection box.
    pub fill_color: DrawColor,

    /// Opacity of the fill (`0.0..=1.0`).
    pub fill_opacity: f64,

    /// Stroke color of the selection box border.
    pub stroke_color: DrawColor,

    /// Stroke width of the selection box border.
    pub stroke_width: f64,
}

impl BoxSelectionConfig {
    /// Mirrors `ConfigDefaults.accentColor` from the Dart engine.
    pub const DEFAULT_FILL_COLOR: DrawColor = DrawColor::new(0xFF40_96FF);

    /// Mirrors `ConfigDefaults.boxSelectionFillOpacity` from the Dart engine.
    pub const DEFAULT_FILL_OPACITY: f64 = 0.2;

    /// Mirrors `ConfigDefaults.accentColor` from the Dart engine.
    pub const DEFAULT_STROKE_COLOR: DrawColor = DrawColor::new(0xFF40_96FF);

    /// Mirrors `ConfigDefaults.selectionStrokeWidth` from the Dart engine.
    pub const DEFAULT_STROKE_WIDTH: f64 = 1.0;

    pub fn new(
        fill_color: DrawColor,
        fill_opacity: f64,
        stroke_color: DrawColor,
        stroke_width: f64,
    ) -> Self {
        assert!(
            fill_opacity >= 0.0 && fill_opacity <= 1.0,
            "fill_opacity must be in [0, 1]"
        );
        assert!(stroke_width >= 0.0, "stroke_width must be non-negative");

        Self {
            fill_color,
            fill_opacity,
            stroke_color,
            stroke_width,
        }
    }

    pub fn copy_with(
        self,
        fill_color: Option<DrawColor>,
        fill_opacity: Option<f64>,
        stroke_color: Option<DrawColor>,
        stroke_width: Option<f64>,
    ) -> Self {
        let next_fill_color = fill_color.unwrap_or(self.fill_color);
        let next_fill_opacity = fill_opacity.unwrap_or(self.fill_opacity);
        let next_stroke_color = stroke_color.unwrap_or(self.stroke_color);
        let next_stroke_width = stroke_width.unwrap_or(self.stroke_width);

        if next_fill_color == self.fill_color
            && next_fill_opacity == self.fill_opacity
            && next_stroke_color == self.stroke_color
            && next_stroke_width == self.stroke_width
        {
            return self;
        }

        Self::new(
            next_fill_color,
            next_fill_opacity,
            next_stroke_color,
            next_stroke_width,
        )
    }
}

impl Default for BoxSelectionConfig {
    fn default() -> Self {
        Self::new(
            Self::DEFAULT_FILL_COLOR,
            Self::DEFAULT_FILL_OPACITY,
            Self::DEFAULT_STROKE_COLOR,
            Self::DEFAULT_STROKE_WIDTH,
        )
    }
}

impl fmt::Display for BoxSelectionConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "BoxSelectionConfig(fillColor: {}, fillOpacity: {}, strokeColor: {}, strokeWidth: {})",
            self.fill_color, self.fill_opacity, self.stroke_color, self.stroke_width
        )
    }
}
