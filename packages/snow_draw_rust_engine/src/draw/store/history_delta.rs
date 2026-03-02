#![allow(dead_code)]

use std::collections::BTreeMap;

use crate::draw::models::application_state::{IdleState, InteractionState, SelectionOverlayState};
use crate::draw::models::element_state::ElementState;
use crate::draw::models::global_elements_state::GlobalElementsState;
use crate::draw::models::selection_state::SelectionState;

/// Minimal compatibility document state used by [`HistoryDelta`] operations.
#[derive(Clone, Debug, PartialEq)]
pub struct DomainDocumentState {
    pub elements: Vec<ElementState>,
    pub global_elements: GlobalElementsState,
}

impl DomainDocumentState {
    pub fn new(elements: Vec<ElementState>, global_elements: GlobalElementsState) -> Self {
        Self {
            elements,
            global_elements,
        }
    }

    pub fn element_map(&self) -> BTreeMap<String, ElementState> {
        self.elements
            .iter()
            .cloned()
            .map(|element| (element.id.clone(), element))
            .collect()
    }

    pub fn order(&self) -> Vec<String> {
        self.elements
            .iter()
            .map(|element| element.id.clone())
            .collect()
    }

    pub fn copy_with(
        &self,
        elements: Option<Vec<ElementState>>,
        global_elements: Option<GlobalElementsState>,
    ) -> Self {
        Self {
            elements: elements.unwrap_or_else(|| self.elements.clone()),
            global_elements: global_elements.unwrap_or_else(|| self.global_elements.clone()),
        }
    }
}

impl Default for DomainDocumentState {
    fn default() -> Self {
        Self {
            elements: Vec::new(),
            global_elements: GlobalElementsState::default(),
        }
    }
}

/// Minimal compatibility domain state used by [`HistoryDelta`] operations.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct DomainState {
    pub document: DomainDocumentState,
    pub selection: SelectionState,
}

impl DomainState {
    pub fn new(document: DomainDocumentState, selection: SelectionState) -> Self {
        Self {
            document,
            selection,
        }
    }

    pub fn copy_with(
        &self,
        document: Option<DomainDocumentState>,
        selection: Option<SelectionState>,
    ) -> Self {
        Self {
            document: document.unwrap_or_else(|| self.document.clone()),
            selection: selection.unwrap_or_else(|| self.selection.clone()),
        }
    }
}

/// Minimal compatibility application state used by [`HistoryDelta`] operations.
#[derive(Clone, Debug, PartialEq)]
pub struct ApplicationState {
    pub interaction: InteractionState,
    pub selection_overlay: SelectionOverlayState,
}

impl ApplicationState {
    pub fn new(interaction: InteractionState, selection_overlay: SelectionOverlayState) -> Self {
        Self {
            interaction,
            selection_overlay,
        }
    }

    pub fn copy_with(
        &self,
        interaction: Option<InteractionState>,
        selection_overlay: Option<SelectionOverlayState>,
    ) -> Self {
        Self {
            interaction: interaction.unwrap_or_else(|| self.interaction.clone()),
            selection_overlay: selection_overlay.unwrap_or_else(|| self.selection_overlay.clone()),
        }
    }
}

impl Default for ApplicationState {
    fn default() -> Self {
        Self {
            interaction: InteractionState::Idle(IdleState),
            selection_overlay: SelectionOverlayState::empty(),
        }
    }
}

/// Minimal compatibility draw state used by [`HistoryDelta`] operations.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct DrawState {
    pub domain: DomainState,
    pub application: ApplicationState,
}

impl DrawState {
    pub fn new(domain: DomainState, application: ApplicationState) -> Self {
        Self {
            domain,
            application,
        }
    }

    pub fn copy_with(
        &self,
        domain: Option<DomainState>,
        application: Option<ApplicationState>,
    ) -> Self {
        Self {
            domain: domain.unwrap_or_else(|| self.domain.clone()),
            application: application.unwrap_or_else(|| self.application.clone()),
        }
    }
}

/// Snapshot payload used to compute history deltas.
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

        Self::new(
            state.domain.document.elements.clone(),
            selection,
            include_selection,
            state.domain.document.global_elements.clone(),
            Some(state.domain.document.element_map()),
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

    pub fn selection_changed(&self) -> bool {
        self.selection_before != self.selection_after
    }

    pub fn has_changes(&self) -> bool {
        !self.before_elements.is_empty()
            || !self.after_elements.is_empty()
            || self.global_elements_before.is_some()
            || self.global_elements_after.is_some()
            || self.order_changed
            || self.selection_changed()
    }

    pub fn apply_backward(&self, state: &DrawState) -> DrawState {
        self.apply(state, false)
    }

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

        let next_document = state
            .domain
            .document
            .copy_with(Some(next_elements), global_elements.cloned());
        let next_domain = state.domain.copy_with(
            Some(next_document),
            Some(
                selection
                    .cloned()
                    .unwrap_or_else(|| state.domain.selection.clone()),
            ),
        );
        let next_application = state.application.copy_with(
            Some(InteractionState::Idle(IdleState)),
            Some(SelectionOverlayState::empty()),
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
