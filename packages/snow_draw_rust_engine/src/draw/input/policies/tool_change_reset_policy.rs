#![allow(dead_code)]

use crate::draw::models::interaction_state::InteractionState;
use crate::draw::reducers::interaction::create::create_element_reducer::CancelCreateElement;
use crate::draw::reducers::interaction::edit::edit_state_reducer::CancelEdit;
use crate::draw::reducers::interaction::selection::box_select_reducer::CancelBoxSelect;
use crate::draw::reducers::interaction::selection::pending_state_reducer::ClearDragPending;
use crate::draw::reducers::interaction::text::text_edit_reducer::FinishTextEdit;
use crate::draw::reducers::selection::selection_reducer::ClearSelection;

/// Tool-change reset action set produced by [`resolve_tool_change_reset_actions`].
///
/// The variants mirror the Dart `DrawAction` payloads that can be emitted when
/// switching tools while an interaction is in progress.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ToolChangeResetAction {
    FinishTextEdit(FinishTextEditPayload),
    CancelCreateElement(CancelCreateElement),
    CancelEdit(CancelEdit),
    CancelBoxSelect(CancelBoxSelect),
    ClearDragPending(ClearDragPending),
    ClearSelection(ClearSelection),
}

/// Payload for text-edit completion caused by tool changes.
///
/// The current reducer action only stores text. This payload keeps the Dart
/// fields (`element_id`, `is_new`) available for callers that still need them.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FinishTextEditPayload {
    pub element_id: String,
    pub text: String,
    pub is_new: bool,
}

impl FinishTextEditPayload {
    pub fn new(element_id: impl Into<String>, text: impl Into<String>, is_new: bool) -> Self {
        Self {
            element_id: element_id.into(),
            text: text.into(),
            is_new,
        }
    }

    /// Converts this payload into the reducer action currently consumed by the
    /// Rust text-edit reducer.
    pub fn to_action(&self) -> FinishTextEdit {
        FinishTextEdit::new(self.text.clone())
    }
}

/// Resolves actions required to reset interaction state for tool changes.
///
/// Mirrors Dart `resolveToolChangeResetActions`.
pub fn resolve_tool_change_reset_actions(
    interaction: &InteractionState,
    include_clear_selection: bool,
    text_element_id: Option<&str>,
    text_draft_text: Option<&str>,
    text_is_new: Option<bool>,
) -> Vec<ToolChangeResetAction> {
    let mut actions = Vec::with_capacity(if include_clear_selection { 2 } else { 1 });

    if let Some(interaction_reset_action) =
        resolve_interaction_reset_action(interaction, text_element_id, text_draft_text, text_is_new)
    {
        actions.push(interaction_reset_action);
    }

    if include_clear_selection {
        actions.push(ToolChangeResetAction::ClearSelection(ClearSelection));
    }

    actions
}

fn resolve_interaction_reset_action(
    interaction: &InteractionState,
    text_element_id: Option<&str>,
    text_draft_text: Option<&str>,
    text_is_new: Option<bool>,
) -> Option<ToolChangeResetAction> {
    match interaction {
        InteractionState::TextEditing(text_editing) => {
            let payload = FinishTextEditPayload::new(
                text_element_id.unwrap_or(text_editing.element_id.as_str()),
                text_draft_text.unwrap_or(text_editing.draft_data.text.as_str()),
                text_is_new.unwrap_or(text_editing.is_new),
            );
            Some(ToolChangeResetAction::FinishTextEdit(payload))
        }
        InteractionState::Creating(_) => Some(ToolChangeResetAction::CancelCreateElement(
            CancelCreateElement,
        )),
        InteractionState::Editing(_) => Some(ToolChangeResetAction::CancelEdit(CancelEdit)),
        InteractionState::BoxSelecting(_) => {
            Some(ToolChangeResetAction::CancelBoxSelect(CancelBoxSelect))
        }
        InteractionState::DragPending(_) => {
            Some(ToolChangeResetAction::ClearDragPending(ClearDragPending))
        }
        InteractionState::Idle(_) => None,
    }
}
