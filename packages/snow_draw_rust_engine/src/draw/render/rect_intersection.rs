#![allow(dead_code)]

use crate::draw::types::draw_rect::DrawRect;

/// Returns `true` when two world-space rectangles overlap.
pub fn rects_intersect(a: DrawRect, b: DrawRect) -> bool {
    a.min_x <= b.max_x && a.max_x >= b.min_x && a.min_y <= b.max_y && a.max_y >= b.min_y
}
