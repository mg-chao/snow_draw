#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::ArrowType;

use crate::draw::elements::types::connector::connector_geometry::{
    resolve_connector_geometry_update, ConnectorGeometryUpdate,
};

/// Recomputes geometry for arrow-core style local point edits.
pub fn resolve_core_geometry_update(
    local_points: &[DrawPoint],
    old_rect: DrawRect,
    rotation: f64,
    arrow_type: ArrowType,
) -> ConnectorGeometryUpdate {
    resolve_connector_geometry_update(local_points, old_rect, rotation, arrow_type)
}
