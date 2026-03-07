#![allow(dead_code)]

use crate::draw::types::draw_color::DrawColor;
use serde::{Deserialize, Serialize};
use std::fmt;

/// Selection rendering configuration.
///
/// Contains styling and geometry values used to render selection outlines and
/// control points.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct SelectionRenderConfig {
    /// Stroke width of the selection outline.
    pub stroke_width: f64,

    /// Stroke color of the selection outline.
    pub stroke_color: DrawColor,

    /// Fill color of corner/control-point handles.
    pub corner_fill_color: DrawColor,

    /// Corner/control-point radius.
    pub corner_radius: f64,

    /// Base control-point size.
    pub control_point_size: f64,
}

impl SelectionRenderConfig {
    /// Mirrors `ConfigDefaults.selectionStrokeWidth`.
    pub const DEFAULT_STROKE_WIDTH: f64 = 1.0;

    /// Mirrors `ConfigDefaults.accentColor`.
    pub const DEFAULT_STROKE_COLOR: DrawColor = DrawColor::new(0xFF40_96FF);

    /// Mirrors `ConfigDefaults.controlPointFillColor`.
    pub const DEFAULT_CORNER_FILL_COLOR: DrawColor = DrawColor::new(0xFFFF_FFFF);

    /// Mirrors `ConfigDefaults.controlPointRadius`.
    pub const DEFAULT_CORNER_RADIUS: f64 = 2.0;

    /// Mirrors `ConfigDefaults.controlPointSize`.
    pub const DEFAULT_CONTROL_POINT_SIZE: f64 = 8.0;

    pub fn new(
        stroke_width: f64,
        stroke_color: DrawColor,
        corner_fill_color: DrawColor,
        corner_radius: f64,
        control_point_size: f64,
    ) -> Self {
        assert!(stroke_width > 0.0, "stroke_width must be positive");
        assert!(corner_radius >= 0.0, "corner_radius must be non-negative");
        assert!(
            control_point_size > 0.0,
            "control_point_size must be positive"
        );

        Self {
            stroke_width,
            stroke_color,
            corner_fill_color,
            corner_radius,
            control_point_size,
        }
    }

    pub fn copy_with(
        self,
        stroke_width: Option<f64>,
        stroke_color: Option<DrawColor>,
        corner_fill_color: Option<DrawColor>,
        corner_radius: Option<f64>,
        control_point_size: Option<f64>,
    ) -> Self {
        let next_stroke_width = stroke_width.unwrap_or(self.stroke_width);
        let next_stroke_color = stroke_color.unwrap_or(self.stroke_color);
        let next_corner_fill_color = corner_fill_color.unwrap_or(self.corner_fill_color);
        let next_corner_radius = corner_radius.unwrap_or(self.corner_radius);
        let next_control_point_size = control_point_size.unwrap_or(self.control_point_size);

        if next_stroke_width == self.stroke_width
            && next_stroke_color == self.stroke_color
            && next_corner_fill_color == self.corner_fill_color
            && next_corner_radius == self.corner_radius
            && next_control_point_size == self.control_point_size
        {
            return self;
        }

        Self::new(
            next_stroke_width,
            next_stroke_color,
            next_corner_fill_color,
            next_corner_radius,
            next_control_point_size,
        )
    }
}

impl Default for SelectionRenderConfig {
    fn default() -> Self {
        Self::new(
            Self::DEFAULT_STROKE_WIDTH,
            Self::DEFAULT_STROKE_COLOR,
            Self::DEFAULT_CORNER_FILL_COLOR,
            Self::DEFAULT_CORNER_RADIUS,
            Self::DEFAULT_CONTROL_POINT_SIZE,
        )
    }
}

impl fmt::Display for SelectionRenderConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "SelectionRenderConfig(strokeWidth: {}, strokeColor: {}, cornerFillColor: {}, cornerRadius: {}, controlPointSize: {})",
            self.stroke_width,
            self.stroke_color,
            self.corner_fill_color,
            self.corner_radius,
            self.control_point_size
        )
    }
}

/// Selection interaction configuration.
///
/// Contains hit-testing and gesture thresholds used by interaction logic.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct SelectionInteractionConfig {
    /// Hit tolerance around handles.
    pub handle_tolerance: f64,

    /// Drag threshold before move gestures are considered active.
    pub drag_threshold: f64,
}

impl SelectionInteractionConfig {
    /// Mirrors `ConfigDefaults.handleTolerance`.
    pub const DEFAULT_HANDLE_TOLERANCE: f64 = 6.0;

    /// Mirrors `ConfigDefaults.dragThreshold`.
    pub const DEFAULT_DRAG_THRESHOLD: f64 = 0.0;

    pub fn new(handle_tolerance: f64, drag_threshold: f64) -> Self {
        assert!(handle_tolerance > 0.0, "handle_tolerance must be positive");
        assert!(drag_threshold >= 0.0, "drag_threshold must be non-negative");

        Self {
            handle_tolerance,
            drag_threshold,
        }
    }

    pub fn copy_with(self, handle_tolerance: Option<f64>, drag_threshold: Option<f64>) -> Self {
        let next_handle_tolerance = handle_tolerance.unwrap_or(self.handle_tolerance);
        let next_drag_threshold = drag_threshold.unwrap_or(self.drag_threshold);

        if next_handle_tolerance == self.handle_tolerance
            && next_drag_threshold == self.drag_threshold
        {
            return self;
        }

        Self::new(next_handle_tolerance, next_drag_threshold)
    }
}

impl Default for SelectionInteractionConfig {
    fn default() -> Self {
        Self::new(Self::DEFAULT_HANDLE_TOLERANCE, Self::DEFAULT_DRAG_THRESHOLD)
    }
}

impl fmt::Display for SelectionInteractionConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "SelectionInteractionConfig(handleTolerance: {}, dragThreshold: {})",
            self.handle_tolerance, self.drag_threshold
        )
    }
}

/// Unified selection configuration.
///
/// Combines rendering and interaction settings used by selection workflows.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct SelectionConfig {
    /// Rendering settings.
    pub render: SelectionRenderConfig,

    /// Interaction settings.
    pub interaction: SelectionInteractionConfig,

    /// Padding around selection bounds used for render and hit-test logic.
    pub padding: f64,

    /// Offset from the selection top edge to the rotate handle.
    pub rotate_handle_offset: f64,
}

impl SelectionConfig {
    /// Mirrors `ConfigDefaults.selectionPadding`.
    pub const DEFAULT_PADDING: f64 = 3.0;

    /// Mirrors `ConfigDefaults.rotateHandleOffset`.
    pub const DEFAULT_ROTATE_HANDLE_OFFSET: f64 = 12.0;

    pub fn new(
        render: SelectionRenderConfig,
        interaction: SelectionInteractionConfig,
        padding: f64,
        rotate_handle_offset: f64,
    ) -> Self {
        assert!(padding >= 0.0, "padding must be non-negative");
        assert!(
            rotate_handle_offset >= 0.0,
            "rotate_handle_offset must be non-negative"
        );

        Self {
            render,
            interaction,
            padding,
            rotate_handle_offset,
        }
    }

    pub fn copy_with(
        self,
        render: Option<SelectionRenderConfig>,
        interaction: Option<SelectionInteractionConfig>,
        padding: Option<f64>,
        rotate_handle_offset: Option<f64>,
    ) -> Self {
        let next_render = render.unwrap_or(self.render);
        let next_interaction = interaction.unwrap_or(self.interaction);
        let next_padding = padding.unwrap_or(self.padding);
        let next_rotate_handle_offset = rotate_handle_offset.unwrap_or(self.rotate_handle_offset);

        if next_render == self.render
            && next_interaction == self.interaction
            && next_padding == self.padding
            && next_rotate_handle_offset == self.rotate_handle_offset
        {
            return self;
        }

        Self::new(
            next_render,
            next_interaction,
            next_padding,
            next_rotate_handle_offset,
        )
    }
}

impl Default for SelectionConfig {
    fn default() -> Self {
        Self::new(
            SelectionRenderConfig::default(),
            SelectionInteractionConfig::default(),
            Self::DEFAULT_PADDING,
            Self::DEFAULT_ROTATE_HANDLE_OFFSET,
        )
    }
}

impl fmt::Display for SelectionConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "SelectionConfig(render: {}, interaction: {}, padding: {}, rotateHandleOffset: {})",
            self.render, self.interaction, self.padding, self.rotate_handle_offset
        )
    }
}
