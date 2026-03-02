#![allow(dead_code)]

use crate::draw::models::draw_state::DrawState;
use crate::draw::store::history_manager::PersistentSnapshot;

/// Builds immutable snapshots used by undo/redo history.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct SnapshotBuilder;

impl SnapshotBuilder {
    /// Creates a snapshot builder.
    pub const fn new() -> Self {
        Self
    }

    /// Captures a persistent snapshot from draw state.
    pub fn build_snapshot_from_state(
        &self,
        state: &DrawState,
        include_selection: bool,
    ) -> PersistentSnapshot {
        PersistentSnapshot::from_state(state, include_selection)
    }
}
