#![allow(dead_code)]

use std::collections::HashSet;
use std::sync::Arc;

use crate::draw::config::draw_config::DrawConfig;
use crate::draw::history::history_metadata::{HistoryMetadata, HistoryRecordType};
use crate::draw::models::draw_state::DrawState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::edit_context::{EditContext, TextMetricsService};
use crate::draw::types::edit_operation_id::EditOperationId;
use crate::draw::types::edit_transform::EditTransform;
use crate::draw::types::snap_guides::SnapGuide;

use super::edit_modifiers::EditModifiers;
pub use super::edit_operation_params::{
    ArrowPointOperationParams, ConnectorPointOperationParams, EditOperationParams,
    MoveOperationParams, ResizeOperationParams, RotateOperationParams,
};
pub use crate::draw::edit::preview::edit_preview::EditPreview;

/// Result of a single edit update tick.
#[derive(Clone, Debug, PartialEq)]
pub struct EditUpdateResult<T> {
    pub transform: T,
    pub snap_guides: Vec<SnapGuide>,
}

impl<T> EditUpdateResult<T> {
    pub fn new(transform: T) -> Self {
        Self {
            transform,
            snap_guides: Vec::new(),
        }
    }

    pub fn with_snap_guides(transform: T, snap_guides: Vec<SnapGuide>) -> Self {
        Self {
            transform,
            snap_guides,
        }
    }
}

/// Unified edit-domain operation interface (move/resize/rotate/...).
///
/// This is intentionally not the same concept as an input-layer intent.
pub trait EditOperation: Send + Sync {
    /// Stable id used by operation registry and edit session state.
    fn id(&self) -> EditOperationId;

    /// Whether this operation should record history on finish.
    fn records_history(&self) -> bool {
        true
    }

    /// Creates history metadata for the current context and transform.
    fn create_history_metadata(
        &self,
        context: &EditContext,
        _transform: &EditTransform,
    ) -> HistoryMetadata {
        HistoryMetadata::new(
            format!("{} operation", self.id()),
            HistoryRecordType::Edit,
            selected_ids(context),
            None,
            None,
        )
    }

    /// Creates an immutable edit context snapshot for a new edit session.
    fn create_context(
        &self,
        state: &DrawState,
        position: DrawPoint,
        params: &EditOperationParams,
    ) -> EditContext;

    /// Attaches the session text metrics service to any operation-local state.
    fn attach_text_metrics_service(
        &self,
        _context: &EditContext,
        _text_metrics_service: Arc<dyn TextMetricsService>,
    ) {
    }

    /// Returns the initial transform for a newly started edit session.
    fn initial_transform(
        &self,
        state: &DrawState,
        context: &EditContext,
        start_position: DrawPoint,
    ) -> EditTransform;

    /// Updates the edit session transform. Must not mutate elements.
    fn update(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
        current_position: DrawPoint,
        modifiers: EditModifiers,
        config: &DrawConfig,
    ) -> EditUpdateResult<EditTransform>;

    /// Commits the current transform into persistent state.
    fn finish(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> DrawState;

    /// Cancels the current edit session and returns to idle state.
    ///
    /// Default behavior only transitions application interaction to idle.
    fn cancel(&self, state: &DrawState) -> DrawState {
        state.copy_with(None, Some(state.application.to_idle()))
    }

    /// Builds the effective preview used by rendering and hit-testing.
    ///
    /// Implementations should keep this consistent with [`Self::finish`].
    fn build_preview(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> EditPreview;
}

fn selected_ids(context: &EditContext) -> HashSet<String> {
    context.selected_ids_at_start.clone()
}
