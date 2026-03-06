#![allow(dead_code)]

use std::collections::{HashMap, HashSet};

use crate::draw::models::document_state::{DocumentState, ElementState};
use crate::draw::types::draw_point::DrawPoint;

use super::arrow_binding::ArrowBinding;

/// Ordered bindable candidates projected for arrow algorithm queries.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowBindableCandidates {
    pub elements: Vec<ElementState>,
    pub element_by_id: HashMap<String, ElementState>,
}

impl ArrowBindableCandidates {
    pub fn empty() -> Self {
        Self::default()
    }

    pub fn is_empty(&self) -> bool {
        self.elements.is_empty()
    }

    pub fn element_for_id(&self, id: &str) -> Option<&ElementState> {
        self.element_by_id.get(id)
    }
}

/// Projects ordered bindable candidates from an iterator of elements.
pub fn project_arrow_bindable_candidates<I>(elements: I) -> ArrowBindableCandidates
where
    I: IntoIterator<Item = ElementState>,
{
    let elements = elements.into_iter().collect::<Vec<_>>();
    let element_by_id = elements
        .iter()
        .cloned()
        .map(|element| (element.id.clone(), element))
        .collect();
    ArrowBindableCandidates {
        elements,
        element_by_id,
    }
}

/// Resolves nearby bindable candidates for arrow binding queries.
pub fn resolve_arrow_bindable_candidates(
    document: &DocumentState,
    world_point: DrawPoint,
    distance: f64,
    preferred_binding: Option<&ArrowBinding>,
    opposite_binding: Option<&ArrowBinding>,
    excluded_element_id: Option<&str>,
) -> ArrowBindableCandidates {
    let mut candidate_ids = HashSet::<String>::new();
    if let Some(binding) = preferred_binding {
        candidate_ids.insert(binding.element_id.clone());
    }
    if let Some(binding) = opposite_binding {
        candidate_ids.insert(binding.element_id.clone());
    }

    document.visit_arrow_bindable_elements_at_point(
        world_point,
        distance,
        excluded_element_id,
        |element| {
            candidate_ids.insert(element.id.clone());
            true
        },
    );

    if candidate_ids.is_empty() {
        return ArrowBindableCandidates::empty();
    }

    project_arrow_bindable_candidates(
        document
            .elements
            .iter()
            .filter(|element| candidate_ids.contains(element.id.as_str()))
            .cloned(),
    )
}
