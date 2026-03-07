#![allow(dead_code)]

pub use super::arrow_render_core::generate_elbow_arrow_path;

use crate::draw::elements::types::arrow::arrow_geometry::{ArrowGeometry, DirectionResolveOptions};
use crate::draw::elements::types::arrow::arrow_layout::{
    compute_arrow_rect_and_points, ArrowRectAndPoints,
};
use crate::draw::elements::types::arrow::arrow_two_point_layout::{
    compute_arrow_two_point_layout, ArrowTwoPointLayout,
};
use crate::draw::elements::types::connector::connector_geometry::ConnectorGeometry;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};

pub type RectNormalizedPoints = ArrowTwoPointLayout;
pub type RectAndLocalPoints = ArrowRectAndPoints;

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

pub fn compute_rotated_rect_and_local_points(
    local_points: &[DrawPoint],
    old_rect: DrawRect,
    rotation: f64,
    arrow_type: ArrowType,
) -> RectAndLocalPoints {
    compute_arrow_rect_and_points(local_points, old_rect, rotation, arrow_type)
}

pub fn sample_elbow_path_for_hit_test(points: &[DrawPoint], stroke_width: f64) -> Vec<DrawPoint> {
    ConnectorGeometry::sample_shaft_for_hit_test(points, ArrowType::Elbow, stroke_width)
}

pub fn calculate_arrowhead_inset(style: ArrowheadStyle, stroke_width: f64) -> f64 {
    ArrowGeometry::calculate_arrowhead_inset(style, stroke_width)
}

pub fn calculate_arrowhead_direction_offset(style: ArrowheadStyle, stroke_width: f64) -> f64 {
    ArrowGeometry::calculate_arrowhead_direction_offset(style, stroke_width)
}

pub fn calculate_arrow_shaft_length(points: &[DrawPoint], arrow_type: ArrowType) -> f64 {
    ArrowGeometry::calculate_shaft_length(points, arrow_type)
}

pub fn calculate_curve_point(
    points: &[DrawPoint],
    segment_index: usize,
    t: f64,
) -> Option<DrawPoint> {
    ArrowGeometry::calculate_curve_draw_point(points, segment_index, t)
}

pub fn calculate_arrow_path_bounds(points: &[DrawPoint], arrow_type: ArrowType) -> DrawRect {
    ArrowGeometry::calculate_path_bounds(points, arrow_type)
}

pub fn apply_arrow_endpoint_insets(
    points: &[DrawPoint],
    start_inset: f64,
    end_inset: f64,
) -> Vec<DrawPoint> {
    ArrowGeometry::apply_insets(points, start_inset, end_inset)
}

pub fn resolve_arrow_start_direction(
    points: &[DrawPoint],
    arrow_type: ArrowType,
    start_inset: f64,
    end_inset: f64,
    direction_offset: f64,
) -> Option<DrawPoint> {
    ArrowGeometry::resolve_start_direction(
        points,
        arrow_type,
        DirectionResolveOptions::new(start_inset, end_inset, direction_offset),
    )
}

pub fn resolve_arrow_end_direction(
    points: &[DrawPoint],
    arrow_type: ArrowType,
    start_inset: f64,
    end_inset: f64,
    direction_offset: f64,
) -> Option<DrawPoint> {
    ArrowGeometry::resolve_end_direction(
        points,
        arrow_type,
        DirectionResolveOptions::new(start_inset, end_inset, direction_offset),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::types::element_style::ArrowType;

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

    #[test]
    fn compute_rotated_rect_and_local_points_keeps_zero_rotation_fast_path() {
        let points = vec![DrawPoint::new(10.0, 20.0), DrawPoint::new(40.0, 60.0)];

        let result = compute_rotated_rect_and_local_points(
            &points,
            DrawRect::new(0.0, 0.0, 50.0, 80.0),
            0.0,
            ArrowType::Straight,
        );

        assert_eq!(result.rect, DrawRect::new(10.0, 20.0, 40.0, 60.0));
        assert_eq!(result.local_points, points);
    }

    #[test]
    fn sample_elbow_path_for_hit_test_flattens_connector_path() {
        let points = vec![
            DrawPoint::new(0.0, 0.0),
            DrawPoint::new(40.0, 0.0),
            DrawPoint::new(40.0, 40.0),
        ];

        let sampled = sample_elbow_path_for_hit_test(&points, 2.0);

        assert!(sampled.len() >= points.len());
        assert_eq!(sampled.first().copied(), Some(points[0]));
        assert_eq!(sampled.last().copied(), Some(points[points.len() - 1]));
    }
}
