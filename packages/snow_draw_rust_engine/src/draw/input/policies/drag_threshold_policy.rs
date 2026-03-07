#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

/// Returns whether movement from `from` to `to` reaches `threshold`.
///
/// Non-positive thresholds are treated as immediate drag start.
pub fn has_reached_drag_threshold(from: DrawPoint, to: DrawPoint, threshold: f64) -> bool {
    if threshold <= 0.0 {
        return true;
    }

    let threshold_squared = threshold * threshold;
    from.distance_squared(to) >= threshold_squared
}
