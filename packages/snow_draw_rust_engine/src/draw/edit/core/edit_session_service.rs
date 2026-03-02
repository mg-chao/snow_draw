#![allow(dead_code)]

use std::any::Any;
use std::backtrace::Backtrace;
use std::collections::BTreeMap;
use std::error::Error;
use std::fmt;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Arc;

use crate::draw::config::draw_config::DrawConfig;
use crate::draw::edit::edit_operations::DefaultEditOperationRegistry;
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::edit_session_id::EditSessionId;
use crate::draw::models::interaction_state::{EditingState, InteractionState};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::edit_context::{
    default_text_metrics_service, EditContext, TextMetricsService,
};
use crate::draw::types::edit_operation_id::EditOperationId;
use crate::draw::types::edit_transform::EditTransform;
use crate::draw::types::snap_guides::{snap_guide_list_equals, SnapGuide};

use super::edit_error_handler::{EditErrorHandler, EditFailureReason, EditOutcome, ModuleLogger};
use super::edit_modifiers::EditModifiers;
use super::edit_operation::{EditOperation, EditOperationParams};

#[derive(Clone)]
struct RestoredSession {
    operation: Arc<dyn EditOperation>,
    editing_state: EditingState,
}

#[derive(Default)]
struct SessionRestoreResult {
    session: Option<RestoredSession>,
    failure_reason: Option<EditFailureReason>,
    fallback_operation_id: Option<EditOperationId>,
}

impl SessionRestoreResult {
    fn success(session: RestoredSession) -> Self {
        Self {
            session: Some(session),
            failure_reason: None,
            fallback_operation_id: None,
        }
    }

    fn failure(reason: EditFailureReason, fallback_operation_id: Option<EditOperationId>) -> Self {
        Self {
            session: None,
            failure_reason: Some(reason),
            fallback_operation_id,
        }
    }
}

#[derive(Debug)]
struct EditSessionPanicError {
    message: String,
}

impl EditSessionPanicError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl fmt::Display for EditSessionPanicError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl Error for EditSessionPanicError {}

/// Edit action pipeline.
pub struct EditSessionService {
    pub edit_operations: DefaultEditOperationRegistry,
    config_provider: Arc<dyn Fn() -> DrawConfig + Send + Sync>,
    text_metrics_service: Arc<dyn TextMetricsService>,
    log: Option<ModuleLogger>,
}

impl EditSessionService {
    pub fn new(
        edit_operations: DefaultEditOperationRegistry,
        config_provider: impl Fn() -> DrawConfig + Send + Sync + 'static,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
        log: Option<ModuleLogger>,
    ) -> Self {
        Self {
            edit_operations,
            config_provider: Arc::new(config_provider),
            text_metrics_service: text_metrics_service.unwrap_or_else(default_text_metrics_service),
            log,
        }
    }

    pub fn from_registry(
        registry: DefaultEditOperationRegistry,
        config_provider: impl Fn() -> DrawConfig + Send + Sync + 'static,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
        log: Option<ModuleLogger>,
    ) -> Self {
        Self::new(registry, config_provider, text_metrics_service, log)
    }

    pub fn start(
        &self,
        state: &DrawState,
        operation_id: EditOperationId,
        position: DrawPoint,
        params: &EditOperationParams,
        session_id: EditSessionId,
    ) -> EditOutcome {
        if !state.domain.selection.has_selection() {
            return EditErrorHandler::create_failure(
                state,
                EditFailureReason::NoSelection,
                Some(operation_id),
                true,
            );
        }

        let Some(operation) = self.edit_operations.get_operation(operation_id).cloned() else {
            return EditErrorHandler::create_failure(
                state,
                EditFailureReason::UnknownOperationId,
                Some(operation_id),
                true,
            );
        };

        self.run_guarded(state, Some(operation_id), true, || {
            self.perform_start(state, operation, operation_id, position, params, session_id)
        })
    }

    pub fn update(
        &self,
        state: &DrawState,
        current_position: DrawPoint,
        modifiers: EditModifiers,
    ) -> EditOutcome {
        self.with_restored_session(state, true, |restored| {
            self.perform_update(state, restored, current_position, modifiers)
        })
    }

    pub fn finish(&self, state: &DrawState) -> EditOutcome {
        self.with_restored_session(state, true, |restored| self.perform_finish(state, restored))
    }

    pub fn cancel(&self, state: &DrawState) -> EditOutcome {
        self.with_restored_session(state, false, |restored| {
            self.perform_cancel(state, restored)
        })
    }

    fn with_restored_session<F>(
        &self,
        state: &DrawState,
        validate_versions: bool,
        action: F,
    ) -> EditOutcome
    where
        F: FnOnce(RestoredSession) -> EditOutcome,
    {
        let restoration = self.restore_session(state, validate_versions);
        if let Some(reason) = restoration.failure_reason {
            return EditErrorHandler::create_failure(
                state,
                reason,
                restoration.fallback_operation_id,
                false,
            );
        }

        let Some(restored) = restoration.session else {
            return EditErrorHandler::create_failure(
                state,
                EditFailureReason::NotEditing,
                None,
                false,
            );
        };

        let fallback_operation_id = Some(restored.editing_state.operation_id);
        self.run_guarded(state, fallback_operation_id, false, || action(restored))
    }

    fn perform_start(
        &self,
        state: &DrawState,
        operation: Arc<dyn EditOperation>,
        operation_id: EditOperationId,
        position: DrawPoint,
        params: &EditOperationParams,
        session_id: EditSessionId,
    ) -> EditOutcome {
        let session = self.create_session(
            operation.as_ref(),
            operation_id,
            state,
            position,
            params,
            session_id,
        );

        let next_application =
            state
                .application
                .copy_with(None, Some(InteractionState::Editing(session)), None);
        let next_state = state.copy_with(None, Some(next_application));
        self.success_outcome(next_state, operation_id)
    }

    fn perform_update(
        &self,
        state: &DrawState,
        restored: RestoredSession,
        current_position: DrawPoint,
        modifiers: EditModifiers,
    ) -> EditOutcome {
        let editing_state = restored.editing_state;
        let config = (self.config_provider)();
        let updated = restored.operation.update(
            state,
            &editing_state.context,
            &editing_state.current_transform,
            current_position,
            modifiers,
            &config,
        );

        let transform_unchanged = updated.transform == editing_state.current_transform;
        let guides_unchanged = snap_guide_list_equals(
            updated.snap_guides.as_slice(),
            editing_state.snap_guides.as_slice(),
        );

        if transform_unchanged && guides_unchanged {
            return self.success_outcome(state.clone(), editing_state.operation_id);
        }

        let next_editing =
            editing_state.with_transform(updated.transform, Some(updated.snap_guides));
        let next_application =
            state
                .application
                .copy_with(None, Some(InteractionState::Editing(next_editing)), None);
        let next_state = state.copy_with(None, Some(next_application));
        self.success_outcome(next_state, editing_state.operation_id)
    }

    fn perform_finish(&self, state: &DrawState, restored: RestoredSession) -> EditOutcome {
        let operation_id = restored.editing_state.operation_id;
        let finished_state = restored.operation.finish(
            state,
            &restored.editing_state.context,
            &restored.editing_state.current_transform,
        );
        let next_state = self.to_idle_state(&finished_state);
        self.success_outcome(next_state, operation_id)
    }

    fn perform_cancel(&self, state: &DrawState, restored: RestoredSession) -> EditOutcome {
        let operation_id = restored.editing_state.operation_id;
        let cancelled_state = restored.operation.cancel(state);
        let next_state = self.to_idle_state(&cancelled_state);
        self.success_outcome(next_state, operation_id)
    }

    fn create_session(
        &self,
        operation: &dyn EditOperation,
        operation_id: EditOperationId,
        state: &DrawState,
        position: DrawPoint,
        params: &EditOperationParams,
        session_id: EditSessionId,
    ) -> EditingState {
        let created_context = operation.create_context(state, position, params);
        let context = self.attach_text_metrics_service(created_context);
        let transform = operation.initial_transform(state, &context, position);

        EditingState::new(
            operation_id,
            session_id,
            context,
            transform,
            Vec::<SnapGuide>::new(),
        )
    }

    fn attach_text_metrics_service(&self, context: EditContext) -> EditContext {
        let _ = &self.text_metrics_service;
        context
    }

    fn restore_session(&self, state: &DrawState, validate_versions: bool) -> SessionRestoreResult {
        let InteractionState::Editing(editing_state) = &state.application.interaction else {
            return SessionRestoreResult::failure(EditFailureReason::NotEditing, None);
        };

        let Some(operation) = self
            .edit_operations
            .get_operation(editing_state.operation_id)
            .cloned()
        else {
            return SessionRestoreResult::failure(
                EditFailureReason::UnknownOperationId,
                Some(editing_state.operation_id),
            );
        };

        if validate_versions {
            if let Some(reason) = self.resolve_version_conflict(editing_state, state) {
                return SessionRestoreResult::failure(reason, Some(editing_state.operation_id));
            }
        }

        SessionRestoreResult::success(RestoredSession {
            operation,
            editing_state: editing_state.clone(),
        })
    }

    fn resolve_version_conflict(
        &self,
        editing_state: &EditingState,
        current_state: &DrawState,
    ) -> Option<EditFailureReason> {
        let current_selection_version = current_state.domain.selection.selection_version as i64;
        if editing_state.context.selection_version != current_selection_version {
            return Some(EditFailureReason::SelectionChanged);
        }

        let current_elements_version = current_state.domain.document.elements_version;
        if editing_state.context.elements_version != current_elements_version {
            return Some(EditFailureReason::ElementsChanged);
        }

        None
    }

    fn success_outcome(&self, state: DrawState, operation_id: EditOperationId) -> EditOutcome {
        EditOutcome::new(state, None, Some(operation_id))
    }

    fn to_idle_state(&self, state: &DrawState) -> DrawState {
        let next_application = state.application.to_idle();
        if next_application == state.application {
            return state.clone();
        }
        state.copy_with(None, Some(next_application))
    }

    fn run_guarded<F>(
        &self,
        state: &DrawState,
        fallback_operation_id: Option<EditOperationId>,
        keep_state_on_failure: bool,
        operation: F,
    ) -> EditOutcome
    where
        F: FnOnce() -> EditOutcome,
    {
        match catch_unwind(AssertUnwindSafe(operation)) {
            Ok(outcome) => outcome,
            Err(payload) => {
                self.log_unexpected_panic(payload.as_ref(), fallback_operation_id);
                EditErrorHandler::create_failure(
                    state,
                    EditFailureReason::OperationFailed,
                    fallback_operation_id,
                    keep_state_on_failure,
                )
            }
        }
    }

    fn log_unexpected_panic(
        &self,
        payload: &(dyn Any + Send),
        operation_id: Option<EditOperationId>,
    ) {
        let Some(log) = self.log.as_ref() else {
            return;
        };

        let mut data = BTreeMap::new();
        data.insert("operation", "edit_session_service".to_owned());
        if let Some(id) = operation_id {
            data.insert("operationId", id.to_owned());
        }

        let message = panic_payload_message(payload);
        let error = EditSessionPanicError::new(message);
        log.error(
            "Unexpected edit panic",
            &error,
            &Backtrace::capture(),
            &data,
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

    "unknown panic payload".to_owned()
}
