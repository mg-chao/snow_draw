#![allow(dead_code)]

use std::any::Any;
use std::collections::BTreeMap;
use std::future::Future;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};

use thiserror::Error;

use crate::draw::actions::config_actions::{
    UpdateCanvasConfig, UpdateConfig, UpdateSelectionConfig,
};
use crate::draw::actions::draw_actions::{
    ActionCriticality, CancelEdit, DrawAction, FinishCreateElement, FinishEdit, Redo, StartEdit,
    Undo, UpdateEdit,
};
use crate::draw::config::config_manager::ConfigManager;
use crate::draw::config::draw_config::{DrawConfig, DrawConfigPatch, ElementStyleConfigPatch};
use crate::draw::core::draw_context::DrawContext;
use crate::draw::edit::core::edit_cancel_reason::EditCancelReason;
use crate::draw::edit::core::edit_session_id_generator::EditSessionIdGenerator;
use crate::draw::edit::core::edit_session_service::EditSessionService;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::events::edit_events::{
    EditCancelReason as EventEditCancelReason, EditSessionCancelledEvent, EditSessionFinishedEvent,
    EditSessionStartedEvent, EditSessionUpdatedEvent,
};
use crate::draw::events::error_events::ErrorEvent;
use crate::draw::events::event_bus::{DrawEvent as BusDrawEvent, EventBus};
use crate::draw::events::state_events::{
    DocumentChangedEvent, HistoryAvailabilityChangedEvent, InteractionChangedEvent,
    SelectionChangedEvent, ViewChangedEvent,
};
use crate::draw::models::draw_state::{DomainElementState, DrawState};
use crate::draw::models::interaction_state::{EditingState, InteractionState};
use crate::draw::store::listener_registry::ListenerRegistry;
use crate::draw::store::middleware::middleware_context::{
    DispatchAction, DispatchContext, SharedHistoryManager,
};
use crate::draw::store::middleware::middleware_pipeline::MiddlewarePipeline;
use crate::draw::store::snapshot_builder::SnapshotBuilder;
use crate::draw::store::state_change_detector::{
    has_document_state_changed, has_interaction_state_changed, has_selection_state_changed,
    has_view_state_changed,
};

/// Error type emitted by [`ActionProcessor`] when dispatch cannot continue.
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ActionProcessorError {
    #[error("dispatch queue has been disposed")]
    DispatchQueueDisposed,
    #[error("dispatch queue disposed while pending")]
    DispatchQueueDisposedWhilePending,
    #[error("critical dispatch failure for action {action} (source: {failure_source}): {message}")]
    CriticalDispatchFailure {
        action: String,
        failure_source: String,
        message: String,
    },
}

/// Dependency bundle for [`ActionProcessor`].
#[derive(Clone)]
pub struct ActionProcessorServices {
    pub draw_context: DrawContext,
    pub read_state: Arc<dyn Fn() -> DrawState + Send + Sync + 'static>,
    pub write_state: Arc<dyn Fn(DrawState) + Send + Sync + 'static>,
    pub history_manager: SharedHistoryManager,
    pub config_manager: Arc<Mutex<ConfigManager<DrawConfig>>>,
    pub listener_registry: ListenerRegistry,
    pub snapshot_builder: SnapshotBuilder,
    pub edit_session_service: Arc<EditSessionService>,
    pub session_id_generator: EditSessionIdGenerator,
    pub is_batching: Arc<dyn Fn() -> bool + Send + Sync + 'static>,
    pub include_selection_in_history: bool,
    pub event_bus: Arc<EventBus>,
}

impl ActionProcessorServices {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        draw_context: DrawContext,
        read_state: Arc<dyn Fn() -> DrawState + Send + Sync + 'static>,
        write_state: Arc<dyn Fn(DrawState) + Send + Sync + 'static>,
        history_manager: SharedHistoryManager,
        config_manager: Arc<Mutex<ConfigManager<DrawConfig>>>,
        listener_registry: ListenerRegistry,
        snapshot_builder: SnapshotBuilder,
        edit_session_service: Arc<EditSessionService>,
        session_id_generator: EditSessionIdGenerator,
        is_batching: Arc<dyn Fn() -> bool + Send + Sync + 'static>,
        include_selection_in_history: bool,
        event_bus: Arc<EventBus>,
    ) -> Self {
        Self {
            draw_context,
            read_state,
            write_state,
            history_manager,
            config_manager,
            listener_registry,
            snapshot_builder,
            edit_session_service,
            session_id_generator,
            is_batching,
            include_selection_in_history,
            event_bus,
        }
    }
}

/// Sequential action processor translated from Dart dispatch orchestration.
pub struct ActionProcessor {
    services: ActionProcessorServices,
    pipeline: MiddlewarePipeline,
    dispatch_lock: Mutex<()>,
    last_can_undo: Mutex<bool>,
    last_can_redo: Mutex<bool>,
    is_disposed: AtomicBool,
}

impl ActionProcessor {
    pub fn new(services: ActionProcessorServices, pipeline: MiddlewarePipeline) -> Self {
        let (can_undo, can_redo) = {
            let manager = services
                .history_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            (manager.can_undo(), manager.can_redo())
        };

        Self {
            services,
            pipeline,
            dispatch_lock: Mutex::new(()),
            last_can_undo: Mutex::new(can_undo),
            last_can_redo: Mutex::new(can_redo),
            is_disposed: AtomicBool::new(false),
        }
    }

    pub fn state(&self) -> DrawState {
        (self.services.read_state)()
    }

    pub fn is_disposed(&self) -> bool {
        self.is_disposed.load(Ordering::SeqCst)
    }

    pub fn dispose(&self) {
        self.is_disposed.store(true, Ordering::SeqCst);
    }

    pub fn dispatch(&self, action: DispatchAction) -> Result<(), ActionProcessorError> {
        if self.is_disposed() {
            return Err(ActionProcessorError::DispatchQueueDisposed);
        }

        let _guard = self
            .dispatch_lock
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if self.is_disposed() {
            return Err(ActionProcessorError::DispatchQueueDisposedWhilePending);
        }

        for next_action in self.expand_actions_for_dispatch(action) {
            self.process(next_action)?;
        }

        Ok(())
    }

    pub fn sync_history_availability(&self) {
        let (can_undo, can_redo) = {
            let manager = self
                .services
                .history_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            (manager.can_undo(), manager.can_redo())
        };

        let mut last_can_undo = self
            .last_can_undo
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let mut last_can_redo = self
            .last_can_redo
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());

        let changed = can_undo != *last_can_undo || can_redo != *last_can_redo;
        *last_can_undo = can_undo;
        *last_can_redo = can_redo;
        drop(last_can_undo);
        drop(last_can_redo);

        if changed {
            self.emit_event::<HistoryAvailabilityChangedEvent, _>(|| {
                HistoryAvailabilityChangedEvent::new(can_undo, can_redo)
            });
        }
    }

    fn expand_actions_for_dispatch(&self, action: DispatchAction) -> Vec<DispatchAction> {
        match self.resolve_edit_cancel_reason(action.as_ref()) {
            Some(reason) => vec![Arc::new(CancelEdit::new(reason)), action],
            None => vec![action],
        }
    }

    fn process(&self, action: DispatchAction) -> Result<(), ActionProcessorError> {
        if self.handle_config_action(action.as_ref()) {
            return Ok(());
        }

        self.run_with_frozen_config(|| self.process_through_pipeline(action))
    }

    fn run_with_frozen_config<F>(&self, action: F) -> Result<(), ActionProcessorError>
    where
        F: FnOnce() -> Result<(), ActionProcessorError>,
    {
        {
            let mut manager = self
                .services
                .config_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            manager.freeze();
        }

        let result = action();

        {
            let mut manager = self
                .services
                .config_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            manager.unfreeze();
        }

        result
    }

    fn process_through_pipeline(&self, action: DispatchAction) -> Result<(), ActionProcessorError> {
        let initial_context = DispatchContext::initial(
            action.clone(),
            self.state(),
            self.services.draw_context.clone(),
            self.services.history_manager.clone(),
            self.services.snapshot_builder,
            self.services.edit_session_service.clone(),
            self.services.session_id_generator.clone(),
            (self.services.is_batching)(),
            self.services.include_selection_in_history,
            None,
        );

        let final_context = self.execute_pipeline(initial_context.clone());
        if final_context.has_error() {
            let error_text = final_context
                .error
                .clone()
                .unwrap_or_else(|| "Dispatch failed".to_owned());
            let failure_source = final_context
                .error_source
                .clone()
                .unwrap_or_else(|| "unknown".to_owned());

            self.report_dispatch_error(
                action.as_ref(),
                failure_source.as_str(),
                error_text.as_str(),
                final_context.stack_trace.as_deref(),
                Some(final_context.trace_id.as_str()),
            );

            return self.rethrow_if_critical(action.as_ref(), &failure_source, &error_text);
        }

        self.commit(&initial_context, &final_context);
        Ok(())
    }

    fn execute_pipeline(&self, initial_context: DispatchContext) -> DispatchContext {
        let future = self.pipeline.execute(initial_context.clone());
        match catch_unwind(AssertUnwindSafe(|| block_on_future(future))) {
            Ok(context) => context,
            Err(payload) => initial_context.with_error(
                format!(
                    "Pipeline panic: {}",
                    panic_payload_to_string(payload.as_ref())
                ),
                "pipeline panic",
                Some("Pipeline".to_owned()),
            ),
        }
    }

    fn handle_config_action(&self, action: &dyn DrawAction) -> bool {
        if let Some(update) = action.as_any().downcast_ref::<UpdateConfig>() {
            let mut manager = self
                .services
                .config_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            let _ = manager.update(update.config.clone());
            return true;
        }

        if let Some(update) = action.as_any().downcast_ref::<UpdateSelectionConfig>() {
            let mut manager = self
                .services
                .config_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            let _ = manager.update_selection(update.selection.clone());
            return true;
        }

        if let Some(update) = action.as_any().downcast_ref::<UpdateCanvasConfig>() {
            let mut manager = self
                .services
                .config_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            let _ = manager.update_canvas(update.canvas.clone());
            return true;
        }

        false
    }

    fn resolve_edit_cancel_reason(&self, action: &dyn DrawAction) -> Option<EditCancelReason> {
        if !matches!(
            self.state().application.interaction,
            InteractionState::Editing(_)
        ) {
            return None;
        }

        if action.as_any().is::<Undo>() {
            let manager = self
                .services
                .history_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            if !manager.can_undo() {
                return None;
            }
        }

        if action.as_any().is::<Redo>() {
            let manager = self
                .services
                .history_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            if !manager.can_redo() {
                return None;
            }
        }

        if action.as_any().is::<CancelEdit>()
            || action.as_any().is::<UpdateEdit>()
            || action.as_any().is::<FinishEdit>()
        {
            return None;
        }

        if action.as_any().is::<StartEdit>() {
            return Some(EditCancelReason::NewEditStarted);
        }

        if action.conflicts_with_editing() {
            return Some(EditCancelReason::ConflictingAction);
        }

        None
    }

    fn commit(&self, initial_context: &DispatchContext, final_context: &DispatchContext) {
        self.maybe_increment_serial_number_defaults(
            &initial_context.initial_state,
            &final_context.current_state,
            initial_context.action.as_ref(),
        );

        self.apply_transition_effects(
            &initial_context.initial_state,
            &final_context.current_state,
            initial_context.action.as_ref(),
            final_context.has_state_changed(),
        );
    }

    fn maybe_increment_serial_number_defaults(
        &self,
        previous_state: &DrawState,
        next_state: &DrawState,
        action: &dyn DrawAction,
    ) {
        if !action.as_any().is::<FinishCreateElement>() {
            return;
        }

        let previous_elements = previous_state.domain.document.elements.as_slice();
        let next_elements = next_state.domain.document.elements.as_slice();
        if next_elements.len() <= previous_elements.len() {
            return;
        }

        let Some(last_element) = next_elements.last() else {
            return;
        };
        if last_element.data.as_ref().type_id().as_str() != SerialNumberData::TYPE_ID_TOKEN {
            return;
        }

        let Some(next_serial_from_document) = resolve_next_serial_number(next_elements) else {
            return;
        };

        let current_config = {
            let manager = self
                .services
                .config_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            manager.current().clone()
        };

        let current_serial = current_config.serial_number_style.serial_number;
        let next_serial = next_serial_from_document.max(current_serial);
        if next_serial == current_serial {
            return;
        }

        let next_serial_style =
            current_config
                .serial_number_style
                .copy_with(ElementStyleConfigPatch {
                    serial_number: Some(next_serial),
                    ..ElementStyleConfigPatch::default()
                });

        if next_serial_style == current_config.serial_number_style {
            return;
        }

        let next_config = current_config.copy_with(DrawConfigPatch {
            serial_number_style: Some(next_serial_style),
            ..DrawConfigPatch::default()
        });

        let mut manager = self
            .services
            .config_manager
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let _ = manager.update(next_config);
    }

    fn apply_transition_effects(
        &self,
        previous_state: &DrawState,
        next_state: &DrawState,
        action: &dyn DrawAction,
        has_state_changed: bool,
    ) {
        if has_state_changed {
            (self.services.write_state)(next_state.clone());
            if !(self.services.is_batching)() {
                self.services
                    .listener_registry
                    .notify(previous_state, next_state);
            }
        }

        self.emit_edit_session_events(previous_state, next_state, action);
        self.emit_state_change_events(previous_state, next_state);
    }

    fn emit_edit_session_events(
        &self,
        previous_state: &DrawState,
        next_state: &DrawState,
        action: &dyn DrawAction,
    ) {
        match (
            &previous_state.application.interaction,
            &next_state.application.interaction,
        ) {
            (InteractionState::Editing(previous), InteractionState::Editing(next)) => {
                self.emit_editing_transition(previous, next);
            }
            (InteractionState::Editing(previous), _) => {
                self.emit_editing_ended(previous, action);
            }
            (_, InteractionState::Editing(next)) => {
                self.emit_event::<EditSessionStartedEvent, _>(|| {
                    EditSessionStartedEvent::new(next.session_id.clone(), next.operation_id)
                });
            }
            _ => {}
        }
    }

    fn emit_editing_transition(&self, previous: &EditingState, next: &EditingState) {
        if previous.session_id == next.session_id {
            self.emit_event::<EditSessionUpdatedEvent, _>(|| {
                EditSessionUpdatedEvent::new(next.session_id.clone(), next.operation_id)
            });
            return;
        }

        self.emit_event::<EditSessionCancelledEvent, _>(|| {
            EditSessionCancelledEvent::new(
                previous.session_id.clone(),
                previous.operation_id,
                EventEditCancelReason::NewEditStarted,
            )
        });
        self.emit_event::<EditSessionStartedEvent, _>(|| {
            EditSessionStartedEvent::new(next.session_id.clone(), next.operation_id)
        });
    }

    fn emit_editing_ended(&self, previous: &EditingState, action: &dyn DrawAction) {
        if action.as_any().is::<FinishEdit>() {
            self.emit_event::<EditSessionFinishedEvent, _>(|| {
                EditSessionFinishedEvent::new(previous.session_id.clone(), previous.operation_id)
            });
            return;
        }

        self.emit_event::<EditSessionCancelledEvent, _>(|| {
            EditSessionCancelledEvent::new(
                previous.session_id.clone(),
                previous.operation_id,
                map_cancel_reason(self.resolve_cancel_reason(action)),
            )
        });
    }

    fn emit_state_change_events(&self, previous_state: &DrawState, next_state: &DrawState) {
        if has_document_state_changed(previous_state, next_state) {
            self.emit_event::<DocumentChangedEvent, _>(|| {
                DocumentChangedEvent::new(
                    next_state.domain.document.elements_version,
                    next_state.domain.document.elements.len(),
                )
            });
        }

        if has_selection_state_changed(previous_state, next_state) {
            self.emit_event::<SelectionChangedEvent, _>(|| {
                SelectionChangedEvent::new(
                    next_state.domain.selection.selected_ids.iter().cloned(),
                    next_state.domain.selection.selection_version,
                )
            });
        }

        if has_view_state_changed(previous_state, next_state) {
            self.emit_event::<ViewChangedEvent, _>(|| {
                ViewChangedEvent::new(next_state.application.view.camera)
            });
        }

        if has_interaction_state_changed(previous_state, next_state) {
            self.emit_event::<InteractionChangedEvent, _>(|| {
                InteractionChangedEvent::new(next_state.application.interaction.clone())
            });
        }

        self.sync_history_availability();
    }

    fn resolve_cancel_reason(&self, action: &dyn DrawAction) -> EditCancelReason {
        if let Some(cancel) = action.as_any().downcast_ref::<CancelEdit>() {
            return cancel.reason;
        }

        if action.as_any().is::<StartEdit>() {
            return EditCancelReason::NewEditStarted;
        }

        EditCancelReason::UserCancelled
    }

    fn report_dispatch_error(
        &self,
        action: &dyn DrawAction,
        source: &str,
        error: &str,
        stack_trace: Option<&str>,
        trace_id: Option<&str>,
    ) {
        let mut data = BTreeMap::new();
        data.insert("action".to_owned(), action.action_name().to_owned());
        data.insert(
            "criticality".to_owned(),
            format!("{:?}", action.criticality()),
        );
        data.insert("source".to_owned(), source.to_owned());
        if let Some(trace_id) = trace_id {
            data.insert("traceId".to_owned(), trace_id.to_owned());
        }

        self.services.draw_context.log.store().error(
            "Dispatch failed",
            Some(error),
            stack_trace,
            Some(&data),
        );

        let message = self.build_error_message(action, source, trace_id);
        let stack_trace_owned = stack_trace.map(str::to_owned);
        self.emit_event::<ErrorEvent, _>(|| ErrorEvent::new(message, error, stack_trace_owned));
    }

    fn build_error_message(
        &self,
        action: &dyn DrawAction,
        source: &str,
        trace_id: Option<&str>,
    ) -> String {
        match trace_id {
            Some(trace_id) if !trace_id.is_empty() => format!(
                "Dispatch {} failed (traceId: {}, source: {})",
                action.action_name(),
                trace_id,
                source
            ),
            _ => format!(
                "Dispatch {} failed (source: {})",
                action.action_name(),
                source
            ),
        }
    }

    fn rethrow_if_critical(
        &self,
        action: &dyn DrawAction,
        failure_source: &str,
        message: &str,
    ) -> Result<(), ActionProcessorError> {
        if action.criticality() != ActionCriticality::Critical {
            return Ok(());
        }

        Err(ActionProcessorError::CriticalDispatchFailure {
            action: action.action_name().to_owned(),
            failure_source: failure_source.to_owned(),
            message: message.to_owned(),
        })
    }

    fn emit_event<T, F>(&self, event_factory: F)
    where
        T: BusDrawEvent + 'static,
        F: FnOnce() -> T,
    {
        let _ = self.services.event_bus.emit_lazy::<T, F>(event_factory);
    }
}

fn resolve_next_serial_number(elements: &[DomainElementState]) -> Option<i64> {
    let max_number = elements
        .iter()
        .filter_map(|element| {
            if element.data.as_ref().type_id().as_str() != SerialNumberData::TYPE_ID_TOKEN {
                return None;
            }
            SerialNumberData::from_json(&element.data.to_json())
                .ok()
                .map(|data| data.number)
        })
        .max();

    max_number.map(|value| value + 1)
}

fn map_cancel_reason(reason: EditCancelReason) -> EventEditCancelReason {
    match reason {
        EditCancelReason::UserCancelled => EventEditCancelReason::UserCancelled,
        EditCancelReason::ConflictingAction => EventEditCancelReason::ConflictingAction,
        EditCancelReason::NewEditStarted => EventEditCancelReason::NewEditStarted,
    }
}

fn panic_payload_to_string(payload: &(dyn Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<String>() {
        return message.clone();
    }
    if let Some(message) = payload.downcast_ref::<&str>() {
        return (*message).to_owned();
    }
    "panic without message".to_owned()
}

fn block_on_future<T>(future: Pin<Box<dyn Future<Output = T> + Send + 'static>>) -> T {
    let mut future = future;
    let waker = noop_waker();
    let mut context = Context::from_waker(&waker);

    loop {
        match future.as_mut().poll(&mut context) {
            Poll::Ready(value) => return value,
            Poll::Pending => std::thread::yield_now(),
        }
    }
}

fn noop_waker() -> Waker {
    // SAFETY: All functions in the vtable are no-ops and uphold RawWaker
    // invariants for a null data pointer.
    unsafe { Waker::from_raw(noop_raw_waker()) }
}

fn noop_raw_waker() -> RawWaker {
    RawWaker::new(std::ptr::null(), &NOOP_WAKER_VTABLE)
}

unsafe fn noop_clone(_: *const ()) -> RawWaker {
    noop_raw_waker()
}

unsafe fn noop_wake(_: *const ()) {}

unsafe fn noop_wake_by_ref(_: *const ()) {}

unsafe fn noop_drop(_: *const ()) {}

static NOOP_WAKER_VTABLE: RawWakerVTable =
    RawWakerVTable::new(noop_clone, noop_wake, noop_wake_by_ref, noop_drop);
