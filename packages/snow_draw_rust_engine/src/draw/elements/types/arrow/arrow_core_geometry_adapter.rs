#![allow(dead_code)]

pub use crate::draw::elements::types::arrow::arrow_two_point_layout::{
    compute_arrow_two_point_layout, ArrowTwoPointLayout,
};

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::ArrowType;

use crate::draw::elements::types::connector::connector_geometry::{
    calculate_connector_rect, normalize_connector_points, resolve_connector_geometry_update,
    resolve_connector_local_points, resolve_connector_world_points, ConnectorGeometryUpdate,
};

/// Resolves arrow local-space points from normalized element-local points.
pub fn resolve_arrow_local_points(
    rect: DrawRect,
    normalized_points: &[DrawPoint],
) -> Vec<DrawPoint> {
    resolve_connector_local_points(rect, normalized_points)
}

/// Resolves arrow world-space points from normalized element-local points.
pub fn resolve_arrow_world_points(
    rect: DrawRect,
    normalized_points: &[DrawPoint],
) -> Vec<DrawPoint> {
    resolve_connector_world_points(rect, normalized_points)
}

/// Normalizes arrow world-space points into element-local space.
pub fn normalize_arrow_points(world_points: &[DrawPoint], rect: DrawRect) -> Vec<DrawPoint> {
    normalize_connector_points(world_points, rect)
}

/// Calculates connector bounds from world-space points.
pub fn calculate_arrow_path_bounds_via_core(
    world_points: &[DrawPoint],
    arrow_type: ArrowType,
) -> DrawRect {
    calculate_connector_rect(world_points, arrow_type)
}

/// Recomputes geometry for arrow-core style local point edits.
pub fn resolve_core_geometry_update(
    local_points: &[DrawPoint],
    old_rect: DrawRect,
    rotation: f64,
    arrow_type: ArrowType,
) -> ConnectorGeometryUpdate {
    resolve_connector_geometry_update(local_points, old_rect, rotation, arrow_type)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adapter_wrappers_delegate_to_connector_geometry() {
        let rect = DrawRect::new(10.0, 20.0, 110.0, 220.0);
        let world_points = vec![DrawPoint::new(10.0, 20.0), DrawPoint::new(110.0, 220.0)];

        let normalized = normalize_arrow_points(&world_points, rect);
        let resolved_world = resolve_arrow_world_points(rect, &normalized);
        let resolved_local = resolve_arrow_local_points(rect, &normalized);
        let fast_layout = compute_arrow_two_point_layout(world_points[0], world_points[1]);

        assert_eq!(resolved_world, world_points);
        assert_eq!(resolved_local, vec![DrawPoint::ZERO, DrawPoint::new(100.0, 200.0)]);
        assert_eq!(calculate_arrow_path_bounds_via_core(&world_points, ArrowType::Straight), rect);
        assert_eq!(fast_layout.rect, rect);
        assert_eq!(fast_layout.normalized_points, normalized);
    }
}
