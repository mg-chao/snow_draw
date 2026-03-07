#![allow(dead_code)]

use std::collections::BTreeMap;
use std::fmt;

use crate::draw::models::draw_state::DrawState;
use crate::draw::models::element_state::ElementState;
use crate::draw::models::global_elements_state::GlobalElementsState;
use crate::draw::models::selection_state::SelectionState;

/// Immutable snapshot of persisted draw state for history/delta operations.
///
/// This mirrors the Dart `PersistentSnapshot` semantics:
/// - `element_map` and `order` default to values derived from `elements`
/// - selection can be excluded from comparisons via `include_selection`
#[derive(Clone, Debug)]
pub struct PersistentSnapshot {
    pub elements: Vec<ElementState>,
    pub element_map: BTreeMap<String, ElementState>,
    pub global_elements: GlobalElementsState,
    pub selection: SelectionState,
    pub include_selection: bool,
    pub order: Vec<String>,
}

impl PersistentSnapshot {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        elements: Vec<ElementState>,
        selection: SelectionState,
        include_selection: bool,
        global_elements: GlobalElementsState,
        element_map: Option<BTreeMap<String, ElementState>>,
        order: Option<Vec<String>>,
    ) -> Self {
        let element_map = element_map.unwrap_or_else(|| {
            elements
                .iter()
                .cloned()
                .map(|element| (element.id.clone(), element))
                .collect()
        });
        let order =
            order.unwrap_or_else(|| elements.iter().map(|element| element.id.clone()).collect());

        Self {
            elements,
            element_map,
            global_elements,
            selection,
            include_selection,
            order,
        }
    }

    pub fn from_state(state: &DrawState, include_selection: bool) -> Self {
        let selection = if include_selection {
            state.domain.selection.clone()
        } else {
            SelectionState::default()
        };

        let element_map = state
            .domain
            .document
            .element_map()
            .into_iter()
            .collect::<BTreeMap<_, _>>();

        Self::new(
            state.domain.document.elements.clone(),
            selection,
            include_selection,
            state.domain.document.global_elements.clone(),
            Some(element_map),
            Some(state.domain.document.order()),
        )
    }

    fn comparable_selection(&self) -> Option<&SelectionState> {
        if self.include_selection {
            Some(&self.selection)
        } else {
            None
        }
    }
}

impl PartialEq for PersistentSnapshot {
    fn eq(&self, other: &Self) -> bool {
        self.elements == other.elements
            && self.global_elements == other.global_elements
            && self.include_selection == other.include_selection
            && self.comparable_selection() == other.comparable_selection()
    }
}

impl fmt::Display for PersistentSnapshot {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "PersistentSnapshot(elements: {}, includeSelection: {})",
            self.elements.len(),
            self.include_selection
        )
    }
}
