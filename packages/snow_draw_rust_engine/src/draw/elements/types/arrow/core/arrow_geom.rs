#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_layout::resolve_arrow_geometry_update;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::ArrowType;

use super::arrow_types::NormalizedArrowFromGlobalPoints;

pub fn normalize_arrow_from_global_points(
    global_points: &[DrawPoint],
    max_coordinate: f64,
) -> NormalizedArrowFromGlobalPoints {
    if global_points.is_empty() {
        return NormalizedArrowFromGlobalPoints {
            x: 0.0,
            y: 0.0,
            points: Vec::new(),
            width: 0.0,
            height: 0.0,
        };
    }

    let origin = global_points[0];
    let points = global_points
        .iter()
        .map(|point| {
            DrawPoint::new(
                (point.x - origin.x).clamp(-max_coordinate, max_coordinate),
                (point.y - origin.y).clamp(-max_coordinate, max_coordinate),
            )
        })
        .collect::<Vec<_>>();
    let bounds = DrawRect::from_point_cloud(points.iter().copied());

    NormalizedArrowFromGlobalPoints {
        x: origin.x.clamp(-max_coordinate, max_coordinate),
        y: origin.y.clamp(-max_coordinate, max_coordinate),
        points,
        width: bounds.width(),
        height: bounds.height(),
    }
}

pub fn resolve_geometry_patch_from_local_points(
    local_points: &[DrawPoint],
    old_rect: DrawRect,
    rotation: f64,
    arrow_type: ArrowType,
) -> (DrawRect, Vec<DrawPoint>) {
    let update = resolve_arrow_geometry_update(local_points, old_rect, rotation, arrow_type);
    (update.rect, update.normalized_points)
}
