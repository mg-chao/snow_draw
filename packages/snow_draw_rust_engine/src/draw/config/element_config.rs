#![allow(dead_code)]

use crate::draw::types::draw_color::DrawColor;
use crate::draw::types::element_style::{
    ArrowType, ArrowheadStyle, CanvasFilterType, FillStyle, HighlightShape, StrokeStyle,
    TextHorizontalAlign, TextVerticalAlign,
};
use serde::{Deserialize, Serialize};
use std::fmt;

/// Element configuration.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct ElementConfig {
    /// Elements smaller than this value are treated as invalid and removed.
    pub min_valid_size: f64,

    /// Minimum size to start creating an element.
    pub min_create_size: f64,

    /// Minimum size allowed during resize interactions.
    pub min_resize_size: f64,

    /// Rotation snap angle interval in radians.
    pub rotation_snap_angle: f64,
}

impl ElementConfig {
    pub const DEFAULT_MIN_VALID_SIZE: f64 = 5.0;
    pub const DEFAULT_MIN_CREATE_SIZE: f64 = 8.0;
    pub const DEFAULT_MIN_RESIZE_SIZE: f64 = Self::DEFAULT_MIN_VALID_SIZE;
    pub const DEFAULT_ROTATION_SNAP_ANGLE: f64 = std::f64::consts::PI / 12.0;

    pub fn new(
        min_valid_size: f64,
        min_create_size: f64,
        min_resize_size: f64,
        rotation_snap_angle: f64,
    ) -> Self {
        assert!(min_valid_size > 0.0, "min_valid_size must be positive");
        assert!(min_create_size > 0.0, "min_create_size must be positive");
        assert!(
            min_create_size >= min_valid_size,
            "min_create_size must be >= min_valid_size"
        );
        assert!(min_resize_size > 0.0, "min_resize_size must be positive");
        assert!(
            min_resize_size >= min_valid_size,
            "min_resize_size must be >= min_valid_size"
        );
        assert!(
            rotation_snap_angle >= 0.0,
            "rotation_snap_angle must be non-negative"
        );

        Self {
            min_valid_size,
            min_create_size,
            min_resize_size,
            rotation_snap_angle,
        }
    }

    pub fn copy_with(
        self,
        min_valid_size: Option<f64>,
        min_create_size: Option<f64>,
        min_resize_size: Option<f64>,
        rotation_snap_angle: Option<f64>,
    ) -> Self {
        let next = Self::new(
            min_valid_size.unwrap_or(self.min_valid_size),
            min_create_size.unwrap_or(self.min_create_size),
            min_resize_size.unwrap_or(self.min_resize_size),
            rotation_snap_angle.unwrap_or(self.rotation_snap_angle),
        );

        if next == self {
            self
        } else {
            next
        }
    }
}

impl Default for ElementConfig {
    fn default() -> Self {
        Self::new(
            Self::DEFAULT_MIN_VALID_SIZE,
            Self::DEFAULT_MIN_CREATE_SIZE,
            Self::DEFAULT_MIN_RESIZE_SIZE,
            Self::DEFAULT_ROTATION_SNAP_ANGLE,
        )
    }
}

impl fmt::Display for ElementConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "ElementConfig(minValidSize: {}, minCreateSize: {}, minResizeSize: {}, rotationSnapAngle: {})",
            self.min_valid_size, self.min_create_size, self.min_resize_size, self.rotation_snap_angle
        )
    }
}

/// Default element style configuration.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ElementStyleConfig {
    /// Default opacity of newly created elements (`0.0..=1.0`).
    pub opacity: f64,

    /// Default z-index for newly created elements.
    pub z_index: i64,

    /// Default serial number for serial-number elements.
    pub serial_number: i64,

    /// Default stroke width.
    pub stroke_width: f64,

    /// Default primary color.
    pub color: DrawColor,

    /// Default fill color.
    pub fill_color: DrawColor,

    /// Default stroke style.
    pub stroke_style: StrokeStyle,

    /// Default fill style.
    pub fill_style: FillStyle,

    /// Default highlight shape.
    pub highlight_shape: HighlightShape,

    /// Default filter type.
    pub filter_type: CanvasFilterType,

    /// Default filter strength (`0.0..=1.0`).
    pub filter_strength: f64,

    /// Default corner radius.
    pub corner_radius: f64,

    /// Default arrow type.
    pub arrow_type: ArrowType,

    /// Default start arrowhead.
    pub start_arrowhead: ArrowheadStyle,

    /// Default end arrowhead.
    pub end_arrowhead: ArrowheadStyle,

    /// Default font size.
    pub font_size: f64,

    /// Default font family (`None` means system default).
    pub font_family: Option<String>,

    /// Default horizontal text alignment.
    pub text_align: TextHorizontalAlign,

    /// Default vertical text alignment.
    pub vertical_align: TextVerticalAlign,

    /// Default text stroke color.
    pub text_stroke_color: DrawColor,

    /// Default text stroke width.
    pub text_stroke_width: f64,
}

impl ElementStyleConfig {
    pub const DEFAULT_OPACITY: f64 = 1.0;
    pub const DEFAULT_Z_INDEX: i64 = 1;
    pub const DEFAULT_SERIAL_NUMBER: i64 = 1;
    pub const DEFAULT_STROKE_WIDTH: f64 = 2.0;
    pub const DEFAULT_COLOR: DrawColor = DrawColor::new(0xFF1E_1E1E);
    pub const DEFAULT_FILL_COLOR: DrawColor = DrawColor::new(0x0000_0000);
    pub const DEFAULT_STROKE_STYLE: StrokeStyle = StrokeStyle::Solid;
    pub const DEFAULT_FILL_STYLE: FillStyle = FillStyle::Solid;
    pub const DEFAULT_HIGHLIGHT_SHAPE: HighlightShape = HighlightShape::Rectangle;
    pub const DEFAULT_FILTER_TYPE: CanvasFilterType = CanvasFilterType::Mosaic;
    pub const DEFAULT_FILTER_STRENGTH: f64 = 0.5;
    pub const DEFAULT_CORNER_RADIUS: f64 = 4.0;
    pub const DEFAULT_ARROW_TYPE: ArrowType = ArrowType::Straight;
    pub const DEFAULT_START_ARROWHEAD: ArrowheadStyle = ArrowheadStyle::None;
    pub const DEFAULT_END_ARROWHEAD: ArrowheadStyle = ArrowheadStyle::Standard;
    pub const DEFAULT_FONT_SIZE: f64 = 21.0;
    pub const DEFAULT_TEXT_ALIGN: TextHorizontalAlign = TextHorizontalAlign::Left;
    pub const DEFAULT_VERTICAL_ALIGN: TextVerticalAlign = TextVerticalAlign::Center;
    pub const DEFAULT_TEXT_STROKE_COLOR: DrawColor = DrawColor::new(0xFFF8_F4EC);
    pub const DEFAULT_TEXT_STROKE_WIDTH: f64 = 0.0;

    #[allow(clippy::too_many_arguments)]
    pub fn new(
        opacity: f64,
        z_index: i64,
        serial_number: i64,
        stroke_width: f64,
        color: DrawColor,
        fill_color: DrawColor,
        stroke_style: StrokeStyle,
        fill_style: FillStyle,
        highlight_shape: HighlightShape,
        filter_type: CanvasFilterType,
        filter_strength: f64,
        corner_radius: f64,
        arrow_type: ArrowType,
        start_arrowhead: ArrowheadStyle,
        end_arrowhead: ArrowheadStyle,
        font_size: f64,
        font_family: Option<String>,
        text_align: TextHorizontalAlign,
        vertical_align: TextVerticalAlign,
        text_stroke_color: DrawColor,
        text_stroke_width: f64,
    ) -> Self {
        assert!(
            opacity >= 0.0 && opacity <= 1.0,
            "opacity must be in [0, 1]"
        );
        assert!(z_index >= 0, "z_index must be non-negative");
        assert!(serial_number >= 0, "serial_number must be non-negative");
        assert!(stroke_width >= 0.0, "stroke_width must be non-negative");
        assert!(
            filter_strength >= 0.0,
            "filter_strength must be non-negative"
        );
        assert!(filter_strength <= 1.0, "filter_strength must be <= 1");
        assert!(corner_radius >= 0.0, "corner_radius must be non-negative");
        assert!(font_size >= 0.0, "font_size must be non-negative");
        assert!(
            text_stroke_width >= 0.0,
            "text_stroke_width must be non-negative"
        );

        Self {
            opacity,
            z_index,
            serial_number,
            stroke_width,
            color,
            fill_color,
            stroke_style,
            fill_style,
            highlight_shape,
            filter_type,
            filter_strength,
            corner_radius,
            arrow_type,
            start_arrowhead,
            end_arrowhead,
            font_size,
            font_family,
            text_align,
            vertical_align,
            text_stroke_color,
            text_stroke_width,
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub fn copy_with(
        &self,
        opacity: Option<f64>,
        z_index: Option<i64>,
        serial_number: Option<i64>,
        stroke_width: Option<f64>,
        color: Option<DrawColor>,
        fill_color: Option<DrawColor>,
        stroke_style: Option<StrokeStyle>,
        fill_style: Option<FillStyle>,
        highlight_shape: Option<HighlightShape>,
        filter_type: Option<CanvasFilterType>,
        filter_strength: Option<f64>,
        corner_radius: Option<f64>,
        arrow_type: Option<ArrowType>,
        start_arrowhead: Option<ArrowheadStyle>,
        end_arrowhead: Option<ArrowheadStyle>,
        font_size: Option<f64>,
        font_family: Option<Option<String>>,
        text_align: Option<TextHorizontalAlign>,
        vertical_align: Option<TextVerticalAlign>,
        text_stroke_color: Option<DrawColor>,
        text_stroke_width: Option<f64>,
    ) -> Self {
        let next_font_family = match font_family {
            Some(value) => Self::normalize_font_family(value),
            None => self.font_family.clone(),
        };

        let next = Self::new(
            opacity.unwrap_or(self.opacity),
            z_index.unwrap_or(self.z_index),
            serial_number.unwrap_or(self.serial_number),
            stroke_width.unwrap_or(self.stroke_width),
            color.unwrap_or(self.color),
            fill_color.unwrap_or(self.fill_color),
            stroke_style.unwrap_or(self.stroke_style),
            fill_style.unwrap_or(self.fill_style),
            highlight_shape.unwrap_or(self.highlight_shape),
            filter_type.unwrap_or(self.filter_type),
            filter_strength.unwrap_or(self.filter_strength),
            corner_radius.unwrap_or(self.corner_radius),
            arrow_type.unwrap_or(self.arrow_type),
            start_arrowhead.unwrap_or(self.start_arrowhead),
            end_arrowhead.unwrap_or(self.end_arrowhead),
            font_size.unwrap_or(self.font_size),
            next_font_family,
            text_align.unwrap_or(self.text_align),
            vertical_align.unwrap_or(self.vertical_align),
            text_stroke_color.unwrap_or(self.text_stroke_color),
            text_stroke_width.unwrap_or(self.text_stroke_width),
        );

        if next == *self {
            self.clone()
        } else {
            next
        }
    }

    fn normalize_font_family(font_family: Option<String>) -> Option<String> {
        match font_family {
            Some(value) if value.trim().is_empty() => None,
            value => value,
        }
    }
}

impl Default for ElementStyleConfig {
    fn default() -> Self {
        Self::new(
            Self::DEFAULT_OPACITY,
            Self::DEFAULT_Z_INDEX,
            Self::DEFAULT_SERIAL_NUMBER,
            Self::DEFAULT_STROKE_WIDTH,
            Self::DEFAULT_COLOR,
            Self::DEFAULT_FILL_COLOR,
            Self::DEFAULT_STROKE_STYLE,
            Self::DEFAULT_FILL_STYLE,
            Self::DEFAULT_HIGHLIGHT_SHAPE,
            Self::DEFAULT_FILTER_TYPE,
            Self::DEFAULT_FILTER_STRENGTH,
            Self::DEFAULT_CORNER_RADIUS,
            Self::DEFAULT_ARROW_TYPE,
            Self::DEFAULT_START_ARROWHEAD,
            Self::DEFAULT_END_ARROWHEAD,
            Self::DEFAULT_FONT_SIZE,
            None,
            Self::DEFAULT_TEXT_ALIGN,
            Self::DEFAULT_VERTICAL_ALIGN,
            Self::DEFAULT_TEXT_STROKE_COLOR,
            Self::DEFAULT_TEXT_STROKE_WIDTH,
        )
    }
}

impl fmt::Display for ElementStyleConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let font_family = self.font_family.as_deref().unwrap_or("null");
        write!(
            f,
            "ElementStyleConfig(opacity: {}, zIndex: {}, serialNumber: {}, strokeWidth: {}, color: {}, fillColor: {}, strokeStyle: {:?}, fillStyle: {:?}, highlightShape: {:?}, filterType: {:?}, filterStrength: {}, cornerRadius: {}, arrowType: {:?}, startArrowhead: {:?}, endArrowhead: {:?}, fontSize: {}, fontFamily: {}, textAlign: {:?}, verticalAlign: {:?}, textStrokeColor: {}, textStrokeWidth: {})",
            self.opacity,
            self.z_index,
            self.serial_number,
            self.stroke_width,
            self.color,
            self.fill_color,
            self.stroke_style,
            self.fill_style,
            self.highlight_shape,
            self.filter_type,
            self.filter_strength,
            self.corner_radius,
            self.arrow_type,
            self.start_arrowhead,
            self.end_arrowhead,
            self.font_size,
            font_family,
            self.text_align,
            self.vertical_align,
            self.text_stroke_color,
            self.text_stroke_width
        )
    }
}

#[cfg(test)]
mod tests {
    use super::ElementStyleConfig;

    #[test]
    fn constructor_preserves_non_null_blank_font_family() {
        let config = ElementStyleConfig::new(
            ElementStyleConfig::DEFAULT_OPACITY,
            ElementStyleConfig::DEFAULT_Z_INDEX,
            ElementStyleConfig::DEFAULT_SERIAL_NUMBER,
            ElementStyleConfig::DEFAULT_STROKE_WIDTH,
            ElementStyleConfig::DEFAULT_COLOR,
            ElementStyleConfig::DEFAULT_FILL_COLOR,
            ElementStyleConfig::DEFAULT_STROKE_STYLE,
            ElementStyleConfig::DEFAULT_FILL_STYLE,
            ElementStyleConfig::DEFAULT_HIGHLIGHT_SHAPE,
            ElementStyleConfig::DEFAULT_FILTER_TYPE,
            ElementStyleConfig::DEFAULT_FILTER_STRENGTH,
            ElementStyleConfig::DEFAULT_CORNER_RADIUS,
            ElementStyleConfig::DEFAULT_ARROW_TYPE,
            ElementStyleConfig::DEFAULT_START_ARROWHEAD,
            ElementStyleConfig::DEFAULT_END_ARROWHEAD,
            ElementStyleConfig::DEFAULT_FONT_SIZE,
            Some(String::new()),
            ElementStyleConfig::DEFAULT_TEXT_ALIGN,
            ElementStyleConfig::DEFAULT_VERTICAL_ALIGN,
            ElementStyleConfig::DEFAULT_TEXT_STROKE_COLOR,
            ElementStyleConfig::DEFAULT_TEXT_STROKE_WIDTH,
        );

        assert_eq!(config.font_family.as_deref(), Some(""));
    }

    #[test]
    fn copy_with_normalizes_blank_font_family_to_none() {
        let config = ElementStyleConfig::default().copy_with(
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            Some(Some("  ".to_owned())),
            None,
            None,
            None,
            None,
        );

        assert_eq!(config.font_family, None);
    }
}
