#![allow(dead_code)]

use std::any::Any;
use std::collections::HashSet;
use std::error::Error;
use std::fmt;
use std::panic::{catch_unwind, AssertUnwindSafe};

use crate::draw::actions::draw_actions::{
    ClearHistory, CreateSerialNumberTextElements, DrawAction, FinishEdit, FinishTextEdit, Redo,
    Undo, UpdateGlobalElements,
};
use crate::draw::actions::history_policy::HistoryPolicy;
use crate::draw::history::history_metadata::{HistoryMetadata, HistoryRecordType};
use crate::draw::history::recordable::{HistoryRecordType as ActionHistoryRecordType, Recordable};
use crate::draw::models::interaction_state::InteractionState;
use crate::draw::store::history_manager::HistoryCoalescing as StoreHistoryCoalescing;
use crate::draw::store::middleware::history_recording_error::HistoryRecordingError;
use crate::draw::store::middleware::middleware_context::DispatchContext;
use crate::draw::store::middleware::middleware_pipeline::{
    DispatchFuture, Middleware, MiddlewareError, MiddlewareInvocationResult, NextFunction,
};

/// History middleware that manages undo/redo snapshots.
///
/// It handles:
/// - recording snapshots for recordable actions,
/// - undo/redo operations,
/// - history clearing,
/// - batch-mode awareness.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct HistoryMiddleware;

impl HistoryMiddleware {
    pub const PRIORITY: i32 = 400;
    pub const NAME: &'static str = "History";

    pub const fn new() -> Self {
        Self
    }

    fn invoke_runtime(
        &self,
        context: DispatchContext,
        next: NextFunction,
    ) -> DispatchFuture<MiddlewareInvocationResult> {
        if context.action.as_any().is::<Undo>() {
            return self.handle_undo(context, next);
        }
        if context.action.as_any().is::<Redo>() {
            return self.handle_redo(context, next);
        }
        if context.action.as_any().is::<ClearHistory>() {
            return self.handle_clear_history(context, next);
        }

        self.handle_recordable_action(context, next)
    }

    fn handle_clear_history(
        &self,
        context: DispatchContext,
        next: NextFunction,
    ) -> DispatchFuture<MiddlewareInvocationResult> {
        {
            let mut manager = context
                .history_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            manager.clear();
        }

        Box::pin(async move { next(context).await })
    }

    fn handle_recordable_action(
        &self,
        context: DispatchContext,
        next: NextFunction,
    ) -> DispatchFuture<MiddlewareInvocationResult> {
        let policy = self.resolve_history_policy(&context, context.action.as_ref());
        if policy != HistoryPolicy::Record || context.is_batching {
            return Box::pin(async move { next(context).await });
        }

        let middleware = *self;
        Box::pin(async move {
            let updated_context = next(context).await?;
            if updated_context.has_error() {
                return Ok(updated_context);
            }

            middleware.record_history(&updated_context)?;
            Ok(updated_context)
        })
    }

    fn handle_undo(
        &self,
        context: DispatchContext,
        next: NextFunction,
    ) -> DispatchFuture<MiddlewareInvocationResult> {
        Box::pin(async move {
            let restored_state = {
                let mut manager = context
                    .history_manager
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner());
                if !manager.can_undo() {
                    None
                } else {
                    manager.undo(&context.current_state)
                }
            };

            match restored_state {
                Some(state) => next(context.with_current_state(state)).await,
                None => next(context).await,
            }
        })
    }

    fn handle_redo(
        &self,
        context: DispatchContext,
        next: NextFunction,
    ) -> DispatchFuture<MiddlewareInvocationResult> {
        Box::pin(async move {
            let restored_state = {
                let mut manager = context
                    .history_manager
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner());
                if !manager.can_redo() {
                    None
                } else {
                    manager.redo(&context.current_state)
                }
            };

            match restored_state {
                Some(state) => next(context.with_current_state(state)).await,
                None => next(context).await,
            }
        })
    }

    fn resolve_history_policy(
        &self,
        context: &DispatchContext,
        action: &dyn DrawAction,
    ) -> HistoryPolicy {
        if let Some(action) = action.as_any().downcast_ref::<FinishEdit>() {
            if self.metadata_from_finish_edit(context, action).is_none() {
                return HistoryPolicy::None;
            }
        }

        action.history_policy()
    }

    fn build_metadata(
        &self,
        context: &DispatchContext,
        action: &dyn DrawAction,
    ) -> Option<HistoryMetadata> {
        if let Some(action) = action.as_any().downcast_ref::<FinishTextEdit>() {
            return self.metadata_from_finish_text_edit(action);
        }
        if let Some(action) = action.as_any().downcast_ref::<FinishEdit>() {
            return self.metadata_from_finish_edit(context, action);
        }
        if let Some(action) = action.as_any().downcast_ref::<UpdateGlobalElements>() {
            return Some(recordable_metadata(action));
        }
        if let Some(action) = action
            .as_any()
            .downcast_ref::<CreateSerialNumberTextElements>()
        {
            return Some(recordable_metadata(action));
        }

        None
    }

    fn metadata_from_finish_edit(
        &self,
        context: &DispatchContext,
        action: &FinishEdit,
    ) -> Option<HistoryMetadata> {
        action
            .metadata
            .clone()
            .or_else(|| self.metadata_from_edit(context))
    }

    fn metadata_from_finish_text_edit(&self, action: &FinishTextEdit) -> Option<HistoryMetadata> {
        let has_text = !action.text.trim().is_empty();
        if !has_text && action.is_new {
            return None;
        }

        let (description, record_type) = match (action.is_new, has_text) {
            (false, false) => ("Delete text", HistoryRecordType::Delete),
            (true, true) => ("Create text", HistoryRecordType::Create),
            (false, true) => ("Edit text", HistoryRecordType::Edit),
            _ => return None,
        };

        Some(HistoryMetadata::new(
            description.to_owned(),
            record_type,
            HashSet::new(),
            None,
            None,
        ))
    }

    fn metadata_from_edit(&self, context: &DispatchContext) -> Option<HistoryMetadata> {
        let InteractionState::Editing(interaction) = &context.initial_state.application.interaction
        else {
            return None;
        };

        let operation = context
            .draw_context
            .edit_operations
            .get_operation(interaction.operation_id)?;
        if !operation.records_history() {
            return None;
        }

        Some(
            operation.create_history_metadata(&interaction.context, &interaction.current_transform),
        )
    }

    fn record_history(&self, context: &DispatchContext) -> Result<(), MiddlewareError> {
        let metadata = self.build_metadata(context, context.action.as_ref());
        let include_selection = context.include_selection_in_history;
        let coalescing = context
            .action
            .history_coalescing()
            .map(|hint| StoreHistoryCoalescing::new(hint.key.clone(), Some(hint.window)));

        let snapshot_before = context
            .snapshot_builder
            .build_snapshot_from_state(&context.initial_state, include_selection);
        let snapshot_after = context
            .snapshot_builder
            .build_snapshot_from_state(&context.current_state, include_selection);

        let record_result = catch_unwind(AssertUnwindSafe(|| {
            let mut manager = context
                .history_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());

            manager.record(
                snapshot_before,
                snapshot_after,
                metadata.clone(),
                coalescing,
                Some(&context.initial_state),
                None,
            )
        }));

        match record_result {
            Ok(_recorded) => Ok(()),
            Err(payload) => {
                let panic_error =
                    PanicHistoryRecordingError::new(panic_payload_to_string(payload.as_ref()));
                let error =
                    HistoryRecordingError::with_cause(context.action.action_name(), panic_error);
                Err(MiddlewareError::message(error.to_string()))
            }
        }
    }
}

impl Middleware for HistoryMiddleware {
    fn invoke(
        &self,
        context: DispatchContext,
        next: NextFunction,
    ) -> DispatchFuture<MiddlewareInvocationResult> {
        self.invoke_runtime(context, next)
    }

    fn priority(&self) -> i32 {
        Self::PRIORITY
    }

    fn name(&self) -> &str {
        Self::NAME
    }
}

fn recordable_metadata<T>(recordable: &T) -> HistoryMetadata
where
    T: Recordable,
{
    HistoryMetadata::new(
        recordable.history_description(),
        map_record_type(recordable.record_type()),
        HashSet::new(),
        None,
        None,
    )
}

fn map_record_type(value: ActionHistoryRecordType) -> HistoryRecordType {
    match value {
        ActionHistoryRecordType::Edit => HistoryRecordType::Edit,
        ActionHistoryRecordType::Create => HistoryRecordType::Create,
        ActionHistoryRecordType::Delete => HistoryRecordType::Delete,
        ActionHistoryRecordType::Style => HistoryRecordType::Style,
        ActionHistoryRecordType::Selection => HistoryRecordType::Selection,
        ActionHistoryRecordType::Other => HistoryRecordType::Other,
    }
}

#[derive(Debug)]
struct PanicHistoryRecordingError {
    message: String,
}

impl PanicHistoryRecordingError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl fmt::Display for PanicHistoryRecordingError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "history recording panicked: {}", self.message)
    }
}

impl Error for PanicHistoryRecordingError {}

fn panic_payload_to_string(payload: &(dyn Any + Send)) -> String {
    if let Some(value) = payload.downcast_ref::<String>() {
        return value.clone();
    }
    if let Some(value) = payload.downcast_ref::<&str>() {
        return (*value).to_owned();
    }
    "panic without message".to_owned()
}
