#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SnapGuideKind {
    Point,
    Gap,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SnapGuideAxis {
    Horizontal,
    Vertical,
}

/// Visual guide information for snapping.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SnapGuide {
    pub kind: SnapGuideKind,
    pub axis: SnapGuideAxis,
    pub start: DrawPoint,
    pub end: DrawPoint,
    pub markers: Vec<DrawPoint>,
    pub label: Option<f64>,
}

impl SnapGuide {
    pub fn new(kind: SnapGuideKind, axis: SnapGuideAxis, start: DrawPoint, end: DrawPoint) -> Self {
        Self {
            kind,
            axis,
            start,
            end,
            markers: Vec::new(),
            label: None,
        }
    }
}

pub fn snap_guide_list_equals(a: &[SnapGuide], b: &[SnapGuide]) -> bool {
    a == b
}
