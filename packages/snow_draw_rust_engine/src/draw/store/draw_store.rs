#![allow(dead_code)]

use std::any::Any;
use std::backtrace::Backtrace;
use std::collections::BTreeSet;
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Receiver;
use std::sync::{Arc, Mutex};

use thiserror::Error;

use crate::draw::actions::draw_actions::{ClearHistory, DrawAction, Redo, Undo};
use crate::draw::config::config_manager::ConfigManager;
use crate::draw::config::draw_config::DrawConfig;
use crate::draw::core::callbacks::VoidCallback;
use crate::draw::core::draw_context::DrawContext;
use crate::draw::edit::core::edit_session_id_generator::EditSessionIdGenerator;
use crate::draw::edit::core::edit_session_service::EditSessionService;
use crate::draw::events::event_bus::{
    DrawEvent, DrawEventStream, EventBus, StreamSubscription, TypedEventStream,
};
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::edit_session_id::EditSessionId;
use crate::draw::services::log::log_service::LogData;
use crate::draw::store::dispatch::action_processor::{
    ActionProcessor, ActionProcessorError, ActionProcessorServices,
};
use crate::draw::store::draw_store_interface::{
    DrawStateChange, DrawStore, EqualityFn, EventSubscriptionOptions, StateChangeListener,
    StateProvider, StateSelector,
};
use crate::draw::store::history_manager::{HistoryManager, HistoryManagerSnapshot};
use crate::draw::store::listener_registry::{ListenerErrorHandler, ListenerRegistry};
use crate::draw::store::middleware::middleware_context::SharedHistoryManager;
use crate::draw::store::middleware::middleware_pipeline::MiddlewarePipeline;
use crate::draw::store::middleware::middleware_pipeline_factory::MiddlewarePipelineFactory;
use crate::draw::store::snapshot::PersistentSnapshot;
use crate::draw::store::snapshot_builder::SnapshotBuilder;

/// Draw-store level failures.
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum DrawStoreError {
    #[error("DrawStore has been disposed and cannot be used")]
    Disposed,
    #[error("Dispatch failed: {0}")]
    Dispatch(String),
    #[error("Critical dispatch failure: {0}")]
    CriticalDispatch(String),
}

impl DrawStoreError {
    fn from_processor_error(error: ActionProcessorError) -> Self {
        match error {
            ActionProcessorError::CriticalDispatchFailure { .. } => {
                Self::CriticalDispatch(error.to_string())
            }
            _ => Self::Dispatch(error.to_string()),
        }
    }
}

/// Constructor options for [`DefaultDrawStore`].
#[derive(Default)]
pub struct DefaultDrawStoreOptions {
    pub initial_state: Option<DrawState>,
    pub include_selection_in_history: bool,
    pub history_manager: Option<HistoryManager>,
    pub snapshot_builder: Option<SnapshotBuilder>,
    pub pipeline: Option<MiddlewarePipeline>,
    pub event_bus: Option<EventBus>,
    pub listener_error_handler: Option<ListenerErrorHandler>,
}

/// Rust translation of Dart `DefaultDrawStore`.
pub struct DefaultDrawStore {
    context: DrawContext,
    include_selection_in_history: bool,
    snapshot_builder: SnapshotBuilder,
    owns_event_bus: bool,
    event_bus: Arc<EventBus>,
    config_manager: Arc<Mutex<ConfigManager<DrawConfig>>>,
    listener_registry: ListenerRegistry,
    history_manager: SharedHistoryManager,
    edit_session_service: Arc<EditSessionService>,
    action_processor: ActionProcessor,
    state: Arc<Mutex<DrawState>>,
    is_batching: Arc<AtomicBool>,
    batch_start_snapshot: Option<PersistentSnapshot>,
    batch_start_state: Option<DrawState>,
    is_disposed: bool,
}

impl DefaultDrawStore {
    pub fn new(context: DrawContext, options: DefaultDrawStoreOptions) -> Self {
        let initial_state = options.initial_state.unwrap_or_default();
        let state = Arc::new(Mutex::new(initial_state));
        let is_batching = Arc::new(AtomicBool::new(false));

        let owns_event_bus = options.event_bus.is_none() && context.event_bus.is_none();
        let event_bus = options
            .event_bus
            .map(Arc::new)
            .or_else(|| context.event_bus.clone())
            .unwrap_or_else(|| Arc::new(EventBus::new()));

        let history_manager = options
            .history_manager
            .unwrap_or_else(|| HistoryManager::new(50, Some(context.log.as_ref())));
        let history_manager = Arc::new(Mutex::new(history_manager));

        let snapshot_builder = options.snapshot_builder.unwrap_or_default();
        let config_manager = context.config_manager.clone();

        let listener_registry =
            ListenerRegistry::new(options.listener_error_handler.or_else(|| {
                let log = context.log.clone();
                Some(Arc::new(
                    move |payload: &(dyn Any + Send), backtrace: &Backtrace| {
                        let mut data = LogData::new();
                        data.insert("panic".to_owned(), panic_payload_to_string(payload));
                        log.store().error(
                            "Listener threw during notification",
                            Some("listener panic"),
                            Some(&backtrace.to_string()),
                            Some(&data),
                        );
                    },
                ))
            }));

        let config_manager_for_edit = config_manager.clone();
        let edit_session_service = Arc::new(EditSessionService::from_registry(
            context.edit_operations.as_ref().clone(),
            move || {
                config_manager_for_edit
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .current()
                    .clone()
            },
            Some(context.text_metrics_service.clone()),
            None,
        ));

        let session_sequence = Arc::new(Mutex::new(0_u64));
        let sequence_for_generator = session_sequence.clone();
        let session_id_generator: EditSessionIdGenerator = Arc::new(move || {
            let mut sequence = sequence_for_generator
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            let session_id = format!("edit_{sequence}");
            *sequence = sequence.wrapping_add(1);
            session_id
        });

        let read_state = {
            let state = state.clone();
            Arc::new(move || {
                state
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .clone()
            })
        };
        let write_state = {
            let state = state.clone();
            Arc::new(move |next_state: DrawState| {
                *state
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner()) = next_state;
            })
        };
        let is_batching_reader = {
            let is_batching = is_batching.clone();
            Arc::new(move || is_batching.load(Ordering::SeqCst))
        };

        let pipeline = options
            .pipeline
            .unwrap_or_else(|| MiddlewarePipelineFactory::new().create_default(Vec::new()));

        let services = ActionProcessorServices::new(
            context.clone(),
            read_state,
            write_state,
            history_manager.clone(),
            config_manager.clone(),
            listener_registry.clone(),
            snapshot_builder,
            edit_session_service.clone(),
            session_id_generator,
            is_batching_reader,
            options.include_selection_in_history,
            event_bus.clone(),
        );

        let action_processor = ActionProcessor::new(services, pipeline);

        Self {
            context,
            include_selection_in_history: options.include_selection_in_history,
            snapshot_builder,
            owns_event_bus,
            event_bus,
            config_manager,
            listener_registry,
            history_manager,
            edit_session_service,
            action_processor,
            state,
            is_batching,
            batch_start_snapshot: None,
            batch_start_state: None,
            is_disposed: false,
        }
    }

    pub fn can_undo(&self) -> bool {
        self.history_manager
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .can_undo()
    }

    pub fn can_redo(&self) -> bool {
        self.history_manager
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .can_redo()
    }

    pub fn begin_batch(&mut self) -> Result<(), DrawStoreError> {
        self.check_not_disposed()?;
        if self.is_batching.load(Ordering::SeqCst) {
            return Ok(());
        }

        self.is_batching.store(true, Ordering::SeqCst);
        let start_state = self.state();
        self.batch_start_state = Some(start_state.clone());
        self.batch_start_snapshot = Some(self.build_snapshot(&start_state));

        let mut data = LogData::new();
        data.insert(
            "elements".to_owned(),
            start_state.domain.document.elements.len().to_string(),
        );
        self.context
            .log
            .store()
            .debug("Batch snapshot captured", Some(&data));
        Ok(())
    }

    pub fn end_batch(&mut self) -> Result<(), DrawStoreError> {
        self.check_not_disposed()?;
        if !self.is_batching.load(Ordering::SeqCst) {
            return Ok(());
        }

        self.is_batching.store(false, Ordering::SeqCst);

        let start_state = self
            .batch_start_state
            .take()
            .unwrap_or_else(|| self.state());
        let start_snapshot = self
            .batch_start_snapshot
            .take()
            .unwrap_or_else(|| self.build_snapshot(&start_state));
        let end_state = self.state();
        let end_snapshot = self.build_snapshot(&end_state);

        let recorded = if start_snapshot != end_snapshot {
            let mut manager = self
                .history_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            manager.record(start_snapshot, end_snapshot, None, None, None, None)
        } else {
            false
        };

        let mut data = LogData::new();
        data.insert("recorded".to_owned(), recorded.to_string());
        self.context.log.store().debug("Batch ended", Some(&data));

        if start_state != end_state {
            self.listener_registry.notify(&start_state, &end_state);
        }

        Ok(())
    }

    pub fn dispatch_result(&mut self, action: Box<dyn DrawAction>) -> Result<(), DrawStoreError> {
        self.check_not_disposed()?;
        let action: Arc<dyn DrawAction> = Arc::from(action);
        self.action_processor
            .dispatch(action)
            .map_err(DrawStoreError::from_processor_error)
    }

    pub fn undo<'a>(&'a mut self) -> Pin<Box<dyn Future<Output = ()> + Send + 'a>> {
        self.dispatch(Box::new(Undo))
    }

    pub fn redo<'a>(&'a mut self) -> Pin<Box<dyn Future<Output = ()> + Send + 'a>> {
        self.dispatch(Box::new(Redo))
    }

    pub fn clear_history<'a>(&'a mut self) -> Pin<Box<dyn Future<Output = ()> + Send + 'a>> {
        self.dispatch(Box::new(ClearHistory))
    }

    pub fn export_history(&self) -> HistoryManagerSnapshot {
        self.history_manager
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .snapshot()
    }

    pub fn restore_history(
        &mut self,
        snapshot: HistoryManagerSnapshot,
    ) -> Result<(), DrawStoreError> {
        self.check_not_disposed()?;
        {
            let mut manager = self
                .history_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            manager.restore(snapshot);
        }
        self.action_processor.sync_history_availability();
        Ok(())
    }

    pub fn dispose(&mut self) {
        if self.is_disposed {
            return;
        }

        self.is_disposed = true;
        self.action_processor.dispose();

        {
            let mut manager = self
                .config_manager
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            let _ = manager.dispose();
        }

        if self.owns_event_bus {
            let _ = self.event_bus.dispose();
        }

        self.listener_registry.clear();
        self.history_manager
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clear();
        self.context.log.dispose();
    }

    fn check_not_disposed(&self) -> Result<(), DrawStoreError> {
        if self.is_disposed {
            return Err(DrawStoreError::Disposed);
        }
        Ok(())
    }

    fn build_snapshot(&self, source_state: &DrawState) -> PersistentSnapshot {
        self.snapshot_builder
            .build_snapshot_from_state(source_state, self.include_selection_in_history)
    }
}

impl StateProvider for DefaultDrawStore {
    fn state(&self) -> DrawState {
        self.state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone()
    }
}

impl DrawStore for DefaultDrawStore {
    fn context(&self) -> &DrawContext {
        &self.context
    }

    fn config(&self) -> DrawConfig {
        self.config_manager
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .current()
            .clone()
    }

    fn config_stream(&self) -> Receiver<DrawConfig> {
        self.config_manager
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .stream()
    }

    fn event_bus(&self) -> &EventBus {
        self.event_bus.as_ref()
    }

    fn dispatch<'a>(
        &'a mut self,
        action: Box<dyn DrawAction>,
    ) -> Pin<Box<dyn Future<Output = ()> + Send + 'a>> {
        Box::pin(async move {
            let result = self.dispatch_result(action);
            match result {
                Ok(()) => {}
                Err(DrawStoreError::CriticalDispatch(message)) => {
                    panic!("{message}");
                }
                Err(error) => {
                    self.context.log.store().error(
                        "Dispatch failed at store boundary",
                        Some(&error.to_string()),
                        None,
                        None,
                    );
                }
            }
        })
    }

    fn listen(
        &mut self,
        listener: StateChangeListener<DrawState>,
        change_types: Option<BTreeSet<DrawStateChange>>,
    ) -> VoidCallback {
        self.listener_registry.register(listener, change_types)
    }

    fn unsubscribe(&mut self, listener: &StateChangeListener<DrawState>) -> bool {
        self.listener_registry.unregister(listener)
    }

    fn select<T>(
        &mut self,
        selector: Arc<dyn StateSelector<DrawState, T>>,
        listener: StateChangeListener<T>,
        equals: Option<EqualityFn<T>>,
        change_types: Option<BTreeSet<DrawStateChange>>,
    ) -> VoidCallback
    where
        T: Clone + PartialEq + Send + Sync + 'static,
    {
        let equals = equals.unwrap_or_else(|| {
            let selector = selector.clone();
            Arc::new(move |previous: &T, next: &T| selector.equals(previous, next))
        });

        let previous = Arc::new(Mutex::new(selector.select(&self.state())));
        let selector_ref = selector.clone();
        let listener_ref = listener.clone();
        let previous_ref = previous.clone();

        self.listen(
            Arc::new(move |state| {
                let selected = selector_ref.select(state);
                let mut previous = previous_ref
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner());
                if !equals(&previous, &selected) {
                    *previous = selected.clone();
                    listener_ref(&selected);
                }
            }),
            change_types,
        )
    }

    fn on_event<T, F>(&self, handler: F, _options: EventSubscriptionOptions) -> StreamSubscription
    where
        T: DrawEvent + 'static,
        F: Fn(&T) + Send + Sync + 'static,
    {
        self.event_bus.on::<T, F>(handler)
    }

    fn event_stream(&self) -> DrawEventStream<'_> {
        self.event_bus.stream()
    }

    fn event_stream_of<T>(&self) -> TypedEventStream<'_, T>
    where
        T: DrawEvent + 'static,
    {
        self.event_bus.stream_of::<T>()
    }
}

fn panic_payload_to_string(payload: &(dyn Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<String>() {
        return message.clone();
    }
    if let Some(message) = payload.downcast_ref::<&str>() {
        return (*message).to_owned();
    }
    "listener panic".to_owned()
}

#[allow(clippy::unused_self)]
fn _unused_edit_session_id(_: EditSessionId) {}
