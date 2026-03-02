#![allow(dead_code)]

use crate::draw::models::draw_state::DrawState;
use crate::draw::types::edit_operation_id::EditOperationId;
use crate::draw::types::edit_transform::EditTransform;
use crate::draw::types::snap_guides::SnapGuide;

/// Result returned by an edit operation's update call.
#[derive(Clone, Debug, PartialEq)]
pub struct EditUpdateResult<T = EditTransform> {
    pub transform: T,
    pub snap_guides: Vec<SnapGuide>,
}

impl<T> EditUpdateResult<T> {
    /// Creates an update result with no snap guides.
    pub fn new(transform: T) -> Self {
        Self {
            transform,
            snap_guides: Vec::new(),
        }
    }

    /// Creates an update result with explicit snap guides.
    pub fn with_snap_guides(transform: T, snap_guides: Vec<SnapGuide>) -> Self {
        Self {
            transform,
            snap_guides,
        }
    }
}

/// Unified failure reasons for edit sessions.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum EditFailureReason {
    /// Session or dispatch failed because no edit is active.
    NotEditing,
    /// Session or dispatch failed because the operation id is unknown.
    UnknownOperationId,
    /// Selection changed while editing.
    SelectionChanged,
    /// Element data changed while editing.
    ElementsChanged,
    /// Start-edit validation failed because there is no selection.
    NoSelection,
    /// Start-edit validation failed because selection bounds are missing.
    MissingSelectionBounds,
    /// Start-edit validation failed because params are invalid.
    InvalidParams,
    /// Operation failed unexpectedly.
    OperationFailed,
}

impl EditFailureReason {
    /// Returns whether this failure is recoverable.
    pub fn is_recoverable(self) -> bool {
        matches!(
            self,
            Self::NotEditing
                | Self::SelectionChanged
                | Self::ElementsChanged
                | Self::NoSelection
                | Self::MissingSelectionBounds
        )
    }
}

/// Edit session outcome.
#[derive(Clone, Debug, PartialEq)]
pub struct EditOutcome {
    pub state: DrawState,
    pub failure_reason: Option<EditFailureReason>,
    pub operation_id: Option<EditOperationId>,
}

impl EditOutcome {
    /// Creates an edit session outcome.
    pub fn new(
        state: DrawState,
        failure_reason: Option<EditFailureReason>,
        operation_id: Option<EditOperationId>,
    ) -> Self {
        Self {
            state,
            failure_reason,
            operation_id,
        }
    }

    /// Creates a success outcome.
    pub fn success(state: DrawState, operation_id: Option<EditOperationId>) -> Self {
        Self::new(state, None, operation_id)
    }

    /// Creates a failure outcome.
    pub fn failure(
        state: DrawState,
        failure_reason: EditFailureReason,
        operation_id: Option<EditOperationId>,
    ) -> Self {
        Self::new(state, Some(failure_reason), operation_id)
    }

    /// Returns whether the outcome succeeded.
    pub fn is_success(&self) -> bool {
        self.failure_reason.is_none()
    }
}
