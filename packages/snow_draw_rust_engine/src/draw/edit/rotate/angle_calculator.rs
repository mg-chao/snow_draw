#![allow(dead_code)]

use crate::draw::core::geometry::rotate_geometry::RotateGeometry;
use crate::draw::types::draw_point::DrawPoint;

/// Returns the raw angle from `center` to `current_position` in radians.
#[inline]
pub fn raw_angle(current_position: DrawPoint, center: DrawPoint) -> f64 {
    RotateGeometry::angle_from_center(current_position, center)
}

/// Normalizes an angle delta to the principal range `[-pi, pi]`.
#[inline]
pub fn normalize_delta(delta: f64) -> f64 {
    RotateGeometry::normalize_delta(delta)
}

/// Snaps a total angle (`base_angle + delta`) to the nearest interval and
/// returns the snapped delta.
#[inline]
pub fn apply_discrete_snap(delta: f64, base_angle: f64, snap_interval: f64) -> f64 {
    RotateGeometry::apply_discrete_snap(delta, base_angle, snap_interval)
}
