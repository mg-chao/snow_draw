#![allow(dead_code)]

use crate::draw::types::draw_rect::DrawRect;

/// Scale factors produced during a resize operation.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ResizeScale {
    pub scale_x: f64,
    pub scale_y: f64,
}

impl ResizeScale {
    pub const fn new(scale_x: f64, scale_y: f64) -> Self {
        Self { scale_x, scale_y }
    }
}

/// Pure resize geometry helpers.
pub struct ResizeGeometry;

impl ResizeGeometry {
    pub fn calculate_scale(
        original: DrawRect,
        scaled: DrawRect,
        flip_x: bool,
        flip_y: bool,
    ) -> ResizeScale {
        ResizeScale::new(
            Self::resolve_axis_scale(original.width(), scaled.width(), flip_x),
            Self::resolve_axis_scale(original.height(), scaled.height(), flip_y),
        )
    }

    fn resolve_axis_scale(original_size: f64, scaled_size: f64, flip: bool) -> f64 {
        let scale = if original_size == 0.0 {
            1.0
        } else {
            scaled_size / original_size
        };

        if flip {
            -scale
        } else {
            scale
        }
    }
}
