#![allow(dead_code)]

use std::collections::HashMap;

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::resize_mode::ResizeMode;

/// Selection handle geometry calculator.
///
/// Provides resize/rotate handle positioning and hit testing in local space.
pub struct HandleCalculator;

impl HandleCalculator {
    const RESIZE_MODES: [ResizeMode; 8] = [
        ResizeMode::TopLeft,
        ResizeMode::TopRight,
        ResizeMode::BottomLeft,
        ResizeMode::BottomRight,
        ResizeMode::Top,
        ResizeMode::Bottom,
        ResizeMode::Left,
        ResizeMode::Right,
    ];

    const RESIZE_HIT_TEST_ORDER: [ResizeMode; 8] = [
        ResizeMode::TopLeft,
        ResizeMode::TopRight,
        ResizeMode::BottomRight,
        ResizeMode::BottomLeft,
        ResizeMode::Top,
        ResizeMode::Right,
        ResizeMode::Bottom,
        ResizeMode::Left,
    ];

    pub fn get_resize_handle_position(
        bounds: DrawRect,
        mode: ResizeMode,
        padding: f64,
    ) -> DrawPoint {
        let min_x = bounds.min_x - padding;
        let min_y = bounds.min_y - padding;
        let max_x = bounds.max_x + padding;
        let max_y = bounds.max_y + padding;
        let center_x = bounds.center_x();
        let center_y = bounds.center_y();

        match mode {
            ResizeMode::TopLeft => DrawPoint::new(min_x, min_y),
            ResizeMode::Top => DrawPoint::new(center_x, min_y),
            ResizeMode::TopRight => DrawPoint::new(max_x, min_y),
            ResizeMode::Right => DrawPoint::new(max_x, center_y),
            ResizeMode::BottomRight => DrawPoint::new(max_x, max_y),
            ResizeMode::Bottom => DrawPoint::new(center_x, max_y),
            ResizeMode::BottomLeft => DrawPoint::new(min_x, max_y),
            ResizeMode::Left => DrawPoint::new(min_x, center_y),
        }
    }

    pub fn get_all_resize_handle_positions(
        bounds: DrawRect,
        padding: f64,
    ) -> HashMap<ResizeMode, DrawPoint> {
        let mut handles = HashMap::with_capacity(Self::RESIZE_MODES.len());
        for mode in Self::RESIZE_MODES {
            handles.insert(
                mode,
                Self::get_resize_handle_position(bounds, mode, padding),
            );
        }
        handles
    }

    pub fn get_rotate_handle_position(bounds: DrawRect, margin: f64, padding: f64) -> DrawPoint {
        DrawPoint::new(bounds.center_x(), bounds.min_y - padding - margin)
    }

    pub fn is_point_in_handle(
        test_point: DrawPoint,
        handle_center: DrawPoint,
        tolerance: f64,
    ) -> bool {
        test_point.distance_squared(handle_center) <= tolerance * tolerance
    }

    /// Hit-tests all resize handles (corners + edge midpoints) in local space.
    pub fn hit_test_resize_handles(
        test_point: DrawPoint,
        bounds: DrawRect,
        tolerance: f64,
        padding: f64,
    ) -> Option<ResizeMode> {
        for mode in Self::RESIZE_HIT_TEST_ORDER {
            let handle = Self::get_resize_handle_position(bounds, mode, padding);
            if Self::is_point_in_handle(test_point, handle, tolerance) {
                return Some(mode);
            }
        }
        None
    }
}
