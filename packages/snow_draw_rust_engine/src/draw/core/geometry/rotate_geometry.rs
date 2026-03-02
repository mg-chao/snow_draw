#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

/// Pure rotate geometry helpers.
#[derive(Clone, Copy, Debug, Default)]
pub struct RotateGeometry;

impl RotateGeometry {
    /// Returns the angle from `center` to `point` in radians.
    ///
    /// The result uses the standard `atan2(dy, dx)` convention.
    pub fn angle_from_center(point: DrawPoint, center: DrawPoint) -> f64 {
        (point.y - center.y).atan2(point.x - center.x)
    }

    /// Normalizes an angle delta to the principal range `[-pi, pi]`.
    pub fn normalize_delta(delta: f64) -> f64 {
        delta.sin().atan2(delta.cos())
    }

    /// Applies discrete snapping to a rotation delta.
    ///
    /// `snap_interval` must be strictly positive. In release builds, an invalid
    /// interval returns `delta` unchanged to mirror the Dart behavior.
    pub fn apply_discrete_snap(delta: f64, base_angle: f64, snap_interval: f64) -> f64 {
        debug_assert!(snap_interval > 0.0, "snap_interval must be > 0");
        if snap_interval <= 0.0 {
            return delta;
        }

        let snapped_total = ((base_angle + delta) / snap_interval).round() * snap_interval;
        snapped_total - base_angle
    }

    /// Rotates `point` around `center` by `angle` radians.
    pub fn rotate_point(point: DrawPoint, center: DrawPoint, angle: f64) -> DrawPoint {
        if angle == 0.0 {
            return point;
        }

        let cos_a = angle.cos();
        let sin_a = angle.sin();
        let dx = point.x - center.x;
        let dy = point.y - center.y;

        DrawPoint::new(
            center.x + dx * cos_a - dy * sin_a,
            center.y + dx * sin_a + dy * cos_a,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::RotateGeometry;
    use crate::draw::types::draw_point::DrawPoint;
    use std::f64::consts::{FRAC_PI_2, PI};

    fn approx_eq(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-10
    }

    #[test]
    fn angle_from_center_matches_atan2() {
        let angle = RotateGeometry::angle_from_center(DrawPoint::new(1.0, 1.0), DrawPoint::ZERO);
        assert!(approx_eq(angle, FRAC_PI_2 / 2.0));
    }

    #[test]
    fn normalize_delta_wraps_to_principal_range() {
        let normalized = RotateGeometry::normalize_delta(PI * 1.5);
        assert!(approx_eq(normalized, -FRAC_PI_2));
    }

    #[test]
    fn apply_discrete_snap_rounds_total_angle() {
        let snap = PI / 4.0;
        let base = PI / 8.0;
        let delta = PI / 3.0;
        let snapped = RotateGeometry::apply_discrete_snap(delta, base, snap);

        let total = base + snapped;
        assert!(approx_eq(total, PI / 2.0));
    }

    #[test]
    fn rotate_point_rotates_about_center() {
        let point = DrawPoint::new(2.0, 1.0);
        let center = DrawPoint::new(1.0, 1.0);
        let rotated = RotateGeometry::rotate_point(point, center, FRAC_PI_2);

        assert!(approx_eq(rotated.x, 1.0));
        assert!(approx_eq(rotated.y, 2.0));
    }
}
