#![allow(dead_code)]

use std::any::Any;
use std::backtrace::Backtrace;
use std::error::Error;
use std::fmt;
use std::panic::{catch_unwind, AssertUnwindSafe};

use crate::draw::models::application_state::{EditingState, InteractionState};
use crate::draw::models::draw_state::DrawState;
use crate::draw::services::log::log_service::{LogData, LogService, ModuleLogger};
use crate::draw::types::edit_operation_id::EditOperationId;

use super::edit_errors::{
    EditContextTypeMismatchError, EditErrorWithContext, EditMissingDataError,
    EditParamsTypeMismatchError, EditTransformTypeMismatchError,
};

/// Unified failure reasons for edit sessions.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum EditFailureReason {
    // Session/dispatch failures.
    NotEditing,
    UnknownOperationId,
    // State conflicts.
    SelectionChanged,
    ElementsChanged,
    // Start-edit validation failures.
    NoSelection,
    MissingSelectionBounds,
    InvalidParams,
    // Unexpected operation failure.
    OperationFailed,
}

impl EditFailureReason {
    /// Returns whether this failure can be recovered without resetting the app.
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
    /// Creates an edit outcome.
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

    /// Returns true if the operation succeeded.
    pub fn is_success(&self) -> bool {
        self.failure_reason.is_none()
    }
}

/// Assertion-style error used by callers that want Dart parity.
#[derive(Debug, Default)]
pub struct AssertionError;

impl fmt::Display for AssertionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "AssertionError")
    }
}

impl Error for AssertionError {}

/// Extracts the operation id from `EditingState`.
pub trait EditingStateOperationIdExt {
    fn operation_id(&self) -> Option<EditOperationId>;
}

impl EditingStateOperationIdExt for EditingState {
    fn operation_id(&self) -> Option<EditOperationId> {
        Some(self.operation_id)
    }
}

/// Centralized edit error handling utilities.
pub struct EditErrorHandler;

impl EditErrorHandler {
    fn fallback_log() -> ModuleLogger {
        LogService::fallback().edit()
    }

    /// Returns the current operation id when the app is in editing mode.
    pub fn extract_operation_id(state: &DrawState) -> Option<EditOperationId> {
        match &state.application.interaction {
            InteractionState::Editing(editing) => editing.operation_id(),
            _ => None,
        }
    }

    /// Computes the next state after a failure.
    ///
    /// When `keep_state` is false, the interaction is reset to idle.
    pub fn compute_next_state(state: &DrawState, keep_state: bool) -> DrawState {
        if keep_state {
            return state.clone();
        }

        let next_application = state.application.to_idle();
        if next_application == state.application {
            return state.clone();
        }

        state.copy_with(None, Some(next_application))
    }

    /// Creates a standardized failure outcome.
    pub fn create_failure(
        state: &DrawState,
        reason: EditFailureReason,
        operation_id: Option<EditOperationId>,
        keep_state: bool,
    ) -> EditOutcome {
        EditOutcome::new(
            Self::compute_next_state(state, keep_state),
            Some(reason),
            operation_id.or_else(|| Self::extract_operation_id(state)),
        )
    }

    /// Maps a thrown error to the canonical edit failure reason.
    pub fn map_exception_to_reason(error: &(dyn Error + 'static)) -> EditFailureReason {
        let actual_error: &(dyn Error + 'static) =
            if let Some(with_context) = error.downcast_ref::<EditErrorWithContext>() {
                with_context.inner_error.as_ref()
            } else {
                error
            };

        if actual_error.is::<EditMissingDataError>() {
            EditFailureReason::MissingSelectionBounds
        } else if actual_error.is::<EditContextTypeMismatchError>()
            || actual_error.is::<EditTransformTypeMismatchError>()
            || actual_error.is::<EditParamsTypeMismatchError>()
            || actual_error.is::<AssertionError>()
        {
            EditFailureReason::InvalidParams
        } else {
            EditFailureReason::OperationFailed
        }
    }

    /// Executes an operation and converts thrown failures to an `EditOutcome`.
    pub fn run_with_error_handling<F>(
        state: &DrawState,
        operation: F,
        keep_state_on_failure: bool,
        fallback_operation_id: Option<EditOperationId>,
        operation_name: Option<&str>,
        log: Option<&ModuleLogger>,
    ) -> EditOutcome
    where
        F: FnOnce() -> EditOutcome,
    {
        match catch_unwind(AssertUnwindSafe(operation)) {
            Ok(outcome) => outcome,
            Err(payload) => {
                let payload_ref = payload.as_ref();
                if !Self::is_edit_panic(payload_ref) {
                    Self::log_unexpected_error_payload(
                        payload_ref,
                        operation_name,
                        log,
                        fallback_operation_id,
                    );
                }

                Self::create_failure(
                    state,
                    Self::map_panic_payload_to_reason(payload_ref),
                    fallback_operation_id,
                    keep_state_on_failure,
                )
            }
        }
    }

    fn is_edit_error(error: &(dyn Error + 'static)) -> bool {
        error.is::<EditErrorWithContext>()
            || error.is::<EditMissingDataError>()
            || error.is::<EditContextTypeMismatchError>()
            || error.is::<EditTransformTypeMismatchError>()
            || error.is::<EditParamsTypeMismatchError>()
    }

    fn is_edit_panic(payload: &(dyn Any + Send)) -> bool {
        payload.is::<EditErrorWithContext>()
            || payload.is::<EditMissingDataError>()
            || payload.is::<EditContextTypeMismatchError>()
            || payload.is::<EditTransformTypeMismatchError>()
            || payload.is::<EditParamsTypeMismatchError>()
            || payload.is::<AssertionError>()
    }

    fn map_panic_payload_to_reason(payload: &(dyn Any + Send)) -> EditFailureReason {
        if let Some(error) = payload.downcast_ref::<EditErrorWithContext>() {
            return Self::map_exception_to_reason(error);
        }
        if let Some(error) = payload.downcast_ref::<EditMissingDataError>() {
            return Self::map_exception_to_reason(error);
        }
        if let Some(error) = payload.downcast_ref::<EditContextTypeMismatchError>() {
            return Self::map_exception_to_reason(error);
        }
        if let Some(error) = payload.downcast_ref::<EditTransformTypeMismatchError>() {
            return Self::map_exception_to_reason(error);
        }
        if let Some(error) = payload.downcast_ref::<EditParamsTypeMismatchError>() {
            return Self::map_exception_to_reason(error);
        }
        if let Some(error) = payload.downcast_ref::<AssertionError>() {
            return Self::map_exception_to_reason(error);
        }
        EditFailureReason::OperationFailed
    }

    fn log_unexpected_error_payload(
        payload: &(dyn Any + Send),
        operation_name: Option<&str>,
        log: Option<&ModuleLogger>,
        operation_id: Option<EditOperationId>,
    ) {
        let effective_log = log.cloned().unwrap_or_else(Self::fallback_log);
        let mut data = LogData::new();
        data.insert(
            "operation".to_owned(),
            operation_name.unwrap_or("unknown").to_owned(),
        );
        if let Some(id) = operation_id {
            data.insert("operationId".to_owned(), id.to_owned());
        }
        let error = panic_payload_message(payload);
        let backtrace = format!("{:?}", Backtrace::capture());
        effective_log.error(
            "Unexpected edit error",
            Some(&error),
            Some(&backtrace),
            Some(&data),
        );
    }
}

fn panic_payload_message(payload: &(dyn Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&str>() {
        return (*message).to_owned();
    }

    if let Some(message) = payload.downcast_ref::<String>() {
        return message.clone();
    }

    if let Some(error) = payload.downcast_ref::<EditErrorWithContext>() {
        return error.to_string();
    }

    if let Some(error) = payload.downcast_ref::<EditMissingDataError>() {
        return error.to_string();
    }

    if let Some(error) = payload.downcast_ref::<EditContextTypeMismatchError>() {
        return error.to_string();
    }

    if let Some(error) = payload.downcast_ref::<EditTransformTypeMismatchError>() {
        return error.to_string();
    }

    if let Some(error) = payload.downcast_ref::<EditParamsTypeMismatchError>() {
        return error.to_string();
    }

    if let Some(error) = payload.downcast_ref::<AssertionError>() {
        return error.to_string();
    }

    "unknown panic payload".to_owned()
}
