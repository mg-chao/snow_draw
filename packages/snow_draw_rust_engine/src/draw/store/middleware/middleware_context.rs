#![allow(dead_code)]

use std::fmt;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::draw::actions::draw_actions::DrawAction;
use crate::draw::core::draw_context::DrawContext;
use crate::draw::edit::core::edit_session_id_generator::EditSessionIdGenerator;
use crate::draw::edit::core::edit_session_service::EditSessionService;
use crate::draw::models::draw_state::DrawState;
use crate::draw::store::history_manager::HistoryManager;
use crate::draw::store::snapshot_builder::SnapshotBuilder;

static TRACE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

fn generate_trace_id() -> String {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_micros();
    let sequence = TRACE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    format!("dispatch_{timestamp:x}_{sequence:x}")
}

/// Shared action payload used during middleware dispatch.
pub type DispatchAction = Arc<dyn DrawAction>;

/// Shared history manager handle used by dispatch middleware.
pub type SharedHistoryManager = Arc<Mutex<HistoryManager>>;

/// Flat dispatch context for middleware execution.
#[derive(Clone)]
pub struct DispatchContext {
    pub action: DispatchAction,
    pub draw_context: DrawContext,
    pub initial_state: DrawState,
    pub current_state: DrawState,
    pub history_manager: SharedHistoryManager,
    pub snapshot_builder: SnapshotBuilder,
    pub edit_session_service: Arc<EditSessionService>,
    pub session_id_generator: EditSessionIdGenerator,
    pub is_batching: bool,
    pub include_selection_in_history: bool,
    pub should_stop: bool,
    pub stop_reason: Option<String>,
    pub error: Option<String>,
    pub stack_trace: Option<String>,
    pub error_source: Option<String>,
    pub trace_id: String,
}

impl DispatchContext {
    /// Creates the initial dispatch context for one action dispatch cycle.
    #[allow(clippy::too_many_arguments)]
    pub fn initial(
        action: DispatchAction,
        state: DrawState,
        draw_context: DrawContext,
        history_manager: SharedHistoryManager,
        snapshot_builder: SnapshotBuilder,
        edit_session_service: Arc<EditSessionService>,
        session_id_generator: EditSessionIdGenerator,
        is_batching: bool,
        include_selection_in_history: bool,
        trace_id: Option<String>,
    ) -> Self {
        Self {
            action,
            draw_context,
            initial_state: state.clone(),
            current_state: state,
            history_manager,
            snapshot_builder,
            edit_session_service,
            session_id_generator,
            is_batching,
            include_selection_in_history,
            should_stop: false,
            stop_reason: None,
            error: None,
            stack_trace: None,
            error_source: None,
            trace_id: trace_id.unwrap_or_else(generate_trace_id),
        }
    }

    pub fn has_error(&self) -> bool {
        self.error.is_some()
    }

    pub fn is_terminal(&self) -> bool {
        self.should_stop || self.has_error()
    }

    pub fn has_state_changed(&self) -> bool {
        self.current_state != self.initial_state
    }

    pub fn with_current_state(&self, new_state: DrawState) -> Self {
        if new_state == self.current_state {
            return self.clone();
        }
        self.copy_with(Some(new_state), None, None, None, None, None)
    }

    pub fn with_stop(&self, reason: impl Into<String>) -> Self {
        self.copy_with(None, Some(true), Some(reason.into()), None, None, None)
    }

    pub fn with_error(
        &self,
        error: impl fmt::Display,
        stack_trace: impl Into<String>,
        source: Option<String>,
    ) -> Self {
        let error_text = error.to_string();
        self.copy_with(
            None,
            Some(true),
            Some(format!("Error: {error_text}")),
            Some(error_text),
            Some(stack_trace.into()),
            source,
        )
    }

    fn copy_with(
        &self,
        current_state: Option<DrawState>,
        should_stop: Option<bool>,
        stop_reason: Option<String>,
        error: Option<String>,
        stack_trace: Option<String>,
        error_source: Option<String>,
    ) -> Self {
        Self {
            action: self.action.clone(),
            draw_context: self.draw_context.clone(),
            initial_state: self.initial_state.clone(),
            current_state: current_state.unwrap_or_else(|| self.current_state.clone()),
            history_manager: self.history_manager.clone(),
            snapshot_builder: self.snapshot_builder.clone(),
            edit_session_service: self.edit_session_service.clone(),
            session_id_generator: self.session_id_generator.clone(),
            is_batching: self.is_batching,
            include_selection_in_history: self.include_selection_in_history,
            should_stop: should_stop.unwrap_or(self.should_stop),
            stop_reason: stop_reason.or_else(|| self.stop_reason.clone()),
            error: error.or_else(|| self.error.clone()),
            stack_trace: stack_trace.or_else(|| self.stack_trace.clone()),
            error_source: error_source.or_else(|| self.error_source.clone()),
            trace_id: self.trace_id.clone(),
        }
    }

    fn action_runtime_type(&self) -> &'static str {
        std::any::type_name_of_val(self.action.as_ref())
    }
}

impl fmt::Debug for DispatchContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("DispatchContext")
            .field("action", &self.action_runtime_type())
            .field("trace_id", &self.trace_id)
            .field("has_error", &self.has_error())
            .field("is_terminal", &self.is_terminal())
            .field("state_changed", &self.has_state_changed())
            .finish()
    }
}

impl fmt::Display for DispatchContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "DispatchContext(action: {}, traceId: {}, hasError: {}, isTerminal: {}, \
             stateChanged: {})",
            self.action_runtime_type(),
            self.trace_id,
            self.has_error(),
            self.is_terminal(),
            self.has_state_changed()
        )
    }
}
