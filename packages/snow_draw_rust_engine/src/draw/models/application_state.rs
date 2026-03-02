#![allow(dead_code)]

use std::fmt;

pub use crate::draw::models::interaction_state::{
    BoxSelectingState, CreatingState, DragPendingState, EditingState, IdleState, InteractionState,
    PendingIntent, PendingMoveIntent, PendingSelectIntent, TextEditingState,
};
pub use crate::draw::models::selection_overlay_state::SelectionOverlayState;
pub use crate::draw::models::view_state::ViewState;

/// Application-layer state.
///
/// Contains all temporary UI and interaction state. These states do not
/// participate in undo/redo and are not persisted.
#[derive(Clone, Debug, PartialEq)]
pub struct ApplicationState {
    /// View state (camera position, zoom, and so on).
    pub view: ViewState,
    /// Interaction state (editing, creating, box selection, and so on).
    pub interaction: InteractionState,
    /// Selection overlay state (multi-select bounds/rotation).
    pub selection_overlay: SelectionOverlayState,
}

impl ApplicationState {
    /// Creates an application state with default interaction and selection
    /// overlay values.
    pub fn new(view: ViewState) -> Self {
        Self {
            view,
            interaction: InteractionState::default(),
            selection_overlay: SelectionOverlayState::EMPTY,
        }
    }

    /// Creates an application state with explicit field values.
    pub fn with_parts(
        view: ViewState,
        interaction: InteractionState,
        selection_overlay: SelectionOverlayState,
    ) -> Self {
        Self {
            view,
            interaction,
            selection_overlay,
        }
    }

    /// Factory method: create the initial application state.
    pub fn initial(view: Option<ViewState>) -> Self {
        Self::new(view.unwrap_or(ViewState::INITIAL))
    }

    /// Whether editing is in progress.
    pub fn is_editing(&self) -> bool {
        matches!(self.interaction, InteractionState::Editing(_))
    }

    /// Whether creation is in progress.
    pub fn is_creating(&self) -> bool {
        matches!(self.interaction, InteractionState::Creating(_))
    }

    /// Whether box selection is in progress.
    pub fn is_box_selecting(&self) -> bool {
        matches!(self.interaction, InteractionState::BoxSelecting(_))
    }

    /// Whether text editing is in progress.
    pub fn is_text_editing(&self) -> bool {
        matches!(self.interaction, InteractionState::TextEditing(_))
    }

    /// Whether the state is idle.
    pub fn is_idle(&self) -> bool {
        matches!(self.interaction, InteractionState::Idle(_))
    }

    /// Returns a copy with selectively replaced fields.
    pub fn copy_with(
        &self,
        view: Option<ViewState>,
        interaction: Option<InteractionState>,
        selection_overlay: Option<SelectionOverlayState>,
    ) -> Self {
        Self {
            view: view.unwrap_or_else(|| self.view.clone()),
            interaction: interaction.unwrap_or_else(|| self.interaction.clone()),
            selection_overlay: selection_overlay.unwrap_or_else(|| self.selection_overlay.clone()),
        }
    }

    /// Resets to the idle interaction state.
    pub fn to_idle(&self) -> Self {
        if self.is_idle() {
            return self.clone();
        }

        self.copy_with(None, Some(InteractionState::Idle(IdleState)), None)
    }
}

impl fmt::Display for ApplicationState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "ApplicationState(view: {:?}, interaction: {:?}, selectionOverlay: {:?})",
            self.view, self.interaction, self.selection_overlay
        )
    }
}
