#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::elements::types::connector::connector_geometry::resolve_connector_geometry_update;
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};

use super::arrow_binding::{ArrowBinding, ArrowBindingMode};
use super::arrow_core::ArrowEndpointEdge;
use super::arrow_data::ArrowData;
use super::arrow_data::{
    ArrowBinding as SourceArrowBinding, ArrowBindingMode as SourceArrowBindingMode,
};
use super::core::arrow_focus_core::{
    resolve_focus_point_hit_with_offset, resolve_visible_focus_points,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ArrowFocusEndpoint {
    Start,
    End,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowFocusPoint {
    pub endpoint: ArrowFocusEndpoint,
    pub point: DrawPoint,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowFocusHit {
    pub endpoint: Option<ArrowFocusEndpoint>,
    pub pointer_offset: DrawPoint,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowFocusDragResult {
    pub element: ElementState,
    pub element_changed: bool,
    pub ordered_element_ids: Option<Vec<String>>,
    pub suggested_bindable_id: Option<String>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowFocusFinalizeResult;

pub fn list_visible_arrow_focus_points(
    element: &ElementState,
    data: &ArrowData,
) -> Vec<ArrowFocusPoint> {
    if data.arrow_type == ArrowType::Elbow {
        return Vec::new();
    }
    let arrow = to_arrow_state(element, data);
    resolve_visible_focus_points(&arrow)
        .into_iter()
        .map(|descriptor| ArrowFocusPoint {
            endpoint: match descriptor.edge {
                ArrowEndpointEdge::Start => ArrowFocusEndpoint::Start,
                ArrowEndpointEdge::End => ArrowFocusEndpoint::End,
            },
            point: descriptor.point,
        })
        .collect()
}

pub fn pick_arrow_focus_point_with_offset(
    element: &ElementState,
    data: &ArrowData,
    pointer: DrawPoint,
    tolerance: f64,
) -> ArrowFocusHit {
    if data.arrow_type == ArrowType::Elbow {
        return ArrowFocusHit {
            endpoint: None,
            pointer_offset: DrawPoint::ZERO,
        };
    }

    let hit =
        resolve_focus_point_hit_with_offset(&to_arrow_state(element, data), pointer, tolerance);
    ArrowFocusHit {
        endpoint: hit.edge.map(|edge| match edge {
            ArrowEndpointEdge::Start => ArrowFocusEndpoint::Start,
            ArrowEndpointEdge::End => ArrowFocusEndpoint::End,
        }),
        pointer_offset: hit.pointer_offset,
    }
}

pub fn drag_arrow_focus_point(
    element: &ElementState,
    data: &ArrowData,
    dragged_endpoint: ArrowFocusEndpoint,
    pointer: DrawPoint,
) -> ArrowFocusDragResult {
    if data.arrow_type == ArrowType::Elbow {
        return ArrowFocusDragResult {
            element: element.clone(),
            element_changed: false,
            ordered_element_ids: None,
            suggested_bindable_id: None,
        };
    }

    let mut world_points =
        crate::draw::elements::types::connector::connector_geometry::resolve_connector_world_points(
            element.rect,
            &data.points,
        );
    if world_points.len() < 2 {
        return ArrowFocusDragResult {
            element: element.clone(),
            element_changed: false,
            ordered_element_ids: None,
            suggested_bindable_id: None,
        };
    }

    match dragged_endpoint {
        ArrowFocusEndpoint::Start => world_points[0] = pointer,
        ArrowFocusEndpoint::End => {
            let last_index = world_points.len() - 1;
            world_points[last_index] = pointer;
        }
    }

    let geometry = resolve_connector_geometry_update(
        &world_points,
        element.rect,
        element.rotation,
        data.arrow_type,
    );
    let next_data = data.copy_with(super::arrow_data::ArrowDataPatch {
        points: Some(geometry.normalized_points),
        ..Default::default()
    });
    let next_element = element.copy_with(
        None,
        Some(geometry.rect),
        None,
        None,
        None,
        Some(Arc::new(next_data)),
    );

    ArrowFocusDragResult {
        element_changed: next_element != *element,
        element: next_element,
        ordered_element_ids: None,
        suggested_bindable_id: None,
    }
}

pub fn finalize_arrow_focus_point_drag() -> ArrowFocusFinalizeResult {
    ArrowFocusFinalizeResult
}

fn to_arrow_state(element: &ElementState, data: &ArrowData) -> super::arrow_core::ArrowState {
    let world_points =
        crate::draw::elements::types::connector::connector_geometry::resolve_connector_world_points(
            element.rect,
            &data.points,
        );
    let normalized = super::arrow_core::normalize_arrow_from_global_points(
        &world_points,
        super::arrow_core::DEFAULT_MAX_COORDINATE,
    );
    super::arrow_core::ArrowState {
        id: element.id.clone(),
        x: normalized.x,
        y: normalized.y,
        width: normalized.width,
        height: normalized.height,
        points: normalized.points,
        start_binding: data.start_binding.as_ref().map(to_engine_binding),
        end_binding: data.end_binding.as_ref().map(to_engine_binding),
        start_arrowhead: Some(arrowhead_name(data.start_arrowhead).to_string()),
        end_arrowhead: Some(arrowhead_name(data.end_arrowhead).to_string()),
        elbowed: data.arrow_type == ArrowType::Elbow,
        fixed_segments: data.fixed_segments.clone(),
        start_is_special: data.start_is_special,
        end_is_special: data.end_is_special,
    }
}

fn to_engine_binding(binding: &SourceArrowBinding) -> ArrowBinding {
    ArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        match binding.mode {
            SourceArrowBindingMode::Inside => ArrowBindingMode::Inside,
            SourceArrowBindingMode::Orbit => ArrowBindingMode::Orbit,
            SourceArrowBindingMode::Skip => ArrowBindingMode::Skip,
        },
    )
}

fn arrowhead_name(style: ArrowheadStyle) -> &'static str {
    match style {
        ArrowheadStyle::None => "none",
        ArrowheadStyle::Standard => "standard",
        ArrowheadStyle::Triangle => "triangle",
        ArrowheadStyle::TriangleOutline => "triangleOutline",
        ArrowheadStyle::Square => "square",
        ArrowheadStyle::Dot => "dot",
        ArrowheadStyle::Circle => "circle",
        ArrowheadStyle::CircleOutline => "circleOutline",
        ArrowheadStyle::Diamond => "diamond",
        ArrowheadStyle::DiamondOutline => "diamondOutline",
        ArrowheadStyle::CrowfootOne => "crowfootOne",
        ArrowheadStyle::CrowfootMany => "crowfootMany",
        ArrowheadStyle::CrowfootOneOrMany => "crowfootOneOrMany",
        ArrowheadStyle::InvertedTriangle => "invertedTriangle",
        ArrowheadStyle::VerticalLine => "verticalLine",
    }
}
