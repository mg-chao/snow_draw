#![allow(dead_code)]

use std::collections::{BTreeSet, HashMap, HashSet};

use crate::draw::elements::types::highlight::highlight_data::HighlightData;
use crate::draw::models::draw_state::{DomainDocumentState, DrawState};
use crate::draw::models::global_elements_state::GlobalElementsState;
use crate::draw::models::interaction_state::{CreatingState, InteractionState};
use crate::draw::services::selection_data_computer::SelectionDataComputer;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::snap_guides::{snap_guide_list_equals, SnapGuide};

pub type DocumentState = DomainDocumentState;
pub use crate::draw::models::element_state::ElementState;

/// Effective selection view (considering edit preview).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EffectiveSelection {
    pub bounds: Option<DrawRect>,
    pub center: Option<DrawPoint>,
    pub rotation: Option<f64>,
    pub has_selection: bool,
}

impl EffectiveSelection {
    pub const NONE: Self = Self {
        bounds: None,
        center: None,
        rotation: None,
        has_selection: false,
    };

    pub fn new(
        bounds: Option<DrawRect>,
        center: Option<DrawPoint>,
        rotation: Option<f64>,
        has_selection: bool,
    ) -> Self {
        Self {
            bounds,
            center,
            rotation,
            has_selection,
        }
    }
}

impl Default for EffectiveSelection {
    fn default() -> Self {
        Self::NONE
    }
}

/// Precomputed highlight elements used by highlight-mask rendering.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct HighlightMaskSceneSnapshot {
    elements: Vec<ElementState>,
}

impl HighlightMaskSceneSnapshot {
    pub fn new(elements: Vec<ElementState>) -> Self {
        Self { elements }
    }

    pub fn empty() -> Self {
        Self {
            elements: Vec::new(),
        }
    }

    pub fn elements(&self) -> &[ElementState] {
        &self.elements
    }

    pub fn has_highlights(&self) -> bool {
        !self.elements.is_empty()
    }
}

/// A unified effective-state view for rendering and hit-testing.
#[derive(Clone, Debug)]
pub struct DrawStateView {
    pub state: DrawState,
    preview_elements_by_id: HashMap<String, ElementState>,
    effective_selection: EffectiveSelection,
    pub snap_guides: Vec<SnapGuide>,
    highlight_mask_scene: HighlightMaskSceneSnapshot,
}

impl DrawStateView {
    fn new_internal(
        state: DrawState,
        preview_elements_by_id: HashMap<String, ElementState>,
        effective_selection: EffectiveSelection,
        snap_guides: Vec<SnapGuide>,
    ) -> Self {
        let mut view = Self {
            state,
            preview_elements_by_id,
            effective_selection,
            snap_guides,
            highlight_mask_scene: HighlightMaskSceneSnapshot::empty(),
        };
        view.highlight_mask_scene = view.build_highlight_mask_scene();
        view
    }

    /// Creates a view from persistent state only (no edit preview).
    pub fn from_state(state: DrawState) -> Self {
        Self::from_state_with_snap_guides(state, Vec::new())
    }

    /// Creates a view from persistent state and explicit snap guides.
    pub fn from_state_with_snap_guides(state: DrawState, snap_guides: Vec<SnapGuide>) -> Self {
        let selection = SelectionDataComputer::compute(&state);
        let effective_selection = if selection.has_selection() {
            EffectiveSelection::new(
                selection.overlay_bounds,
                selection.overlay_center,
                selection.overlay_rotation,
                true,
            )
        } else {
            EffectiveSelection::NONE
        };

        Self::new_internal(state, HashMap::new(), effective_selection, snap_guides)
    }

    /// Creates a view from persistent state and preview-derived values.
    pub fn with_preview(
        state: DrawState,
        preview_elements_by_id: HashMap<String, ElementState>,
        effective_selection: EffectiveSelection,
        snap_guides: Vec<SnapGuide>,
    ) -> Self {
        Self::new_internal(
            state,
            preview_elements_by_id,
            effective_selection,
            snap_guides,
        )
    }

    /// Cached highlight-scene payload for highlight-mask rendering.
    pub fn highlight_mask_scene(&self) -> &HighlightMaskSceneSnapshot {
        &self.highlight_mask_scene
    }

    /// Map of element IDs to their preview states.
    pub fn preview_elements_by_id(&self) -> &HashMap<String, ElementState> {
        &self.preview_elements_by_id
    }

    /// IDs of elements currently being previewed.
    pub fn preview_element_ids(&self) -> HashSet<String> {
        self.preview_elements_by_id.keys().cloned().collect()
    }

    /// Returns the effective preview element for `element`.
    pub fn effective_element(&self, element: &ElementState) -> ElementState {
        self.preview_elements_by_id
            .get(&element.id)
            .cloned()
            .unwrap_or_else(|| element.clone())
    }

    /// Effective selection overlay values.
    pub fn effective_selection(&self) -> EffectiveSelection {
        self.effective_selection
    }

    /// All persistent document elements in z-order.
    pub fn elements(&self) -> &[ElementState] {
        &self.state.domain.document.elements
    }

    /// Selected IDs.
    pub fn selected_ids(&self) -> &BTreeSet<String> {
        &self.state.domain.selection.selected_ids
    }

    /// Effective global document elements.
    pub fn global_elements(&self) -> &GlobalElementsState {
        &self.state.domain.document.global_elements
    }

    /// True if there is an active selection (persistent or preview).
    pub fn has_selection(&self) -> bool {
        self.effective_selection.has_selection
    }

    /// Selected elements in document render (z) order.
    pub fn selected_elements(&self) -> Vec<ElementState> {
        let selected_ids = &self.state.domain.selection.selected_ids;
        if selected_ids.is_empty() {
            return Vec::new();
        }

        self.state
            .domain
            .document
            .elements
            .iter()
            .filter(|element| selected_ids.contains(&element.id))
            .cloned()
            .collect()
    }

    fn build_highlight_mask_scene(&self) -> HighlightMaskSceneSnapshot {
        let document = &self.state.domain.document;
        let creating_highlight = self.resolve_creating_highlight_element();
        if creating_highlight.is_none() && self.preview_elements_by_id.is_empty() {
            return Self::snapshot_for_highlights(document.highlight_elements());
        }

        let mut highlights = Vec::<ElementState>::new();
        let mut included_ids = HashSet::<String>::new();
        let creating_highlight_id = creating_highlight.as_ref().map(|value| value.id.as_str());

        for highlight in document.highlight_elements() {
            let effective = if creating_highlight_id.is_some_and(|id| highlight.id == id) {
                creating_highlight.clone()
            } else {
                self.preview_elements_by_id
                    .get(&highlight.id)
                    .cloned()
                    .or(Some(highlight))
            };
            Self::append_if_highlight(&mut highlights, &mut included_ids, effective);
        }

        for preview in self.preview_elements_by_id.values() {
            if self.is_preview_covered_by_document_highlight(
                preview,
                creating_highlight_id,
                &included_ids,
                document,
            ) {
                continue;
            }
            Self::append_if_highlight(&mut highlights, &mut included_ids, Some(preview.clone()));
        }

        Self::append_if_highlight(&mut highlights, &mut included_ids, creating_highlight);
        Self::snapshot_for_highlights(highlights)
    }

    fn resolve_creating_highlight_element(&self) -> Option<ElementState> {
        let InteractionState::Creating(interaction) = &self.state.application.interaction else {
            return None;
        };

        if interaction.element.data.type_id().as_str() != HighlightData::TYPE_ID_TOKEN {
            return None;
        }

        Some(interaction.element.copy_with(
            None,
            Some(interaction.current_rect),
            None,
            None,
            None,
            None,
        ))
    }

    fn is_preview_covered_by_document_highlight(
        &self,
        preview: &ElementState,
        creating_highlight_id: Option<&str>,
        included_ids: &HashSet<String>,
        document: &DomainDocumentState,
    ) -> bool {
        if creating_highlight_id.is_some_and(|id| preview.id == id) {
            return true;
        }
        if included_ids.contains(&preview.id) {
            return true;
        }
        document
            .get_element_by_id(&preview.id)
            .is_some_and(|element| element.data.type_id().as_str() == HighlightData::TYPE_ID_TOKEN)
    }

    fn append_if_highlight(
        target: &mut Vec<ElementState>,
        included_ids: &mut HashSet<String>,
        element: Option<ElementState>,
    ) {
        let Some(element) = element else {
            return;
        };

        if element.data.type_id().as_str() != HighlightData::TYPE_ID_TOKEN
            || !included_ids.insert(element.id.clone())
        {
            return;
        }

        target.push(element);
    }

    fn snapshot_for_highlights(values: Vec<ElementState>) -> HighlightMaskSceneSnapshot {
        if values.is_empty() {
            HighlightMaskSceneSnapshot::empty()
        } else {
            HighlightMaskSceneSnapshot::new(values)
        }
    }
}

impl PartialEq for DrawStateView {
    fn eq(&self, other: &Self) -> bool {
        self.state == other.state
            && self.preview_elements_by_id == other.preview_elements_by_id
            && self.effective_selection == other.effective_selection
            && snap_guide_list_equals(&self.snap_guides, &other.snap_guides)
    }
}

pub type CreatingInteractionState = CreatingState;
