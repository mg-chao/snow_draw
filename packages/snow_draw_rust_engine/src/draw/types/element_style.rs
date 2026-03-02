#![allow(dead_code)]

use crate::draw::types::draw_color::DrawColor;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum StrokeStyle {
    Solid,
    Dashed,
    Dotted,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum FillStyle {
    Solid,
    Line,
    CrossLine,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum HighlightShape {
    Rectangle,
    Ellipse,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum CanvasFilterType {
    Mosaic,
    GaussianBlur,
    Grayscale,
    Inversion,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ArrowType {
    Straight,
    Curved,
    Elbow,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ArrowheadStyle {
    None,
    Standard,
    Triangle,
    Square,
    Circle,
    Diamond,
    InvertedTriangle,
    VerticalLine,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum TextHorizontalAlign {
    Left,
    Center,
    Right,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum TextVerticalAlign {
    Top,
    Center,
    Bottom,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct ElementStyleUpdate {
    pub color: Option<DrawColor>,
    pub fill_color: Option<DrawColor>,
    pub stroke_width: Option<f64>,
    pub stroke_style: Option<StrokeStyle>,
    pub fill_style: Option<FillStyle>,
    pub highlight_shape: Option<HighlightShape>,
    pub filter_type: Option<CanvasFilterType>,
    pub filter_strength: Option<f64>,
    pub corner_radius: Option<f64>,
    pub arrow_type: Option<ArrowType>,
    pub start_arrowhead: Option<ArrowheadStyle>,
    pub end_arrowhead: Option<ArrowheadStyle>,
    pub font_size: Option<f64>,
    pub font_family: Option<String>,
    pub text_align: Option<TextHorizontalAlign>,
    pub vertical_align: Option<TextVerticalAlign>,
    pub text_stroke_color: Option<DrawColor>,
    pub text_stroke_width: Option<f64>,
    pub serial_number: Option<i64>,
}

impl ElementStyleUpdate {
    pub fn is_empty(&self) -> bool {
        self.color.is_none()
            && self.fill_color.is_none()
            && self.stroke_width.is_none()
            && self.stroke_style.is_none()
            && self.fill_style.is_none()
            && self.highlight_shape.is_none()
            && self.filter_type.is_none()
            && self.filter_strength.is_none()
            && self.corner_radius.is_none()
            && self.arrow_type.is_none()
            && self.start_arrowhead.is_none()
            && self.end_arrowhead.is_none()
            && self.font_size.is_none()
            && self.font_family.is_none()
            && self.text_align.is_none()
            && self.vertical_align.is_none()
            && self.text_stroke_color.is_none()
            && self.text_stroke_width.is_none()
            && self.serial_number.is_none()
    }
}
