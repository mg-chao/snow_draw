#![allow(dead_code)]

use crate::draw::models::draw_state::DrawState;

/// Interaction state transition result.
#[derive(Clone, Debug, PartialEq)]
pub struct InteractionTransition {
    /// The draw state after applying the interaction reducer step.
    pub next_state: DrawState,
}

impl InteractionTransition {
    /// Creates a transition with the provided next state.
    pub const fn new(next_state: DrawState) -> Self {
        Self { next_state }
    }

    /// Creates a transition that keeps the state unchanged.
    pub const fn unchanged(state: DrawState) -> Self {
        Self::new(state)
    }
}
