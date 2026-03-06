#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::elements::types::arrow::arrow_layout::{
    resolve_arrow_geometry_update, ArrowGeometryUpdate,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::ArrowType;

pub type ConnectorGeometryUpdate = ArrowGeometryUpdate;

/// Calculates connector bounds from world-space points.
pub fn calculate_connector_rect(points: &[DrawPoint], arrow_type: ArrowType) -> DrawRect {
    ArrowGeometry::calculate_path_bounds(points, arrow_type)
}

/// Normalizes connector world-space points into element-local space.
pub fn normalize_connector_points(world_points: &[DrawPoint], rect: DrawRect) -> Vec<DrawPoint> {
    ArrowGeometry::normalize_points(world_points, rect)
}

/// Resolves world-space connector points from normalized element-local points.
pub fn resolve_connector_world_points(
    rect: DrawRect,
    normalized_points: &[DrawPoint],
) -> Vec<DrawPoint> {
    ArrowGeometry::resolve_world_points(rect, normalized_points)
}

/// Recomputes connector geometry after local point edits.
pub fn resolve_connector_geometry_update(
    local_points: &[DrawPoint],
    old_rect: DrawRect,
    rotation: f64,
    arrow_type: ArrowType,
) -> ConnectorGeometryUpdate {
    resolve_arrow_geometry_update(local_points, old_rect, rotation, arrow_type)
}
