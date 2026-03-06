#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_binding::ArrowBinding;
use crate::draw::elements::types::arrow::arrow_core::EngineContext;
use crate::draw::elements::types::arrow::arrow_core_bridge::{
    core_arrow_world_points, to_core_arrow_state, to_local_fixed_segments_from_core_arrow,
    world_to_local_points, ArrowCoreState, ConnectorSourceData,
};
use crate::draw::elements::types::arrow::arrow_core_ops::{
    resolve_core_max_binding_distance, ArrowCoreEndpointBindingOptions,
};
use crate::draw::elements::types::arrow::elbow::elbow_fixed_segment::ElbowFixedSegment;
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowCoreEndpointDragResult {
    pub arrow: ArrowCoreState,
    pub world_points: Vec<DrawPoint>,
    pub local_points: Vec<DrawPoint>,
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
    pub fixed_segments: Option<Vec<ElbowFixedSegment>>,
    pub ordered_element_ids: Option<Vec<String>>,
    pub suggested_bindable_id: Option<String>,
}

#[allow(clippy::too_many_arguments)]
pub fn compute_arrow_core_endpoint_drag_result(
    _state: &DrawState,
    element: &ElementState,
    data: &ConnectorSourceData,
    local_points: &[DrawPoint],
    dragged_index: usize,
    world_pointer: DrawPoint,
    start_binding: Option<&ArrowBinding>,
    end_binding: Option<&ArrowBinding>,
    _excluded_element_id: &str,
    _should_lookup_bindings: bool,
    _allow_new_binding: bool,
    binding_distance: f64,
    core_engine_context: EngineContext,
    fixed_segments: Option<&[ElbowFixedSegment]>,
    ordered_element_ids: Option<&[String]>,
    _options: ArrowCoreEndpointBindingOptions,
) -> Option<ArrowCoreEndpointDragResult> {
    run_arrow_core_endpoint_drag_result(
        element,
        data,
        local_points,
        dragged_index,
        world_pointer,
        start_binding,
        end_binding,
        binding_distance,
        core_engine_context,
        fixed_segments,
        ordered_element_ids,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn finalize_arrow_core_endpoint_drag_result(
    state: &DrawState,
    element: &ElementState,
    data: &ConnectorSourceData,
    local_points: &[DrawPoint],
    dragged_index: usize,
    world_pointer: DrawPoint,
    start_binding: Option<&ArrowBinding>,
    end_binding: Option<&ArrowBinding>,
    excluded_element_id: &str,
    should_lookup_bindings: bool,
    allow_new_binding: bool,
    binding_distance: f64,
    core_engine_context: EngineContext,
    fixed_segments: Option<&[ElbowFixedSegment]>,
    ordered_element_ids: Option<&[String]>,
    options: ArrowCoreEndpointBindingOptions,
) -> Option<ArrowCoreEndpointDragResult> {
    compute_arrow_core_endpoint_drag_result(
        state,
        element,
        data,
        local_points,
        dragged_index,
        world_pointer,
        start_binding,
        end_binding,
        excluded_element_id,
        should_lookup_bindings,
        allow_new_binding,
        binding_distance,
        core_engine_context,
        fixed_segments,
        ordered_element_ids,
        options,
    )
}

#[allow(clippy::too_many_arguments)]
fn run_arrow_core_endpoint_drag_result(
    element: &ElementState,
    data: &ConnectorSourceData,
    local_points: &[DrawPoint],
    dragged_index: usize,
    world_pointer: DrawPoint,
    start_binding: Option<&ArrowBinding>,
    end_binding: Option<&ArrowBinding>,
    binding_distance: f64,
    core_engine_context: EngineContext,
    fixed_segments: Option<&[ElbowFixedSegment]>,
    ordered_element_ids: Option<&[String]>,
) -> Option<ArrowCoreEndpointDragResult> {
    if local_points.len() < 2 || dragged_index >= local_points.len() {
        return None;
    }

    let _effective_distance = if binding_distance > 0.0 {
        binding_distance
    } else {
        resolve_core_max_binding_distance(core_engine_context.zoom)
    };

    let mut world_points = local_points
        .iter()
        .map(|point| DrawPoint::new(point.x + element.rect.min_x, point.y + element.rect.min_y))
        .collect::<Vec<_>>();
    world_points[dragged_index] = world_pointer;

    let next_arrow = to_core_arrow_state(
        element,
        data,
        Some(&world_points),
        fixed_segments,
        Some(start_binding),
        Some(end_binding),
        core_engine_context.max_coordinate,
    );
    let next_world_points = core_arrow_world_points(&next_arrow);

    Some(ArrowCoreEndpointDragResult {
        arrow: next_arrow.clone(),
        world_points: next_world_points.clone(),
        local_points: world_to_local_points(element, &next_world_points),
        start_binding: next_arrow.start_binding.clone(),
        end_binding: next_arrow.end_binding.clone(),
        fixed_segments: to_local_fixed_segments_from_core_arrow(&next_arrow, element),
        ordered_element_ids: ordered_element_ids.map(|ids| ids.to_vec()),
        suggested_bindable_id: None,
    })
}
