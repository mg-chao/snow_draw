#![allow(dead_code)]

use std::collections::BTreeMap;

use crate::draw::models::application_state::{IdleState, InteractionState, SelectionOverlayState};
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::element_state::ElementState;
use crate::draw::models::global_elements_state::GlobalElementsState;
use crate::draw::models::selection_state::SelectionState;
use crate::draw::store::snapshot::PersistentSnapshot;

/// Immutable delta between two history snapshots.
#[derive(Clone, Debug, PartialEq)]
pub struct HistoryDelta {
    pub before_elements: BTreeMap<String, ElementState>,
    pub after_elements: BTreeMap<String, ElementState>,
    pub global_elements_before: Option<GlobalElementsState>,
    pub global_elements_after: Option<GlobalElementsState>,
    pub order_before: Vec<String>,
    pub order_after: Vec<String>,
    pub order_changed: bool,
    pub selection_before: Option<SelectionState>,
    pub selection_after: Option<SelectionState>,
}

impl HistoryDelta {
    /// Creates a history delta from two snapshots.
    pub fn from_snapshots(before: &PersistentSnapshot, after: &PersistentSnapshot) -> Self {
        let mut before_elements = BTreeMap::<String, ElementState>::new();
        let mut after_elements = BTreeMap::<String, ElementState>::new();
        collect_changed_elements_by_scan(
            &before.element_map,
            &after.element_map,
            &mut before_elements,
            &mut after_elements,
        );

        let order_before = before.order.clone();
        let order_after = after.order.clone();
        let order_changed = order_before != order_after;

        let (global_elements_before, global_elements_after) =
            if before.global_elements != after.global_elements {
                (
                    Some(before.global_elements.clone()),
                    Some(after.global_elements.clone()),
                )
            } else {
                (None, None)
            };

        let (selection_before, selection_after) = if before.include_selection
            && after.include_selection
            && before.selection != after.selection
        {
            (
                Some(copy_selection(&before.selection)),
                Some(copy_selection(&after.selection)),
            )
        } else {
            (None, None)
        };

        Self {
            before_elements,
            after_elements,
            global_elements_before,
            global_elements_after,
            order_before,
            order_after,
            order_changed,
            selection_before,
            selection_after,
        }
    }

    /// Whether selection changed in this delta.
    pub fn selection_changed(&self) -> bool {
        self.selection_before != self.selection_after
    }

    /// Whether this delta contains any effective change.
    pub fn has_changes(&self) -> bool {
        !self.before_elements.is_empty()
            || !self.after_elements.is_empty()
            || self.global_elements_before.is_some()
            || self.global_elements_after.is_some()
            || self.order_changed
            || self.selection_changed()
    }

    /// Applies the backward side of the delta to state.
    pub fn apply_backward(&self, state: &DrawState) -> DrawState {
        self.apply(state, false)
    }

    /// Applies the forward side of the delta to state.
    pub fn apply_forward(&self, state: &DrawState) -> DrawState {
        self.apply(state, true)
    }

    fn apply(&self, state: &DrawState, forward: bool) -> DrawState {
        let current_by_id = state
            .domain
            .document
            .elements
            .iter()
            .cloned()
            .map(|element| (element.id.clone(), element))
            .collect::<BTreeMap<_, _>>();

        let target_elements = if forward {
            &self.after_elements
        } else {
            &self.before_elements
        };
        let removed_ids = if forward {
            self.before_elements.keys()
        } else {
            self.after_elements.keys()
        };
        let retained_ids = if forward {
            &self.after_elements
        } else {
            &self.before_elements
        };

        let mut next_by_id = current_by_id;
        for id in removed_ids {
            if !retained_ids.contains_key(id) {
                next_by_id.remove(id);
            }
        }
        for (id, element) in target_elements {
            next_by_id.insert(id.clone(), element.clone());
        }

        let target_order = if forward {
            &self.order_after
        } else {
            &self.order_before
        };
        let mut next_elements = Vec::<ElementState>::with_capacity(target_order.len());
        for id in target_order {
            if let Some(element) = next_by_id.get(id) {
                next_elements.push(element.clone());
            }
        }

        let selection = if forward {
            self.selection_after.as_ref()
        } else {
            self.selection_before.as_ref()
        };
        let global_elements = if forward {
            self.global_elements_after.as_ref()
        } else {
            self.global_elements_before.as_ref()
        };

        let next_document =
            state
                .domain
                .document
                .copy_with(Some(next_elements), global_elements.cloned(), None);
        let next_domain = state.domain.copy_with(
            Some(next_document),
            Some(
                selection
                    .cloned()
                    .unwrap_or_else(|| state.domain.selection.clone()),
            ),
        );
        let next_application = state.application.copy_with(
            None,
            Some(InteractionState::Idle(IdleState)),
            Some(SelectionOverlayState::EMPTY),
        );

        state.copy_with(Some(next_domain), Some(next_application))
    }
}

fn collect_changed_elements_by_scan(
    before_by_id: &BTreeMap<String, ElementState>,
    after_by_id: &BTreeMap<String, ElementState>,
    before_elements: &mut BTreeMap<String, ElementState>,
    after_elements: &mut BTreeMap<String, ElementState>,
) {
    for (id, before_element) in before_by_id {
        match after_by_id.get(id) {
            None => {
                before_elements.insert(id.clone(), before_element.clone());
            }
            Some(after_element) if after_element != before_element => {
                before_elements.insert(id.clone(), before_element.clone());
                after_elements.insert(id.clone(), after_element.clone());
            }
            Some(_) => {}
        }
    }

    for (id, after_element) in after_by_id {
        if !before_by_id.contains_key(id) {
            after_elements.insert(id.clone(), after_element.clone());
        }
    }
}

fn copy_selection(selection: &SelectionState) -> SelectionState {
    SelectionState::new(selection.selected_ids.clone(), selection.selection_version)
}
