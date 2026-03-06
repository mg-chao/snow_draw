#![allow(dead_code)]

pub use super::arrow_render_core::generate_elbow_arrow_path;

use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::elements::types::arrow::arrow_two_point_layout::{
    compute_arrow_two_point_layout, ArrowTwoPointLayout,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

pub fn resolve_arrowhead_length(stroke_width: f64) -> f64 {
    ArrowGeometry::resolve_arrowhead_length(stroke_width)
}

pub fn ensure_minimum_arrow_points(points: &[DrawPoint]) -> Vec<DrawPoint> {
    if points.len() >= 2 {
        return points.to_vec();
    }
    if points.is_empty() {
        return vec![DrawPoint::ZERO, DrawPoint::new(1.0, 1.0)];
    }
    let first = points[0];
    vec![first, first]
}

pub fn denormalize_rect_points(rect: DrawRect, normalized_points: &[DrawPoint]) -> Vec<DrawPoint> {
    ArrowGeometry::resolve_world_points(rect, normalized_points)
}

pub fn normalize_rect_points(
    rect: DrawRect,
    world_points: &[DrawPoint],
    clamp: bool,
) -> Vec<DrawPoint> {
    let points = ensure_minimum_arrow_points(world_points);
    let width = rect.width();
    let height = rect.height();
    points
        .into_iter()
        .map(|point| {
            let x = if width == 0.0 {
                0.0
            } else {
                (point.x - rect.min_x) / width
            };
            let y = if height == 0.0 {
                0.0
            } else {
                (point.y - rect.min_y) / height
            };
            let nx = if clamp { x.clamp(0.0, 1.0) } else { x };
            let ny = if clamp { y.clamp(0.0, 1.0) } else { y };
            DrawPoint::with_pressure_and_timestamp(nx, ny, point.pressure, point.timestamp)
        })
        .collect()
}

pub fn compute_rect_normalized_points(
    rect: DrawRect,
    world_points: &[DrawPoint],
) -> ArrowTwoPointLayout {
    ArrowTwoPointLayout::new(rect, normalize_rect_points(rect, world_points, true))
}

pub fn compute_two_point_rect_normalized_points(
    first: DrawPoint,
    second: DrawPoint,
) -> ArrowTwoPointLayout {
    compute_arrow_two_point_layout(first, second)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ensure_minimum_arrow_points_supplies_defaults() {
        assert_eq!(
            ensure_minimum_arrow_points(&[]),
            vec![DrawPoint::ZERO, DrawPoint::new(1.0, 1.0)]
        );
        assert_eq!(
            ensure_minimum_arrow_points(&[DrawPoint::new(3.0, 4.0)]),
            vec![DrawPoint::new(3.0, 4.0), DrawPoint::new(3.0, 4.0)]
        );
    }

    #[test]
    fn normalize_rect_points_can_skip_clamping() {
        let rect = DrawRect::new(10.0, 20.0, 30.0, 40.0);
        let normalized = normalize_rect_points(rect, &[DrawPoint::new(0.0, 10.0)], false);

        assert_eq!(normalized[0], DrawPoint::new(-0.5, -0.5));
    }
}
