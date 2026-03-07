#![allow(dead_code)]

use std::collections::{HashMap, HashSet};

use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;

use super::arrow_binding::ArrowBinding;
use super::arrow_core::{ArrowState, BindableState, EngineContext};
use super::arrow_core_bridge::{
    apply_core_arrow_patches_to_sources, project_core_document, to_core_bindable_state,
    ArrowCoreDocumentProjection,
};
use super::core::arrow_hit_test::is_point_near_bindable_for_binding_hit as is_point_near_core_bindable_for_binding_hit;
use super::core::arrow_order_core::{
    reorder_arrow_above_hovered_bindable, reordered_element_ids_from_hovered_reorder,
};
use super::core::arrow_state_core::reduce_arrow_engine_events_to_order;
use super::core::arrow_types::{
    ArrowEngineEvent, ArrowStatePatchWithId, BindableRelationState,
    BindableState as CoreBindableState, ReduceArrowEngineEventsToOrderInput,
    ReorderArrowAboveHoveredBindableInput,
};

#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowBindableCandidates {
    pub elements: Vec<ElementState>,
    pub bindables: Vec<BindableState>,
    pub element_by_id: HashMap<String, ElementState>,
    pub bindable_by_id: HashMap<String, BindableState>,
}

impl ArrowBindableCandidates {
    pub fn empty() -> Self {
        Self::default()
    }

    pub fn is_empty(&self) -> bool {
        self.bindables.is_empty()
    }

    pub fn element_for_id(&self, id: &str) -> Option<&ElementState> {
        self.element_by_id.get(id)
    }

    pub fn bindable_for_id(&self, id: &str) -> Option<&BindableState> {
        self.bindable_by_id.get(id)
    }
}

pub fn project_arrow_bindable_candidates<I>(elements: I) -> ArrowBindableCandidates
where
    I: IntoIterator<Item = ElementState>,
{
    let mut seen_ids = HashSet::<String>::new();
    let mut projected_elements = Vec::new();
    let mut projected_bindables = Vec::new();
    let mut element_by_id = HashMap::new();
    let mut bindable_by_id = HashMap::new();

    for element in elements {
        if !seen_ids.insert(element.id.clone()) {
            continue;
        }
        let Some(bindable) = to_core_bindable_state(&element, Some(element.z_index as usize), true, true, Some(element.rect)) else {
            continue;
        };
        element_by_id.insert(element.id.clone(), element.clone());
        bindable_by_id.insert(bindable.id.clone(), bindable.clone());
        projected_elements.push(element);
        projected_bindables.push(bindable);
    }

    ArrowBindableCandidates {
        elements: projected_elements,
        bindables: projected_bindables,
        element_by_id,
        bindable_by_id,
    }
}

pub fn resolve_arrow_bindable_candidates<I>(
    elements: I,
    world_point: DrawPoint,
    distance: f64,
    preferred_binding: Option<&ArrowBinding>,
    opposite_binding: Option<&ArrowBinding>,
    excluded_element_id: Option<&str>,
) -> ArrowBindableCandidates
where
    I: IntoIterator<Item = ElementState>,
{
    let all = project_arrow_bindable_candidates(elements);
    if all.is_empty() {
        return ArrowBindableCandidates::empty();
    }

    let mut candidate_ids = HashSet::<String>::new();
    if let Some(binding) = preferred_binding {
        candidate_ids.insert(binding.element_id.clone());
    }
    if let Some(binding) = opposite_binding {
        candidate_ids.insert(binding.element_id.clone());
    }

    for bindable in &all.bindables {
        if excluded_element_id.is_some_and(|excluded| bindable.id == excluded) {
            continue;
        }
        if is_point_near_bindable_for_binding_hit(world_point, bindable, distance) {
            candidate_ids.insert(bindable.id.clone());
        }
    }

    if candidate_ids.is_empty() {
        return ArrowBindableCandidates::empty();
    }

    project_arrow_bindable_candidates(
        all.elements
            .into_iter()
            .filter(|element| candidate_ids.contains(element.id.as_str())),
    )
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowAppliedResult {
    pub ordered_element_ids: Option<Vec<String>>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowScene {
    pub candidates: ArrowBindableCandidates,
    pub projection: ArrowCoreDocumentProjection,
    pub context: EngineContext,
}

impl ArrowScene {
    pub fn from_elements<I>(elements: I, context: Option<EngineContext>) -> Self
    where
        I: IntoIterator<Item = ElementState>,
    {
        Self::from_elements_with_options(elements, false, None, context)
    }

    pub fn from_elements_with_options<I>(
        elements: I,
        only_bound_arrows: bool,
        ordered_element_ids: Option<&[String]>,
        context: Option<EngineContext>,
    ) -> Self
    where
        I: IntoIterator<Item = ElementState>,
    {
        let materialized = elements.into_iter().collect::<Vec<_>>();
        let projection = project_core_document(&materialized, only_bound_arrows, ordered_element_ids);
        let candidates = project_arrow_bindable_candidates(materialized);

        Self {
            candidates,
            projection,
            context: context.unwrap_or_else(|| {
                EngineContext::new(1.0, true, super::arrow_core::BIND_MODE_ORBIT, 1e6)
            }),
        }
    }

    pub fn bindables(&self) -> &[BindableState] {
        &self.projection.bindables
    }

    pub fn bindable_relations(&self) -> &[BindableRelationState] {
        &self.projection.bindable_relations
    }

    pub fn arrows(&self) -> &[ArrowState] {
        &self.projection.arrows
    }

    pub fn arrow_sources(
        &self,
    ) -> &HashMap<String, (ElementState, super::arrow_core_bridge::ConnectorSourceData)> {
        &self.projection.arrow_sources
    }

    pub fn ordered_element_ids(&self) -> &[String] {
        &self.projection.ordered_element_ids
    }

    pub fn anchor_element_ids_by_bindable_id(&self) -> &HashMap<String, Vec<String>> {
        &self.projection.anchor_element_ids_by_bindable_id
    }

    pub fn has_arrows(&self) -> bool {
        !self.projection.arrows.is_empty()
    }

    pub fn apply_arrow_patches(
        &self,
        patches: &[ArrowStatePatchWithId],
    ) -> HashMap<String, ElementState> {
        apply_core_arrow_patches_to_sources(patches, &self.projection.arrow_sources)
    }

    pub fn reduce_events_to_ordered_element_ids(
        &self,
        events: &[ArrowEngineEvent],
    ) -> Option<Vec<String>> {
        reduce_arrow_events_to_ordered_ids(
            &self.projection.ordered_element_ids,
            events,
            Some(&self.projection.anchor_element_ids_by_bindable_id),
        )
    }

    pub fn reorder_arrow_above_hovered_bindable(
        &self,
        arrow_id: &str,
        hovered_bindable_id: Option<&str>,
        point: Option<DrawPoint>,
        ordered_element_ids: Option<&[String]>,
        tolerance: Option<f64>,
    ) -> Option<Vec<String>> {
        let reorder = reorder_arrow_above_hovered_bindable(&ReorderArrowAboveHoveredBindableInput {
            ordered_element_ids: ordered_element_ids
                .map(|value| value.to_vec())
                .unwrap_or_else(|| self.projection.ordered_element_ids.clone()),
            arrow_id: arrow_id.to_string(),
            hovered_bindable_id: hovered_bindable_id.map(str::to_string),
            point,
            bindables: Some(
                self.projection
                    .bindables
                    .iter()
                    .map(to_order_core_bindable_state)
                    .collect(),
            ),
            tolerance,
            anchor_element_ids_by_bindable_id: Some(
                self.projection.anchor_element_ids_by_bindable_id.clone(),
            ),
        });
        reordered_element_ids_from_hovered_reorder(&reorder)
    }
}

pub fn reduce_arrow_events_to_ordered_ids(
    ordered_element_ids: &[String],
    events: &[ArrowEngineEvent],
    anchor_element_ids_by_bindable_id: Option<&HashMap<String, Vec<String>>>,
) -> Option<Vec<String>> {
    if ordered_element_ids.is_empty() || events.is_empty() {
        return None;
    }

    let result = reduce_arrow_engine_events_to_order(&ReduceArrowEngineEventsToOrderInput {
        ordered_element_ids: ordered_element_ids.to_vec(),
        events: events.to_vec(),
        anchor_element_ids_by_bindable_id: anchor_element_ids_by_bindable_id.cloned(),
    });
    if !result.moved || result.ordered_element_ids == ordered_element_ids {
        return None;
    }
    Some(result.ordered_element_ids)
}

fn is_point_near_bindable_for_binding_hit(
    point: DrawPoint,
    bindable: &BindableState,
    tolerance: f64,
) -> bool {
    let core_bindable = to_order_core_bindable_state(bindable);
    is_point_near_core_bindable_for_binding_hit(point, &core_bindable, tolerance)
}

fn to_order_core_bindable_state(bindable: &BindableState) -> CoreBindableState {
    CoreBindableState {
        id: bindable.id.clone(),
        shape: bindable.shape.as_str().to_string(),
        x: bindable.x,
        y: bindable.y,
        width: bindable.width,
        height: bindable.height,
        angle: bindable.angle,
        stroke_width: bindable.stroke_width,
        roundness: None,
        z_index: bindable.z_index,
        background_opaque: bindable.background_opaque,
        binding_enabled: bindable.binding_enabled,
        interior_hit_enabled: bindable.interior_hit_enabled,
        visibility_bounds: bindable.visibility_bounds,
    }
}
