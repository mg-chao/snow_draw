#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

use super::arrow_core::normalize_arrow_from_global_points;

/// Normalizes world-space points for core-style connector operations.
pub fn normalize_core_points(points: &[DrawPoint]) -> Vec<DrawPoint> {
    normalize_arrow_from_global_points(points, super::arrow_core::DEFAULT_MAX_COORDINATE)
}
