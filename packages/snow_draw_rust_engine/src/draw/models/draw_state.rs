#![allow(dead_code)]

use std::collections::HashMap;
use std::fmt;

use crate::draw::elements::types::highlight::highlight_data::HighlightData;
use crate::draw::models::application_state::{
    ApplicationState, IdleState, InteractionState, SelectionOverlayState, ViewState,
};
use crate::draw::models::element_state::ElementState;
use crate::draw::models::global_elements_state::GlobalElementsState;
use crate::draw::models::selection_state::SelectionState;

pub type DomainElementState = ElementState;
pub type DomainSelectionState = SelectionState;

/// Persisted document data used by draw-domain state.
#[derive(Clone, Debug, PartialEq)]
pub struct DomainDocumentState {
    pub elements: Vec<DomainElementState>,
    pub elements_version: i64,
    pub global_elements: GlobalElementsState,
}

impl DomainDocumentState {
    pub fn new(
        elements: Vec<DomainElementState>,
        elements_version: i64,
        global_elements: GlobalElementsState,
    ) -> Self {
        Self {
            elements,
            elements_version,
            global_elements,
        }
    }

    pub fn get_element_by_id(&self, id: &str) -> Option<&DomainElementState> {
        self.elements.iter().find(|element| element.id == id)
    }

    pub fn element_map(&self) -> HashMap<String, DomainElementState> {
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
        elements: Option<Vec<DomainElementState>>,
        global_elements: Option<GlobalElementsState>,
        elements_version: Option<i64>,
    ) -> Self {
        let next_elements = elements.unwrap_or_else(|| self.elements.clone());
        let next_global_elements = global_elements.unwrap_or_else(|| self.global_elements.clone());
        let changed =
            next_elements != self.elements || next_global_elements != self.global_elements;
        let next_elements_version = elements_version.unwrap_or_else(|| {
            if changed {
                self.elements_version.saturating_add(1)
            } else {
                self.elements_version
            }
        });

        Self {
            elements: next_elements,
            elements_version: next_elements_version,
            global_elements: next_global_elements,
        }
    }

    pub fn highlight_elements(&self) -> Vec<DomainElementState> {
        self.elements
            .iter()
            .filter(|element| element.data.type_id().as_str() == HighlightData::TYPE_ID_TOKEN)
            .cloned()
            .collect()
    }
}

impl Default for DomainDocumentState {
    fn default() -> Self {
        Self::new(Vec::new(), 0, GlobalElementsState::default())
    }
}

/// Domain-layer state.
///
/// Includes all state that must be persisted and participates in undo/redo.
#[derive(Clone, Debug, PartialEq)]
pub struct DomainState {
    pub document: DomainDocumentState,
    pub selection: DomainSelectionState,
}

impl DomainState {
    pub fn new(document: DomainDocumentState, selection: DomainSelectionState) -> Self {
        Self {
            document,
            selection,
        }
    }

    pub fn empty() -> Self {
        Self::default()
    }

    pub fn copy_with(
        &self,
        document: Option<DomainDocumentState>,
        selection: Option<DomainSelectionState>,
    ) -> Self {
        Self {
            document: document.unwrap_or_else(|| self.document.clone()),
            selection: selection.unwrap_or_else(|| self.selection.clone()),
        }
    }
}

impl Default for DomainState {
    fn default() -> Self {
        Self {
            document: DomainDocumentState::default(),
            selection: DomainSelectionState::default(),
        }
    }
}

/// Aggregate root for draw state.
///
/// Coordinates domain and application state with a unified access interface.
#[derive(Clone, Debug, PartialEq)]
pub struct DrawState {
    /// Domain state (participates in undo/redo and is persisted).
    pub domain: DomainState,
    /// Application state (temporary, not part of undo/redo).
    pub application: ApplicationState,
}

impl DrawState {
    /// Creates a draw state, defaulting missing sections to their initial values.
    pub fn new(domain: Option<DomainState>, application: Option<ApplicationState>) -> Self {
        Self {
            domain: domain.unwrap_or_else(DomainState::empty),
            application: application.unwrap_or_else(|| ApplicationState::initial(None)),
        }
    }

    /// Factory method: create initial state.
    pub fn initial(view: Option<ViewState>) -> Self {
        Self {
            domain: DomainState::empty(),
            application: ApplicationState::initial(view),
        }
    }

    /// Returns a copy with selectively replaced fields.
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

    /// Get the domain snapshot used for history.
    pub fn domain_snapshot(&self) -> DomainState {
        self.domain.clone()
    }

    /// Restore domain state from history.
    pub fn restore_from_snapshot(&self, snapshot: DomainState) -> Self {
        Self {
            domain: snapshot,
            application: self.application.copy_with(
                None,
                Some(InteractionState::Idle(IdleState)),
                Some(SelectionOverlayState::EMPTY),
            ),
        }
    }
}

impl Default for DrawState {
    fn default() -> Self {
        Self::new(None, None)
    }
}

impl fmt::Display for DrawState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "DrawState(elements: {}, selection: {:?}, interaction: {:?})",
            self.domain.document.elements.len(),
            self.domain.selection.selected_ids,
            self.application.interaction
        )
    }
}
