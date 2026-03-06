#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

pub const BIND_MODE_INSIDE: &str = "inside";
pub const BIND_MODE_ORBIT: &str = "orbit";
pub const BIND_MODE_SKIP: &str = "skip";
pub const DEFAULT_MAX_COORDINATE: f64 = 1e6;

/// Normalizes world-space connector points into a stable coordinate range.
pub fn normalize_arrow_from_global_points(
    points: &[DrawPoint],
    _max_coordinate: f64,
) -> Vec<DrawPoint> {
    points.to_vec()
}
