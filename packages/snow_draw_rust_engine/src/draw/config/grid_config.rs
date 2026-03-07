#![allow(dead_code)]

use crate::draw::types::draw_color::DrawColor;
use serde::{Deserialize, Serialize};
use std::fmt;

/// Grid snapping and rendering configuration.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct GridConfig {
    /// Whether grid snapping and rendering is enabled.
    pub enabled: bool,

    /// Grid cell size in world pixels.
    pub size: f64,

    /// Base color for grid lines.
    pub line_color: DrawColor,

    /// Opacity for minor grid lines.
    pub line_opacity: f64,

    /// Opacity for major grid lines.
    pub major_line_opacity: f64,

    /// Line width in screen pixels.
    pub line_width: f64,

    /// Number of minor cells between major lines.
    pub major_line_every: i64,

    /// Minimum screen spacing (px) between rendered grid lines.
    pub min_screen_spacing: f64,

    /// Hide grid if base spacing falls below this (px).
    pub min_render_spacing: f64,
}

impl GridConfig {
    /// Mirrors `ConfigDefaults.gridEnabled`.
    pub const DEFAULT_ENABLED: bool = false;

    /// Mirrors `ConfigDefaults.gridSize`.
    pub const DEFAULT_SIZE: f64 = 20.0;

    /// Mirrors `ConfigDefaults.gridMinSize`.
    pub const MIN_SIZE: f64 = 5.0;

    /// Mirrors `ConfigDefaults.gridMaxSize`.
    pub const MAX_SIZE: f64 = 100.0;

    /// Mirrors `ConfigDefaults.gridLineColor`.
    pub const DEFAULT_LINE_COLOR: DrawColor = DrawColor::new(0xFFBD_BDBD);

    /// Mirrors `ConfigDefaults.gridLineOpacity`.
    pub const DEFAULT_LINE_OPACITY: f64 = 0.45;

    /// Mirrors `ConfigDefaults.gridMajorLineOpacity`.
    pub const DEFAULT_MAJOR_LINE_OPACITY: f64 = 0.7;

    /// Mirrors `ConfigDefaults.gridLineWidth`.
    pub const DEFAULT_LINE_WIDTH: f64 = 1.0;

    /// Mirrors `ConfigDefaults.gridMajorLineEvery`.
    pub const DEFAULT_MAJOR_LINE_EVERY: i64 = 5;

    /// Mirrors `ConfigDefaults.gridMinScreenSpacing`.
    pub const DEFAULT_MIN_SCREEN_SPACING: f64 = 10.0;

    /// Mirrors `ConfigDefaults.gridMinRenderSpacing`.
    pub const DEFAULT_MIN_RENDER_SPACING: f64 = 2.0;

    #[allow(clippy::too_many_arguments)]
    pub fn new(
        enabled: bool,
        size: f64,
        line_color: DrawColor,
        line_opacity: f64,
        major_line_opacity: f64,
        line_width: f64,
        major_line_every: i64,
        min_screen_spacing: f64,
        min_render_spacing: f64,
    ) -> Self {
        assert!(size >= Self::MIN_SIZE, "size too small");
        assert!(size <= Self::MAX_SIZE, "size too large");
        assert!(
            line_opacity >= 0.0 && line_opacity <= 1.0,
            "line_opacity must be in [0, 1]"
        );
        assert!(
            major_line_opacity >= 0.0 && major_line_opacity <= 1.0,
            "major_line_opacity must be in [0, 1]"
        );
        assert!(line_width > 0.0, "line_width must be positive");
        assert!(major_line_every > 0, "major_line_every must be positive");
        assert!(
            min_screen_spacing > 0.0,
            "min_screen_spacing must be positive"
        );
        assert!(
            min_render_spacing >= 0.0,
            "min_render_spacing must be non-negative"
        );
        assert!(
            min_render_spacing <= min_screen_spacing,
            "min_render_spacing must be <= min_screen_spacing"
        );

        Self {
            enabled,
            size,
            line_color,
            line_opacity,
            major_line_opacity,
            line_width,
            major_line_every,
            min_screen_spacing,
            min_render_spacing,
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub fn copy_with(
        self,
        enabled: Option<bool>,
        size: Option<f64>,
        line_color: Option<DrawColor>,
        line_opacity: Option<f64>,
        major_line_opacity: Option<f64>,
        line_width: Option<f64>,
        major_line_every: Option<i64>,
        min_screen_spacing: Option<f64>,
        min_render_spacing: Option<f64>,
    ) -> Self {
        if enabled.is_none()
            && size.is_none()
            && line_color.is_none()
            && line_opacity.is_none()
            && major_line_opacity.is_none()
            && line_width.is_none()
            && major_line_every.is_none()
            && min_screen_spacing.is_none()
            && min_render_spacing.is_none()
        {
            return self;
        }

        let next = Self::new(
            enabled.unwrap_or(self.enabled),
            size.unwrap_or(self.size),
            line_color.unwrap_or(self.line_color),
            line_opacity.unwrap_or(self.line_opacity),
            major_line_opacity.unwrap_or(self.major_line_opacity),
            line_width.unwrap_or(self.line_width),
            major_line_every.unwrap_or(self.major_line_every),
            min_screen_spacing.unwrap_or(self.min_screen_spacing),
            min_render_spacing.unwrap_or(self.min_render_spacing),
        );

        if next == self {
            self
        } else {
            next
        }
    }
}

impl Default for GridConfig {
    fn default() -> Self {
        Self::new(
            Self::DEFAULT_ENABLED,
            Self::DEFAULT_SIZE,
            Self::DEFAULT_LINE_COLOR,
            Self::DEFAULT_LINE_OPACITY,
            Self::DEFAULT_MAJOR_LINE_OPACITY,
            Self::DEFAULT_LINE_WIDTH,
            Self::DEFAULT_MAJOR_LINE_EVERY,
            Self::DEFAULT_MIN_SCREEN_SPACING,
            Self::DEFAULT_MIN_RENDER_SPACING,
        )
    }
}

impl fmt::Display for GridConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "GridConfig(enabled: {}, size: {}, lineColor: {}, lineOpacity: {}, majorLineOpacity: {}, lineWidth: {}, majorLineEvery: {}, minScreenSpacing: {}, minRenderSpacing: {})",
            self.enabled,
            self.size,
            self.line_color,
            self.line_opacity,
            self.major_line_opacity,
            self.line_width,
            self.major_line_every,
            self.min_screen_spacing,
            self.min_render_spacing
        )
    }
}
