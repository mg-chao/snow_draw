#![allow(dead_code)]

use std::collections::{BTreeMap, VecDeque};
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use serde_json::{json, Value};

use super::input_event::{PointerHoverInputEvent, PointerMoveInputEvent};
use super::middleware::default_middlewares::{
    InputEvent as DefaultMiddlewareInputEvent, InputEventKind,
};
use super::middleware::input_middleware::{
    InputEvent as MiddlewareInputEvent, InputMiddleware, InputPipeline, MiddlewareContext,
};
use super::plugin_engine::{PluginContext, PluginResult};
use super::plugin_registry::{PluginRegistry, PluginRegistryError};

const PROCESSING_FAILURE_REASON: &str = "Input processing failed";
const DISPOSED_REASON: &str = "Input coordinator disposed";
const COALESCED_EVENT_MESSAGE: &str = "Event coalesced by coordinator";
const PRESSURE_COALESCING_TOLERANCE: f64 = 1e-4;
const EVENT_INTERCEPTED_MESSAGE: &str = "Event intercepted by middleware";

/// Boxed async value used by plugin-facing APIs.
pub type PluginFuture<T> = Pin<Box<dyn Future<Output = T> + 'static>>;

/// Plugin-based input coordinator.
///
/// This mirrors Dart `PluginInputCoordinator`:
/// 1. middleware preprocess
/// 2. plugin registry dispatch
/// 3. queue/coalescing to avoid move-event flooding
pub struct PluginInputCoordinator {
    plugin_context: PluginContext,
    registry: PluginRegistry,
    pipeline: InputPipeline,
    queue: VecDeque<QueuedInputEvent>,
    completed_results: BTreeMap<u64, Option<PluginResult>>,
    next_event_id: u64,
    is_draining: bool,
    is_disposed: bool,
    coalesced_event_count: usize,
}

impl PluginInputCoordinator {
    /// Creates a coordinator and registers the default plugin set.
    pub fn new(
        plugin_context: PluginContext,
        middlewares: Option<Vec<Arc<dyn InputMiddleware>>>,
    ) -> Self {
        let mut registry = PluginRegistry::new(plugin_context.clone());
        if let Err(error) = registry.register_defaults() {
            let logger = plugin_context.context().log.input();
            logger.error(
                "Failed to register default input plugins",
                Some(&error.to_string()),
                None,
                None,
            );
        }

        Self::with_registry(plugin_context, registry, middlewares)
    }

    /// Creates a coordinator with an explicit registry implementation.
    pub fn with_registry(
        plugin_context: PluginContext,
        registry: PluginRegistry,
        middlewares: Option<Vec<Arc<dyn InputMiddleware>>>,
    ) -> Self {
        Self {
            plugin_context,
            registry,
            pipeline: InputPipeline::new(middlewares.unwrap_or_default()),
            queue: VecDeque::new(),
            completed_results: BTreeMap::new(),
            next_event_id: 0,
            is_draining: false,
            is_disposed: false,
            coalesced_event_count: 0,
        }
    }

    /// Returns the plugin registry.
    pub fn registry(&self) -> &PluginRegistry {
        &self.registry
    }

    /// Returns a mutable plugin registry.
    pub fn registry_mut(&mut self) -> &mut PluginRegistry {
        &mut self.registry
    }

    /// Registers plugins using the coordinator-owned registry.
    pub fn register_plugins(
        &mut self,
        plugins: Vec<Box<dyn crate::draw::input::plugin_engine::InputPlugin>>,
    ) -> Result<(), PluginRegistryError> {
        self.registry.register_all(plugins)
    }

    /// Returns the middleware pipeline.
    pub fn pipeline(&self) -> &InputPipeline {
        &self.pipeline
    }

    /// Handles one input event.
    pub async fn handle_event(&mut self, event: MiddlewareInputEvent) -> Option<PluginResult> {
        if self.is_disposed {
            return Some(PluginResult::unhandled(Some(DISPOSED_REASON.to_owned())));
        }

        let event_id = self.next_event_id;
        self.next_event_id = self.next_event_id.wrapping_add(1);

        self.enqueue(QueuedInputEvent {
            id: event_id,
            event,
        });

        if !self.is_draining {
            self.drain_queue().await;
        }

        self.completed_results.remove(&event_id).unwrap_or_else(|| {
            Some(PluginResult::unhandled(Some(
                PROCESSING_FAILURE_REASON.to_owned(),
            )))
        })
    }

    fn enqueue(&mut self, incoming_event: QueuedInputEvent) {
        if self.try_coalesce(&incoming_event) {
            return;
        }

        self.queue.push_back(incoming_event);
    }

    fn try_coalesce(&mut self, incoming_event: &QueuedInputEvent) -> bool {
        if !self.is_draining || self.queue.is_empty() {
            return false;
        }

        if !is_coalescible_event(&incoming_event.event) {
            return false;
        }

        let Some(last_queued_event) = self.queue.back() else {
            return false;
        };

        if !can_coalesce_events(&last_queued_event.event, &incoming_event.event) {
            return false;
        }

        let last = self
            .queue
            .pop_back()
            .expect("queue back should exist when coalescing");

        self.completed_results.insert(
            last.id,
            Some(PluginResult::consumed(Some(
                COALESCED_EVENT_MESSAGE.to_owned(),
            ))),
        );
        self.coalesced_event_count += 1;

        self.queue.push_back(incoming_event.clone());
        true
    }

    async fn drain_queue(&mut self) {
        self.is_draining = true;

        while let Some(queued_event) = self.queue.pop_front() {
            let result = self.process_event(queued_event.event.clone()).await;
            self.completed_results.insert(queued_event.id, result);
        }

        self.is_draining = false;
    }

    async fn process_event(&mut self, event: MiddlewareInputEvent) -> Option<PluginResult> {
        let middleware_context = MiddlewareContext::new(
            self.plugin_context.state(),
            None,
            Some(self.plugin_context.context().log.input()),
        );

        let processed_event = self.pipeline.execute(event, middleware_context).await;
        let Some(processed_event) = processed_event else {
            return Some(PluginResult::handled(Some(
                EVENT_INTERCEPTED_MESSAGE.to_owned(),
            )));
        };

        self.registry.dispatch(&processed_event)
    }

    /// Resets all plugin state.
    pub fn reset(&mut self) {
        self.registry.reset_all();
    }

    /// Disposes resources owned by this coordinator.
    pub async fn dispose(&mut self) {
        if self.is_disposed {
            return;
        }

        self.is_disposed = true;
        self.complete_queued_events(Some(PluginResult::unhandled(Some(
            DISPOSED_REASON.to_owned(),
        ))));

        if !self.is_draining && !self.queue.is_empty() {
            self.drain_queue().await;
        }

        self.registry.dispose();
    }

    fn complete_queued_events(&mut self, result: Option<PluginResult>) {
        while let Some(queued_event) = self.queue.pop_front() {
            self.completed_results
                .insert(queued_event.id, result.clone());
        }
    }

    /// Returns coordinator statistics.
    pub fn get_stats(&self) -> BTreeMap<String, Value> {
        let middleware_names = self
            .pipeline
            .middlewares()
            .iter()
            .map(|middleware| Value::String(middleware.name().to_owned()))
            .collect::<Vec<_>>();

        let registry_stats = self.registry.get_stats();
        let plugin_stats = registry_stats
            .plugins_by_priority
            .iter()
            .map(|plugin| {
                json!({
                    "id": plugin.id,
                    "name": plugin.name,
                    "priority": plugin.priority,
                })
            })
            .collect::<Vec<_>>();

        let event_type_handlers = registry_stats
            .event_type_handlers
            .iter()
            .map(|(event_type, count)| (event_type.clone(), json!(count)))
            .collect::<serde_json::Map<String, Value>>();

        let mut stats = BTreeMap::new();
        stats.insert("middlewareCount".to_owned(), json!(self.pipeline.len()));
        stats.insert("middlewares".to_owned(), Value::Array(middleware_names));
        stats.insert("queuedEvents".to_owned(), json!(self.queue.len()));
        stats.insert("isDraining".to_owned(), json!(self.is_draining));
        stats.insert(
            "coalescedEvents".to_owned(),
            json!(self.coalesced_event_count),
        );
        stats.insert(
            "totalPlugins".to_owned(),
            json!(registry_stats.total_plugins),
        );
        stats.insert("pluginsByPriority".to_owned(), Value::Array(plugin_stats));
        stats.insert(
            "eventTypeHandlers".to_owned(),
            Value::Object(event_type_handlers),
        );
        stats
    }
}

#[derive(Clone)]
struct QueuedInputEvent {
    id: u64,
    event: MiddlewareInputEvent,
}

fn is_coalescible_event(event: &MiddlewareInputEvent) -> bool {
    if event.as_ref().is::<PointerMoveInputEvent>() || event.as_ref().is::<PointerHoverInputEvent>()
    {
        return true;
    }

    let Some(default_event) = event.as_ref().downcast_ref::<DefaultMiddlewareInputEvent>() else {
        return false;
    };

    matches!(
        default_event.kind,
        InputEventKind::PointerMove | InputEventKind::PointerHover
    )
}

fn can_coalesce_events(
    previous_event: &MiddlewareInputEvent,
    next_event: &MiddlewareInputEvent,
) -> bool {
    if previous_event.as_ref().type_id() != next_event.as_ref().type_id() {
        return false;
    }

    if let (Some(previous), Some(next)) = (
        previous_event
            .as_ref()
            .downcast_ref::<PointerMoveInputEvent>(),
        next_event.as_ref().downcast_ref::<PointerMoveInputEvent>(),
    ) {
        return previous.input.modifiers == next.input.modifiers
            && is_pressure_compatible(previous.input.pressure, next.input.pressure);
    }

    if let (Some(previous), Some(next)) = (
        previous_event
            .as_ref()
            .downcast_ref::<PointerHoverInputEvent>(),
        next_event.as_ref().downcast_ref::<PointerHoverInputEvent>(),
    ) {
        return previous.input.modifiers == next.input.modifiers
            && is_pressure_compatible(previous.input.pressure, next.input.pressure);
    }

    if let (Some(previous), Some(next)) = (
        previous_event
            .as_ref()
            .downcast_ref::<DefaultMiddlewareInputEvent>(),
        next_event
            .as_ref()
            .downcast_ref::<DefaultMiddlewareInputEvent>(),
    ) {
        return previous.modifiers == next.modifiers
            && is_pressure_compatible(previous.pressure, next.pressure);
    }

    false
}

fn is_pressure_compatible(previous_pressure: f64, next_pressure: f64) -> bool {
    if previous_pressure == 0.0 || next_pressure == 0.0 {
        return previous_pressure == next_pressure;
    }

    (previous_pressure - next_pressure).abs() <= PRESSURE_COALESCING_TOLERANCE
}
