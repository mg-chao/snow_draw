#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding, ArrowBindingResult, ArrowBindingUtils,
};
use crate::draw::elements::types::arrow::arrow_binding_snapper::{
    ArrowBindingCachePolicy, ArrowBindingResolver as SnapperBindingResolver, ArrowBindingSnapper,
};
use crate::draw::elements::types::arrow::arrow_core::EngineContext;
use crate::draw::elements::types::arrow::arrow_core_bridge::{
    core_arrow_world_points, to_core_arrow_state, to_local_fixed_segments_from_core_arrow,
    world_to_local_points, ArrowCoreState, ConnectorSourceData,
};
use crate::draw::elements::types::arrow::arrow_core_ops::{
    resolve_core_max_binding_distance, ArrowCoreEndpointBindingOptions,
};
use crate::draw::elements::types::arrow::elbow::elbow_fixed_segment::ElbowFixedSegment;
use crate::draw::models::draw_state::{DomainElementState, DrawState};
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};

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
    run_arrow_core_endpoint_drag_result(
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
        false,
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
    run_arrow_core_endpoint_drag_result(
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
        true,
    )
}

#[allow(clippy::too_many_arguments)]
fn run_arrow_core_endpoint_drag_result(
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
    _options: ArrowCoreEndpointBindingOptions,
    _finalize: bool,
) -> Option<ArrowCoreEndpointDragResult> {
    if binding_distance < 0.0 {
        return None;
    }
    if local_points.len() < 2 || dragged_index >= local_points.len() {
        return None;
    }

    let effective_distance = if binding_distance > 0.0 {
        binding_distance
    } else {
        resolve_core_max_binding_distance(core_engine_context.zoom)
    };
    let mut next_local_points = local_points.to_vec();
    let mut world_points = local_points
        .iter()
        .map(|point| DrawPoint::new(point.x + element.rect.min_x, point.y + element.rect.min_y))
        .collect::<Vec<_>>();
    let mut next_start_binding = start_binding.cloned();
    let mut next_end_binding = end_binding.cloned();
    let mut suggested_bindable_id = None;

    let dragged_is_endpoint = dragged_index == 0 || dragged_index + 1 == local_points.len();
    if dragged_is_endpoint {
        let endpoint = if dragged_index == 0 {
            Endpoint::Start
        } else {
            Endpoint::End
        };
        let existing_binding = match endpoint {
            Endpoint::Start => next_start_binding.as_ref(),
            Endpoint::End => next_end_binding.as_ref(),
        };
        let candidate = ArrowBindingSnapper::resolve_endpoint_binding_candidate(
            state,
            world_pointer,
            data.arrow_type,
            endpoint_arrowhead_style(data, endpoint),
            should_lookup_bindings,
            effective_distance,
            allow_new_binding,
            has_bindable_targets(state, excluded_element_id),
            existing_binding,
            endpoint_reference_point(&world_points, endpoint),
            None,
            Some(excluded_element_id),
            ArrowBindingCachePolicy::default(),
            &ENDPOINT_DRAG_BINDING_RESOLVER,
        );

        let target_world = if let Some(ArrowBindingResult {
            binding,
            snap_point,
            ..
        }) = candidate
        {
            suggested_bindable_id = Some(binding.element_id.clone());
            match endpoint {
                Endpoint::Start => next_start_binding = Some(binding),
                Endpoint::End => next_end_binding = Some(binding),
            }
            snap_point
        } else {
            match endpoint {
                Endpoint::Start => next_start_binding = None,
                Endpoint::End => next_end_binding = None,
            }
            world_pointer
        };

        world_points[dragged_index] = target_world;
        next_local_points[dragged_index] = to_local_point(element, target_world);
    } else {
        world_points[dragged_index] = world_pointer;
        next_local_points[dragged_index] = to_local_point(element, world_pointer);
    }

    if data.arrow_type != ArrowType::Elbow && next_local_points.len() >= 2 && dragged_is_endpoint {
        let loop_threshold = effective_distance.max(1.0);
        let start_index = 0;
        let end_index = next_local_points.len() - 1;
        if world_points[start_index].distance_squared(world_points[end_index])
            <= loop_threshold * loop_threshold
        {
            if dragged_index == start_index {
                world_points[start_index] = world_points[end_index];
                next_local_points[start_index] = next_local_points[end_index];
                next_start_binding = next_end_binding.clone();
                suggested_bindable_id = suggested_bindable_id.or_else(|| {
                    next_end_binding
                        .as_ref()
                        .map(|binding| binding.element_id.clone())
                });
            } else {
                world_points[end_index] = world_points[start_index];
                next_local_points[end_index] = next_local_points[start_index];
                next_end_binding = next_start_binding.clone();
                suggested_bindable_id = suggested_bindable_id.or_else(|| {
                    next_start_binding
                        .as_ref()
                        .map(|binding| binding.element_id.clone())
                });
            }
        }
    }

    let fixed_segments_for_core = if data.arrow_type == ArrowType::Elbow {
        fixed_segments
    } else {
        None
    };
    let next_arrow = to_core_arrow_state(
        element,
        data,
        Some(&next_local_points),
        fixed_segments_for_core,
        Some(next_start_binding.as_ref()),
        Some(next_end_binding.as_ref()),
        core_engine_context.max_coordinate,
    );
    let next_world_points = core_arrow_world_points(&next_arrow);

    Some(ArrowCoreEndpointDragResult {
        arrow: next_arrow.clone(),
        world_points: next_world_points.clone(),
        local_points: world_to_local_points(element, &next_world_points),
        start_binding: next_arrow.start_binding.clone(),
        end_binding: next_arrow.end_binding.clone(),
        fixed_segments: if data.arrow_type == ArrowType::Elbow {
            to_local_fixed_segments_from_core_arrow(&next_arrow, element)
        } else {
            fixed_segments.map(|segments| segments.to_vec())
        },
        ordered_element_ids: ordered_element_ids.map(|ids| ids.to_vec()),
        suggested_bindable_id,
    })
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Endpoint {
    Start,
    End,
}

fn endpoint_arrowhead_style(data: &ConnectorSourceData, endpoint: Endpoint) -> ArrowheadStyle {
    match endpoint {
        Endpoint::Start => data.start_arrowhead,
        Endpoint::End => data.end_arrowhead,
    }
}

fn endpoint_reference_point(world_points: &[DrawPoint], endpoint: Endpoint) -> Option<DrawPoint> {
    if world_points.len() < 2 {
        return None;
    }
    match endpoint {
        Endpoint::Start => world_points.get(1).copied(),
        Endpoint::End => world_points
            .get(world_points.len().saturating_sub(2))
            .copied(),
    }
}

fn to_local_point(element: &ElementState, world_point: DrawPoint) -> DrawPoint {
    DrawPoint::new(
        world_point.x - element.rect.min_x,
        world_point.y - element.rect.min_y,
    )
}

fn has_bindable_targets(state: &DrawState, excluded_element_id: &str) -> bool {
    state.domain.document.elements.iter().any(|element| {
        element.id != excluded_element_id && ArrowBindingUtils::is_bindable_target(element)
    })
}

struct EndpointDragBindingResolver;

const ENDPOINT_DRAG_BINDING_RESOLVER: EndpointDragBindingResolver = EndpointDragBindingResolver;

impl SnapperBindingResolver<DomainElementState> for EndpointDragBindingResolver {
    fn is_bindable_target(&self, target: &DomainElementState) -> bool {
        ArrowBindingUtils::is_bindable_target(target)
    }

    fn resolve_binding_search_distance(&self, snap_distance: f64) -> f64 {
        ArrowBindingUtils::resolve_binding_search_distance(snap_distance)
    }

    fn resolve_binding_candidate_for_target(
        &self,
        world_point: DrawPoint,
        target: &DomainElementState,
        snap_distance: f64,
        reference_point: Option<DrawPoint>,
    ) -> Option<ArrowBindingResult> {
        ArrowBindingUtils::resolve_binding_candidate_for_target(
            world_point,
            target,
            snap_distance,
            reference_point,
        )
    }

    fn resolve_elbow_binding_candidate_for_target(
        &self,
        world_point: DrawPoint,
        target: &DomainElementState,
        snap_distance: f64,
        has_arrowhead: bool,
    ) -> Option<ArrowBindingResult> {
        ArrowBindingUtils::resolve_elbow_binding_candidate_for_target(
            world_point,
            target,
            snap_distance,
            has_arrowhead,
        )
    }

    fn resolve_binding_candidate(
        &self,
        world_point: DrawPoint,
        targets: &[DomainElementState],
        snap_distance: f64,
        preferred_binding: Option<&ArrowBinding>,
        allow_new_binding: bool,
        reference_point: Option<DrawPoint>,
    ) -> Option<ArrowBindingResult> {
        ArrowBindingUtils::resolve_binding_candidate(
            world_point,
            targets.iter(),
            snap_distance,
            preferred_binding,
            allow_new_binding,
            reference_point,
        )
    }

    fn resolve_elbow_binding_candidate(
        &self,
        world_point: DrawPoint,
        targets: &[DomainElementState],
        snap_distance: f64,
        preferred_binding: Option<&ArrowBinding>,
        allow_new_binding: bool,
        has_arrowhead: bool,
    ) -> Option<ArrowBindingResult> {
        ArrowBindingUtils::resolve_elbow_binding_candidate(
            world_point,
            targets.iter(),
            snap_distance,
            has_arrowhead,
            preferred_binding,
            allow_new_binding,
        )
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::{
        compute_arrow_core_endpoint_drag_result, finalize_arrow_core_endpoint_drag_result,
    };
    use crate::draw::elements::types::arrow::arrow_binding::{ArrowBinding, ArrowBindingMode};
    use crate::draw::elements::types::arrow::arrow_core::EngineContext;
    use crate::draw::elements::types::arrow::arrow_core_ops::ArrowCoreEndpointBindingOptions;
    use crate::draw::elements::types::arrow::arrow_data::{
        ArrowBinding as DataArrowBinding, ArrowBindingMode as DataArrowBindingMode, ArrowData,
        ArrowDataPatch,
    };
    use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
    use crate::draw::models::application_state::ApplicationState;
    use crate::draw::models::draw_state::{DomainDocumentState, DomainState, DrawState};
    use crate::draw::models::element_state::ElementState;
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::types::draw_rect::DrawRect;
    use crate::draw::types::element_style::ArrowType;

    fn binding(id: &str) -> ArrowBinding {
        ArrowBinding::new(
            id.to_owned(),
            DrawPoint::new(0.5, 0.5),
            ArrowBindingMode::Orbit,
        )
    }

    fn to_data_binding(binding: ArrowBinding) -> DataArrowBinding {
        DataArrowBinding::new(
            binding.element_id,
            binding.anchor,
            match binding.mode {
                ArrowBindingMode::Inside => DataArrowBindingMode::Inside,
                ArrowBindingMode::Orbit => DataArrowBindingMode::Orbit,
                ArrowBindingMode::Skip => DataArrowBindingMode::Skip,
            },
        )
    }

    fn arrow_data_with(
        start_binding: Option<ArrowBinding>,
        end_binding: Option<ArrowBinding>,
    ) -> ArrowData {
        ArrowData::default().copy_with(ArrowDataPatch {
            start_binding: match start_binding {
                Some(value) => {
                    crate::draw::elements::types::arrow::arrow_data::NullableField::Value(
                        to_data_binding(value),
                    )
                }
                None => crate::draw::elements::types::arrow::arrow_data::NullableField::Null,
            },
            end_binding: match end_binding {
                Some(value) => {
                    crate::draw::elements::types::arrow::arrow_data::NullableField::Value(
                        to_data_binding(value),
                    )
                }
                None => crate::draw::elements::types::arrow::arrow_data::NullableField::Null,
            },
            ..Default::default()
        })
    }

    fn arrow_element(id: &str, rect: DrawRect, data: ArrowData) -> ElementState {
        ElementState::new(id.to_owned(), rect, 0.0, 1.0, 10, Arc::new(data))
    }

    fn rectangle_element(id: &str, rect: DrawRect) -> ElementState {
        ElementState::new(
            id.to_owned(),
            rect,
            0.0,
            1.0,
            1,
            Arc::new(RectangleData::default()),
        )
    }

    fn draw_state(elements: Vec<ElementState>) -> DrawState {
        let domain = DomainState::new(
            DomainDocumentState::new(elements, 1, Default::default()),
            Default::default(),
        );
        DrawState::new(Some(domain), Some(ApplicationState::initial(None)))
    }

    #[test]
    fn compute_endpoint_drag_snaps_and_reports_suggested_binding() {
        let data = ArrowData::default();
        let arrow = arrow_element("arrow", DrawRect::new(0.0, 0.0, 20.0, 20.0), data.clone());
        let target = rectangle_element("box", DrawRect::new(90.0, 90.0, 130.0, 130.0));
        let state = draw_state(vec![target.clone(), arrow.clone()]);

        let result = compute_arrow_core_endpoint_drag_result(
            &state,
            &arrow,
            &data,
            &[DrawPoint::new(0.0, 10.0), DrawPoint::new(20.0, 10.0)],
            1,
            DrawPoint::new(110.0, 110.0),
            None,
            None,
            "arrow",
            true,
            true,
            40.0,
            EngineContext::new(1.0, true, "orbit", 1e6),
            None,
            None,
            ArrowCoreEndpointBindingOptions::default(),
        )
        .expect("endpoint drag result");

        assert_eq!(result.suggested_bindable_id.as_deref(), Some("box"));
        assert_eq!(
            result
                .end_binding
                .as_ref()
                .map(|value| value.element_id.as_str()),
            Some("box")
        );
        assert_eq!(result.start_binding, None);
    }

    #[test]
    fn compute_endpoint_drag_clears_dragged_binding_when_lookup_is_disabled() {
        let existing_start = binding("box");
        let data = arrow_data_with(Some(existing_start.clone()), None);
        let arrow = arrow_element("arrow", DrawRect::new(0.0, 0.0, 20.0, 20.0), data.clone());
        let target = rectangle_element("box", DrawRect::new(90.0, 90.0, 130.0, 130.0));
        let state = draw_state(vec![target, arrow.clone()]);

        let result = compute_arrow_core_endpoint_drag_result(
            &state,
            &arrow,
            &data,
            &[DrawPoint::new(0.0, 10.0), DrawPoint::new(20.0, 10.0)],
            0,
            DrawPoint::new(30.0, 30.0),
            Some(&existing_start),
            None,
            "arrow",
            false,
            true,
            20.0,
            EngineContext::new(1.0, true, "orbit", 1e6),
            None,
            None,
            ArrowCoreEndpointBindingOptions::default(),
        )
        .expect("endpoint drag result");

        assert_eq!(result.start_binding, None);
        assert_eq!(result.suggested_bindable_id, None);
    }

    #[test]
    fn finalize_endpoint_drag_closes_loop_and_reuses_opposite_binding() {
        let end_binding = binding("box");
        let data = arrow_data_with(None, Some(end_binding.clone())).copy_with(ArrowDataPatch {
            arrow_type: Some(ArrowType::Straight),
            ..Default::default()
        });
        let arrow = arrow_element("arrow", DrawRect::new(0.0, 0.0, 20.0, 20.0), data.clone());
        let target = rectangle_element("box", DrawRect::new(90.0, 90.0, 130.0, 130.0));
        let state = draw_state(vec![target, arrow.clone()]);

        let result = finalize_arrow_core_endpoint_drag_result(
            &state,
            &arrow,
            &data,
            &[DrawPoint::new(0.0, 10.0), DrawPoint::new(20.0, 10.0)],
            0,
            DrawPoint::new(20.0, 10.0),
            None,
            Some(&end_binding),
            "arrow",
            false,
            true,
            24.0,
            EngineContext::new(1.0, true, "orbit", 1e6),
            None,
            None,
            ArrowCoreEndpointBindingOptions::default(),
        )
        .expect("finalize drag result");

        assert_eq!(result.start_binding, Some(end_binding));
        assert_eq!(result.world_points.first(), result.world_points.last());
    }
}
