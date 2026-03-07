#![allow(dead_code)]

use crate::draw::edit::edit_operations::DefaultEditOperationRegistry;
use crate::draw::edit::preview::edit_preview::EditPreview;
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::interaction_state::InteractionState;

/// Computes the effective edit preview for rendering and hit-testing.
#[derive(Clone, Copy, Debug, Default)]
pub struct EditPreviewEngine;

impl EditPreviewEngine {
    pub const fn new() -> Self {
        Self
    }

    pub fn build(
        &self,
        state: &DrawState,
        edit_operations: &DefaultEditOperationRegistry,
    ) -> EditPreview {
        let InteractionState::Editing(editing) = &state.application.interaction else {
            return EditPreview::none();
        };

        let Some(operation) = edit_operations.get_operation(editing.operation_id) else {
            return EditPreview::none();
        };

        operation.build_preview(state, &editing.context, &editing.current_transform)
    }
}
