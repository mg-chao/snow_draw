#![allow(dead_code)]

use std::collections::{HashMap, HashSet};

use crate::draw::models::draw_state::DomainDocumentState;
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;

use super::arrow_binding::{ArrowBinding, ArrowBindingUtils};
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
        let Some(bindable) = to_core_bindable_state(
            &element,
            Some(element.z_index as usize),
            true,
            true,
            Some(element.rect),
        ) else {
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

pub fn resolve_arrow_bindable_candidates(
    document: &DomainDocumentState,
    world_point: DrawPoint,
    distance: f64,
    preferred_binding: Option<&ArrowBinding>,
    opposite_binding: Option<&ArrowBinding>,
    excluded_element_id: Option<&str>,
    include_nearby: bool,
) -> ArrowBindableCandidates {
    let mut candidate_ids = HashSet::<String>::new();
    if let Some(binding) = preferred_binding {
        candidate_ids.insert(binding.element_id.clone());
    }
    if let Some(binding) = opposite_binding {
        candidate_ids.insert(binding.element_id.clone());
    }

    if include_nearby && distance > 0.0 && document.has_arrow_bindable_elements() {
        for element in document.query_arrow_bindable_elements_at_point_top_down(
            world_point,
            distance,
            excluded_element_id,
            true,
        ) {
            candidate_ids.insert(element.id);
        }
    }

    if candidate_ids.is_empty() {
        return ArrowBindableCandidates::empty();
    }

    project_arrow_bindable_candidates(
        document
            .elements
            .iter()
            .cloned()
            .into_iter()
            .filter(|element| candidate_ids.contains(element.id.as_str())),
    )
}
pub fn resolve_arrow_bindable_candidates_for_endpoint_strategy(
    document: &DomainDocumentState,
    allow_new_binding: bool,
    active_binding: Option<&ArrowBinding>,
    opposite_binding: Option<&ArrowBinding>,
    excluded_element_id: Option<&str>,
    ordered_element_ids: Option<&[String]>,
) -> ArrowBindableCandidates {
    let ordered_ids_storage;
    let ordered_ids = match ordered_element_ids {
        Some(ids) if !ids.is_empty() => ids,
        _ => {
            ordered_ids_storage = document.ordered_element_ids();
            ordered_ids_storage.as_slice()
        }
    };
    let has_order_override = ordered_element_ids.is_some_and(|ids| !ids.is_empty());

    let mut bound_ids = HashSet::<&str>::new();
    if let Some(binding) = active_binding {
        if !binding.element_id.is_empty() {
            bound_ids.insert(binding.element_id.as_str());
        }
    }
    if let Some(binding) = opposite_binding {
        if !binding.element_id.is_empty() {
            bound_ids.insert(binding.element_id.as_str());
        }
    }
    if !allow_new_binding && bound_ids.is_empty() {
        return ArrowBindableCandidates::empty();
    }

    let mut elements = Vec::<ElementState>::new();
    for (index, element_id) in ordered_ids.iter().enumerate() {
        if excluded_element_id.is_some_and(|excluded| excluded == element_id.as_str()) {
            continue;
        }
        if !allow_new_binding && !bound_ids.contains(element_id.as_str()) {
            continue;
        }

        let Some(element) = document.get_element_by_id(element_id).cloned() else {
            continue;
        };
        if !ArrowBindingUtils::is_bindable_target(&element) {
            continue;
        }

        let adjusted = if has_order_override {
            element.copy_with(None, None, None, None, Some(index as i64), None)
        } else {
            element
        };
        elements.push(adjusted);
    }

    if elements.is_empty() {
        return ArrowBindableCandidates::empty();
    }
    project_arrow_bindable_candidates(elements)
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
    pub fn from_document(document: &DomainDocumentState, context: Option<EngineContext>) -> Self {
        Self::from_elements_with_options(
            document.elements.iter().cloned(),
            false,
            Some(&document.ordered_element_ids()),
            context,
        )
    }

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
        let projection =
            project_core_document(&materialized, only_bound_arrows, ordered_element_ids);
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
        let reorder =
            reorder_arrow_above_hovered_bindable(&ReorderArrowAboveHoveredBindableInput {
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

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::{
        resolve_arrow_bindable_candidates, resolve_arrow_bindable_candidates_for_endpoint_strategy,
    };
    use crate::draw::elements::types::arrow::arrow_binding::{ArrowBinding, ArrowBindingMode};
    use crate::draw::elements::types::rectangle::rectangle_data::{
        RectangleData, RectangleDataPatch,
    };
    use crate::draw::models::draw_state::DomainDocumentState;
    use crate::draw::models::element_state::ElementState;
    use crate::draw::models::global_elements_state::GlobalElementsState;
    use crate::draw::types::draw_color::DrawColor;
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::types::draw_rect::DrawRect;

    fn bindable(id: &str, z_index: i64) -> ElementState {
        let data = RectangleData::default().copy_with(RectangleDataPatch {
            fill_color: Some(DrawColor::new(0xFF12_3456)),
            ..RectangleDataPatch::default()
        });
        ElementState::new(
            id,
            DrawRect::new(0.0, 0.0, 20.0, 20.0),
            0.0,
            1.0,
            z_index,
            Arc::new(data),
        )
    }

    fn binding(id: &str) -> ArrowBinding {
        ArrowBinding::new(id, DrawPoint::new(0.5, 0.5), ArrowBindingMode::Orbit)
    }

    fn transparent_bindable(id: &str, z_index: i64) -> ElementState {
        let data = RectangleData::default().copy_with(RectangleDataPatch {
            fill_color: Some(DrawColor::new(0x0012_3456)),
            ..RectangleDataPatch::default()
        });
        ElementState::new(
            id,
            DrawRect::new(0.0, 0.0, 20.0, 20.0),
            0.0,
            1.0,
            z_index,
            Arc::new(data),
        )
    }

    #[test]
    fn resolve_candidates_stops_at_first_opaque_nearby_hit() {
        let document = DomainDocumentState::new(
            vec![bindable("bottom", 0), bindable("top", 1)],
            0,
            GlobalElementsState::default(),
        );

        let candidates = resolve_arrow_bindable_candidates(
            &document,
            DrawPoint::new(1.0, 10.0),
            2.0,
            None,
            None,
            None,
            true,
        );
        let ids = candidates
            .elements
            .iter()
            .map(|element| element.id.as_str())
            .collect::<Vec<_>>();

        assert_eq!(ids, vec!["top"]);
    }

    #[test]
    fn resolve_candidates_merge_bound_targets_with_nearby_hits_in_document_order() {
        let document = DomainDocumentState::new(
            vec![bindable("bottom", 0), transparent_bindable("top", 1)],
            0,
            GlobalElementsState::default(),
        );

        let candidates = resolve_arrow_bindable_candidates(
            &document,
            DrawPoint::new(1.0, 10.0),
            2.0,
            Some(&binding("bottom")),
            None,
            None,
            true,
        );
        let ids = candidates
            .elements
            .iter()
            .map(|element| element.id.as_str())
            .collect::<Vec<_>>();

        assert_eq!(ids, vec!["bottom", "top"]);
    }

    #[test]
    fn resolve_candidates_can_skip_nearby_bindables() {
        let document = DomainDocumentState::new(
            vec![bindable("bottom", 0), bindable("top", 1)],
            0,
            GlobalElementsState::default(),
        );

        let candidates = resolve_arrow_bindable_candidates(
            &document,
            DrawPoint::new(1.0, 10.0),
            2.0,
            Some(&binding("bottom")),
            None,
            None,
            false,
        );
        let ids = candidates
            .elements
            .iter()
            .map(|element| element.id.as_str())
            .collect::<Vec<_>>();

        assert_eq!(ids, vec!["bottom"]);
    }

    #[test]
    fn scene_from_document_preserves_document_order() {
        let document = DomainDocumentState::new(
            vec![bindable("a", 0), bindable("b", 1), bindable("c", 2)],
            0,
            GlobalElementsState::default(),
        );

        let scene = super::ArrowScene::from_document(&document, None);

        assert_eq!(
            scene.ordered_element_ids(),
            &["a".to_owned(), "b".to_owned(), "c".to_owned()]
        );
    }

    #[test]
    fn endpoint_strategy_respects_order_override_for_new_bindings() {
        let document = DomainDocumentState::new(
            vec![bindable("a", 0), bindable("b", 1), bindable("c", 2)],
            0,
            GlobalElementsState::default(),
        );
        let ordered_ids = vec!["c".to_owned(), "a".to_owned(), "b".to_owned()];

        let candidates = resolve_arrow_bindable_candidates_for_endpoint_strategy(
            &document,
            true,
            None,
            None,
            None,
            Some(ordered_ids.as_slice()),
        );

        let ids = candidates
            .elements
            .iter()
            .map(|element| element.id.as_str())
            .collect::<Vec<_>>();
        assert_eq!(ids, vec!["c", "a", "b"]);
        assert_eq!(
            candidates
                .bindable_for_id("c")
                .and_then(|bindable| bindable.z_index),
            Some(0.0)
        );
        assert_eq!(
            candidates
                .bindable_for_id("a")
                .and_then(|bindable| bindable.z_index),
            Some(1.0)
        );
        assert_eq!(
            candidates
                .bindable_for_id("b")
                .and_then(|bindable| bindable.z_index),
            Some(2.0)
        );
    }

    #[test]
    fn endpoint_strategy_keeps_only_bound_targets_when_new_binding_is_disabled() {
        let document = DomainDocumentState::new(
            vec![bindable("a", 0), bindable("b", 1), bindable("c", 2)],
            0,
            GlobalElementsState::default(),
        );

        let candidates = resolve_arrow_bindable_candidates_for_endpoint_strategy(
            &document,
            false,
            Some(&binding("b")),
            Some(&binding("c")),
            None,
            None,
        );

        let ids = candidates
            .elements
            .iter()
            .map(|element| element.id.as_str())
            .collect::<Vec<_>>();
        assert_eq!(ids, vec!["b", "c"]);
    }
}
