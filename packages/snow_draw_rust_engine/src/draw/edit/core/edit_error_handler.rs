#![allow(dead_code)]

use std::backtrace::Backtrace;
use std::collections::BTreeMap;
use std::error::Error;
use std::fmt;
use std::sync::OnceLock;

use crate::draw::models::application_state::{EditingState, InteractionState};
use crate::draw::models::draw_state::DrawState;
use crate::draw::types::edit_operation_id::EditOperationId;

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

/// Base marker for edit-domain errors.
pub trait EditError: Error {}

/// Thrown when an `EditContext` of an unexpected type is provided to an operation.
#[derive(Debug, Default)]
pub struct EditContextTypeMismatchError;

impl fmt::Display for EditContextTypeMismatchError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "EditContextTypeMismatchError")
    }
}

impl Error for EditContextTypeMismatchError {}
impl EditError for EditContextTypeMismatchError {}

/// Thrown when an `EditTransform` of an unexpected type is provided to an operation.
#[derive(Debug, Default)]
pub struct EditTransformTypeMismatchError;

impl fmt::Display for EditTransformTypeMismatchError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "EditTransformTypeMismatchError")
    }
}

impl Error for EditTransformTypeMismatchError {}
impl EditError for EditTransformTypeMismatchError {}

/// Thrown when `EditOperationParams` of an unexpected type is provided.
#[derive(Debug, Default)]
pub struct EditParamsTypeMismatchError;

impl fmt::Display for EditParamsTypeMismatchError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "EditParamsTypeMismatchError")
    }
}

impl Error for EditParamsTypeMismatchError {}
impl EditError for EditParamsTypeMismatchError {}

/// Thrown when required edit-session data is missing.
#[derive(Debug, Default)]
pub struct EditMissingDataError;

impl fmt::Display for EditMissingDataError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "EditMissingDataError")
    }
}

impl Error for EditMissingDataError {}
impl EditError for EditMissingDataError {}

/// Wrapper for errors with additional context information.
#[derive(Debug)]
pub struct EditErrorWithContext {
    pub inner_error: Box<dyn Error + Send + Sync + 'static>,
    pub context: String,
}

impl fmt::Display for EditErrorWithContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}\n{}", self.inner_error, self.context)
    }
}

impl Error for EditErrorWithContext {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        Some(self.inner_error.as_ref())
    }
}

impl EditError for EditErrorWithContext {}

/// Assertion-style error used by callers that want Dart parity.
#[derive(Debug, Default)]
pub struct AssertionError;

impl fmt::Display for AssertionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "AssertionError")
    }
}

impl Error for AssertionError {}

/// Minimal logger interface used by edit error handling.
///
/// This is intentionally local to keep this module buildable while the
/// dedicated logging module is translated.
#[derive(Clone, Debug, Default)]
pub struct ModuleLogger;

impl ModuleLogger {
    /// Logs an unexpected error.
    pub fn error(
        &self,
        _message: &str,
        _error: &(dyn Error + 'static),
        _backtrace: &Backtrace,
        _data: &BTreeMap<&'static str, String>,
    ) {
        // No-op fallback logger.
    }
}

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
    fn fallback_log() -> &'static ModuleLogger {
        static FALLBACK_LOG: OnceLock<ModuleLogger> = OnceLock::new();
        FALLBACK_LOG.get_or_init(ModuleLogger::default)
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

    /// Executes an operation and converts errors to an `EditOutcome`.
    pub fn run_with_error_handling<F, E>(
        state: &DrawState,
        operation: F,
        keep_state_on_failure: bool,
        fallback_operation_id: Option<EditOperationId>,
        operation_name: Option<&str>,
        log: Option<&ModuleLogger>,
    ) -> EditOutcome
    where
        F: FnOnce() -> Result<EditOutcome, E>,
        E: Error + Send + Sync + 'static,
    {
        match operation() {
            Ok(outcome) => outcome,
            Err(error) => {
                let error_ref: &(dyn Error + 'static) = &error;
                if !Self::is_edit_error(error_ref) {
                    Self::log_unexpected_error(
                        error_ref,
                        operation_name,
                        log,
                        fallback_operation_id,
                    );
                }

                Self::create_failure(
                    state,
                    Self::map_exception_to_reason(error_ref),
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

    fn log_unexpected_error(
        error: &(dyn Error + 'static),
        operation_name: Option<&str>,
        log: Option<&ModuleLogger>,
        operation_id: Option<EditOperationId>,
    ) {
        let effective_log: &ModuleLogger = match log {
            Some(logger) => logger,
            None => Self::fallback_log(),
        };
        let mut data = BTreeMap::new();
        data.insert("operation", operation_name.unwrap_or("unknown").to_owned());
        if let Some(id) = operation_id {
            data.insert("operationId", id.to_owned());
        }
        let backtrace = Backtrace::capture();
        effective_log.error("Unexpected edit error", error, &backtrace, &data);
    }
}
