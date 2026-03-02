#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::resize_mode::ResizeMode;

/// Returns the opposite anchor point for a resize handle in local bounds space.
///
/// The returned point is expressed in the same coordinate space as `rect`
/// (typically the selection overlay's un-rotated local frame).
pub fn opposite_bound_point_local(rect: DrawRect, mode: ResizeMode) -> DrawPoint {
    match mode {
        ResizeMode::TopLeft => DrawPoint::new(rect.max_x, rect.max_y),
        ResizeMode::TopRight => DrawPoint::new(rect.min_x, rect.max_y),
        ResizeMode::BottomRight => DrawPoint::new(rect.min_x, rect.min_y),
        ResizeMode::BottomLeft => DrawPoint::new(rect.max_x, rect.min_y),
        ResizeMode::Top => DrawPoint::new(rect.center_x(), rect.max_y),
        ResizeMode::Bottom => DrawPoint::new(rect.center_x(), rect.min_y),
        ResizeMode::Left => DrawPoint::new(rect.max_x, rect.center_y()),
        ResizeMode::Right => DrawPoint::new(rect.min_x, rect.center_y()),
    }
}
