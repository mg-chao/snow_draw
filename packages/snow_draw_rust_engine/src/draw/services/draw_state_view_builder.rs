#![allow(dead_code)]

use std::collections::HashMap;
use std::sync::Arc;

use crate::draw::edit::edit_operations::DefaultEditOperationRegistry;
use crate::draw::edit::preview::edit_preview_engine::EditPreviewEngine;
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::draw_state_view::{DrawStateView, EffectiveSelection};
use crate::draw::models::element_state::ElementState;
use crate::draw::models::interaction_state::{EditingState, InteractionState, TextEditingState};
use crate::draw::services::selection_data_computer::SelectionDataComputer;

const SHARED_PREVIEW_ENGINE: EditPreviewEngine = EditPreviewEngine::new();

/// Builds [`DrawStateView`] instances.
#[derive(Clone)]
pub struct DrawStateViewBuilder {
    pub edit_operations: DefaultEditOperationRegistry,
    preview_engine: EditPreviewEngine,
}

impl DrawStateViewBuilder {
    pub fn new(
        edit_operations: DefaultEditOperationRegistry,
        preview_engine: Option<EditPreviewEngine>,
    ) -> Self {
        Self {
            edit_operations,
            preview_engine: preview_engine.unwrap_or(SHARED_PREVIEW_ENGINE),
        }
    }

    /// Builds a [`DrawStateView`] for the provided state.
    pub fn build(&self, state: &DrawState) -> DrawStateView {
        self.build_uncached(state)
    }

    fn build_uncached(&self, state: &DrawState) -> DrawStateView {
        match &state.application.interaction {
            InteractionState::Creating(creating) => DrawStateView::from_state_with_snap_guides(
                state.clone(),
                creating.snap_guides.clone(),
            ),
            InteractionState::TextEditing(text_editing) => {
                self.build_text_editing_preview(state, text_editing)
            }
            InteractionState::Editing(editing) => self.build_editing_preview(state, editing),
            _ => DrawStateView::from_state(state.clone()),
        }
    }

    fn build_editing_preview(
        &self,
        state: &DrawState,
        interaction: &EditingState,
    ) -> DrawStateView {
        let preview = self.preview_engine.build(state, &self.edit_operations);
        let has_preview =
            preview.selection_preview.is_some() || !preview.preview_elements_by_id.is_empty();
        if !has_preview {
            return DrawStateView::from_state_with_snap_guides(
                state.clone(),
                interaction.snap_guides.clone(),
            );
        }

        let effective_selection = if let Some(selection_preview) = preview.selection_preview {
            EffectiveSelection::new(
                Some(selection_preview.bounds),
                Some(selection_preview.center),
                selection_preview.rotation,
                true,
            )
        } else {
            Self::build_selection_from_state(state)
        };

        DrawStateView::with_preview(
            state.clone(),
            preview.preview_elements_by_id,
            effective_selection,
            interaction.snap_guides.clone(),
        )
    }

    fn build_text_editing_preview(
        &self,
        state: &DrawState,
        interaction: &TextEditingState,
    ) -> DrawStateView {
        let existing_element = state
            .domain
            .document
            .get_element_by_id(&interaction.element_id)
            .cloned();
        let preview_element = self.build_text_editing_element(state, interaction, existing_element);

        DrawStateView::with_preview(
            state.clone(),
            HashMap::from([(preview_element.id.clone(), preview_element.clone())]),
            self.build_selection_with_preview(state, &preview_element),
            Vec::new(),
        )
    }

    fn build_text_editing_element(
        &self,
        state: &DrawState,
        interaction: &TextEditingState,
        element: Option<ElementState>,
    ) -> ElementState {
        if let Some(element) = element {
            return element.copy_with(
                None,
                Some(interaction.rect),
                Some(interaction.rotation),
                Some(interaction.opacity),
                None,
                Some(Arc::new(interaction.draft_data.clone())),
            );
        }

        ElementState::new(
            interaction.element_id.clone(),
            interaction.rect,
            interaction.rotation,
            interaction.opacity,
            state.domain.document.elements.len() as i64,
            Arc::new(interaction.draft_data.clone()),
        )
    }

    fn build_selection_with_preview(
        &self,
        state: &DrawState,
        preview_element: &ElementState,
    ) -> EffectiveSelection {
        let selection = &state.domain.selection;
        if selection.selected_ids.is_empty() {
            return EffectiveSelection::NONE;
        }

        let mut selected_elements = Vec::<ElementState>::new();
        for id in &selection.selected_ids {
            if id == &preview_element.id {
                selected_elements.push(preview_element.clone());
                continue;
            }

            if let Some(selected_element) = state.domain.document.get_element_by_id(id) {
                selected_elements.push(selected_element.clone());
            }
        }

        if selected_elements.is_empty() {
            return EffectiveSelection::NONE;
        }

        let selection = SelectionDataComputer::compute_from_selected_elements(
            selected_elements,
            state.application.selection_overlay,
        );
        if !selection.has_selection() {
            return EffectiveSelection::NONE;
        }

        EffectiveSelection::new(
            selection.overlay_bounds,
            selection.overlay_center,
            selection.overlay_rotation,
            true,
        )
    }

    fn build_selection_from_state(state: &DrawState) -> EffectiveSelection {
        let selection = SelectionDataComputer::compute(state);
        if !selection.has_selection() {
            return EffectiveSelection::NONE;
        }

        EffectiveSelection::new(
            selection.overlay_bounds,
            selection.overlay_center,
            selection.overlay_rotation,
            true,
        )
    }
}

impl Default for DrawStateViewBuilder {
    fn default() -> Self {
        Self::new(DefaultEditOperationRegistry::default(), None)
    }
}
