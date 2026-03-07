#![allow(dead_code)]

use crate::draw::types::draw_color::DrawColor;
use serde::{Deserialize, Serialize};
use std::fmt;

/// Object snapping configuration.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct SnapConfig {
    /// Whether object snapping is enabled.
    pub enabled: bool,

    /// Base snap distance in screen pixels.
    pub distance: f64,

    /// Enable point snapping (corners/centers/edges).
    pub enable_point_snaps: bool,

    /// Enable gap snapping (equal spacing).
    pub enable_gap_snaps: bool,

    /// Enable arrow endpoint binding to elements.
    pub enable_arrow_binding: bool,

    /// Snap distance for arrow binding in screen pixels.
    pub arrow_binding_distance: f64,

    /// Whether to render snap guides.
    pub show_guides: bool,

    /// Whether to render gap size labels.
    pub show_gap_size: bool,

    /// Color for snap guides.
    pub line_color: DrawColor,

    /// Stroke width for snap guides.
    pub line_width: f64,

    /// Cross/tick marker size in screen pixels.
    pub marker_size: f64,

    /// Dash length for gap guides.
    pub gap_dash_length: f64,

    /// Dash gap length for gap guides.
    pub gap_dash_gap: f64,
}

impl SnapConfig {
    /// Mirrors `ConfigDefaults.objectSnapEnabled`.
    pub const DEFAULT_ENABLED: bool = false;

    /// Mirrors `ConfigDefaults.objectSnapDistance`.
    pub const DEFAULT_DISTANCE: f64 = 8.0;

    /// Mirrors `ConfigDefaults.objectSnapPointEnabled`.
    pub const DEFAULT_ENABLE_POINT_SNAPS: bool = true;

    /// Mirrors `ConfigDefaults.objectSnapGapEnabled`.
    pub const DEFAULT_ENABLE_GAP_SNAPS: bool = true;

    /// Mirrors `ConfigDefaults.arrowBindingEnabled`.
    pub const DEFAULT_ENABLE_ARROW_BINDING: bool = true;

    /// Mirrors `ConfigDefaults.arrowBindingDistance`.
    pub const DEFAULT_ARROW_BINDING_DISTANCE: f64 = 10.0;

    /// Mirrors `ConfigDefaults.objectSnapShowGuides`.
    pub const DEFAULT_SHOW_GUIDES: bool = true;

    /// Mirrors `ConfigDefaults.objectSnapShowGapSize`.
    pub const DEFAULT_SHOW_GAP_SIZE: bool = false;

    /// Mirrors `ConfigDefaults.objectSnapLineColor`.
    pub const DEFAULT_LINE_COLOR: DrawColor = DrawColor::new(0xFFFF_6B6B);

    /// Mirrors `ConfigDefaults.objectSnapLineWidth`.
    pub const DEFAULT_LINE_WIDTH: f64 = 1.0;

    /// Mirrors `ConfigDefaults.objectSnapMarkerSize`.
    pub const DEFAULT_MARKER_SIZE: f64 = 8.0;

    /// Mirrors `ConfigDefaults.objectSnapGapDashLength`.
    pub const DEFAULT_GAP_DASH_LENGTH: f64 = 4.0;

    /// Mirrors `ConfigDefaults.objectSnapGapDashGap`.
    pub const DEFAULT_GAP_DASH_GAP: f64 = 4.0;

    #[allow(clippy::too_many_arguments)]
    pub fn new(
        enabled: bool,
        distance: f64,
        enable_point_snaps: bool,
        enable_gap_snaps: bool,
        enable_arrow_binding: bool,
        arrow_binding_distance: f64,
        show_guides: bool,
        show_gap_size: bool,
        line_color: DrawColor,
        line_width: f64,
        marker_size: f64,
        gap_dash_length: f64,
        gap_dash_gap: f64,
    ) -> Self {
        assert!(distance >= 0.0, "distance must be non-negative");
        assert!(
            arrow_binding_distance >= 0.0,
            "arrow_binding_distance must be non-negative"
        );
        assert!(line_width > 0.0, "line_width must be positive");
        assert!(marker_size >= 0.0, "marker_size must be non-negative");
        assert!(
            gap_dash_length >= 0.0,
            "gap_dash_length must be non-negative"
        );
        assert!(gap_dash_gap >= 0.0, "gap_dash_gap must be non-negative");

        Self {
            enabled,
            distance,
            enable_point_snaps,
            enable_gap_snaps,
            enable_arrow_binding,
            arrow_binding_distance,
            show_guides,
            show_gap_size,
            line_color,
            line_width,
            marker_size,
            gap_dash_length,
            gap_dash_gap,
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub fn copy_with(
        self,
        enabled: Option<bool>,
        distance: Option<f64>,
        enable_point_snaps: Option<bool>,
        enable_gap_snaps: Option<bool>,
        enable_arrow_binding: Option<bool>,
        arrow_binding_distance: Option<f64>,
        show_guides: Option<bool>,
        show_gap_size: Option<bool>,
        line_color: Option<DrawColor>,
        line_width: Option<f64>,
        marker_size: Option<f64>,
        gap_dash_length: Option<f64>,
        gap_dash_gap: Option<f64>,
    ) -> Self {
        if enabled.is_none()
            && distance.is_none()
            && enable_point_snaps.is_none()
            && enable_gap_snaps.is_none()
            && enable_arrow_binding.is_none()
            && arrow_binding_distance.is_none()
            && show_guides.is_none()
            && show_gap_size.is_none()
            && line_color.is_none()
            && line_width.is_none()
            && marker_size.is_none()
            && gap_dash_length.is_none()
            && gap_dash_gap.is_none()
        {
            return self;
        }

        let next = Self::new(
            enabled.unwrap_or(self.enabled),
            distance.unwrap_or(self.distance),
            enable_point_snaps.unwrap_or(self.enable_point_snaps),
            enable_gap_snaps.unwrap_or(self.enable_gap_snaps),
            enable_arrow_binding.unwrap_or(self.enable_arrow_binding),
            arrow_binding_distance.unwrap_or(self.arrow_binding_distance),
            show_guides.unwrap_or(self.show_guides),
            show_gap_size.unwrap_or(self.show_gap_size),
            line_color.unwrap_or(self.line_color),
            line_width.unwrap_or(self.line_width),
            marker_size.unwrap_or(self.marker_size),
            gap_dash_length.unwrap_or(self.gap_dash_length),
            gap_dash_gap.unwrap_or(self.gap_dash_gap),
        );

        if next == self {
            self
        } else {
            next
        }
    }
}

impl Default for SnapConfig {
    fn default() -> Self {
        Self::new(
            Self::DEFAULT_ENABLED,
            Self::DEFAULT_DISTANCE,
            Self::DEFAULT_ENABLE_POINT_SNAPS,
            Self::DEFAULT_ENABLE_GAP_SNAPS,
            Self::DEFAULT_ENABLE_ARROW_BINDING,
            Self::DEFAULT_ARROW_BINDING_DISTANCE,
            Self::DEFAULT_SHOW_GUIDES,
            Self::DEFAULT_SHOW_GAP_SIZE,
            Self::DEFAULT_LINE_COLOR,
            Self::DEFAULT_LINE_WIDTH,
            Self::DEFAULT_MARKER_SIZE,
            Self::DEFAULT_GAP_DASH_LENGTH,
            Self::DEFAULT_GAP_DASH_GAP,
        )
    }
}

impl fmt::Display for SnapConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "SnapConfig(enabled: {}, distance: {}, enablePointSnaps: {}, enableGapSnaps: {}, enableArrowBinding: {}, arrowBindingDistance: {}, showGuides: {}, showGapSize: {}, lineColor: {}, lineWidth: {}, markerSize: {}, gapDashLength: {}, gapDashGap: {})",
            self.enabled,
            self.distance,
            self.enable_point_snaps,
            self.enable_gap_snaps,
            self.enable_arrow_binding,
            self.arrow_binding_distance,
            self.show_guides,
            self.show_gap_size,
            self.line_color,
            self.line_width,
            self.marker_size,
            self.gap_dash_length,
            self.gap_dash_gap
        )
    }
}
