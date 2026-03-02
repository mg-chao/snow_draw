#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Snapping helpers for grid-aligned geometry.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct GridSnapService;

impl GridSnapService {
    /// Creates a new stateless grid snap service.
    pub const fn new() -> Self {
        Self
    }

    /// Snaps a scalar value to the nearest grid line.
    ///
    /// Returns the original input when either value is non-finite or
    /// `grid_size <= 0.0`.
    pub fn snap_value(&self, value: f64, grid_size: f64) -> f64 {
        if !value.is_finite() || !grid_size.is_finite() || grid_size <= 0.0 {
            return value;
        }

        let snapped = (value / grid_size).round() * grid_size;
        if snapped.is_finite() {
            snapped
        } else {
            value
        }
    }

    /// Snaps a point to the nearest grid intersection.
    pub fn snap_point(&self, point: DrawPoint, grid_size: f64) -> DrawPoint {
        let snapped_x = self.snap_value(point.x, grid_size);
        let snapped_y = self.snap_value(point.y, grid_size);

        if same_coordinate(snapped_x, point.x) && same_coordinate(snapped_y, point.y) {
            return point;
        }

        point.copy_with(Some(snapped_x), Some(snapped_y), None, None)
    }

    /// Snaps selected rectangle edges to the nearest grid lines.
    ///
    /// If all snap flags are `false`, this returns the original rectangle.
    pub fn snap_rect(
        &self,
        rect: DrawRect,
        grid_size: f64,
        snap_min_x: bool,
        snap_max_x: bool,
        snap_min_y: bool,
        snap_max_y: bool,
    ) -> DrawRect {
        if !snap_min_x && !snap_max_x && !snap_min_y && !snap_max_y {
            return rect;
        }

        let snapped_min_x = if snap_min_x {
            self.snap_value(rect.min_x, grid_size)
        } else {
            rect.min_x
        };
        let snapped_min_y = if snap_min_y {
            self.snap_value(rect.min_y, grid_size)
        } else {
            rect.min_y
        };
        let snapped_max_x = if snap_max_x {
            self.snap_value(rect.max_x, grid_size)
        } else {
            rect.max_x
        };
        let snapped_max_y = if snap_max_y {
            self.snap_value(rect.max_y, grid_size)
        } else {
            rect.max_y
        };

        if same_coordinate(snapped_min_x, rect.min_x)
            && same_coordinate(snapped_min_y, rect.min_y)
            && same_coordinate(snapped_max_x, rect.max_x)
            && same_coordinate(snapped_max_y, rect.max_y)
        {
            return rect;
        }

        DrawRect::new(snapped_min_x, snapped_min_y, snapped_max_x, snapped_max_y)
    }
}

fn same_coordinate(a: f64, b: f64) -> bool {
    a == b || (a.is_nan() && b.is_nan())
}

pub const GRID_SNAP_SERVICE: GridSnapService = GridSnapService::new();
