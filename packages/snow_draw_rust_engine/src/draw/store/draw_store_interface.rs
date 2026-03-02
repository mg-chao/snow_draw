#![allow(dead_code)]

use std::collections::BTreeSet;
use std::error::Error;
use std::future::Future;
use std::pin::Pin;
use std::sync::mpsc::Receiver;
use std::sync::Arc;

use crate::draw::actions::draw_actions::DrawAction;
use crate::draw::config::draw_config::DrawConfig;
use crate::draw::core::callbacks::VoidCallback;
use crate::draw::core::draw_context::DrawContext;
use crate::draw::events::event_bus::{
    DrawEvent, DrawEventStream, EventBus, StreamSubscription, TypedEventStream,
};
use crate::draw::models::draw_state::DrawState;

/// Callback type used for draw-state listeners.
pub type StateChangeListener<T> = Arc<dyn Fn(&T) + Send + Sync + 'static>;

/// Optional equality override for selector subscriptions.
pub type EqualityFn<T> = Arc<dyn Fn(&T, &T) -> bool + Send + Sync + 'static>;

/// Error type used by event listener hooks.
pub type EventError = Box<dyn Error + Send + Sync + 'static>;

/// Optional `onError` callback for event subscriptions.
pub type EventErrorHandler = Arc<dyn Fn(EventError) + Send + Sync + 'static>;

/// Optional `onDone` callback for event subscriptions.
pub type EventDoneHandler = Arc<dyn Fn() + Send + Sync + 'static>;

/// Mirrors Dart `DrawStateChange`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum DrawStateChange {
    Document,
    Selection,
    View,
    Interaction,
}

/// Minimal state-provider abstraction used by input-layer dependencies.
pub trait StateProvider {
    fn state(&self) -> DrawState;
}

/// Selector abstraction used for slice subscriptions.
pub trait StateSelector<S, T>: Send + Sync {
    /// Selects data from the full state.
    fn select(&self, state: &S) -> T;

    /// Compares two selected values for change detection.
    ///
    /// The default behavior uses `PartialEq`.
    fn equals(&self, previous: &T, next: &T) -> bool
    where
        T: PartialEq,
    {
        previous == next
    }
}

/// Optional listener lifecycle hooks when subscribing to typed events.
#[derive(Clone, Default)]
pub struct EventSubscriptionOptions {
    pub on_error: Option<EventErrorHandler>,
    pub on_done: Option<EventDoneHandler>,
    pub cancel_on_error: Option<bool>,
}

/// Draw-store abstraction for testability.
///
/// Input-layer components should depend on this trait so tests can inject
/// lightweight fake implementations.
pub trait DrawStore: StateProvider {
    /// Access to the shared draw context.
    fn context(&self) -> &DrawContext;

    /// Current drawing configuration snapshot.
    fn config(&self) -> DrawConfig;

    /// Broadcast stream of configuration changes.
    fn config_stream(&self) -> Receiver<DrawConfig>;

    /// Backing event bus used for event streams and typed listeners.
    fn event_bus(&self) -> &EventBus;

    /// Stream facade for all draw events.
    fn event_stream(&self) -> DrawEventStream<'_> {
        self.event_bus().stream()
    }

    /// Returns a typed event stream for `T`.
    fn event_stream_of<T>(&self) -> TypedEventStream<'_, T>
    where
        T: DrawEvent + 'static,
    {
        self.event_bus().stream_of::<T>()
    }

    /// Registers a typed event listener for `T`.
    fn on_event<T, F>(&self, handler: F, _options: EventSubscriptionOptions) -> StreamSubscription
    where
        T: DrawEvent + 'static,
        F: Fn(&T) + Send + Sync + 'static,
    {
        self.event_bus().on::<T, F>(handler)
    }

    /// Dispatches one action through the store pipeline.
    fn dispatch<'a>(
        &'a mut self,
        action: Box<dyn DrawAction>,
    ) -> Pin<Box<dyn Future<Output = ()> + Send + 'a>>;

    /// Subscribes to draw state changes.
    ///
    /// `change_types = None` means all tracked state-change domains.
    fn listen(
        &mut self,
        listener: StateChangeListener<DrawState>,
        change_types: Option<BTreeSet<DrawStateChange>>,
    ) -> VoidCallback;

    /// Unsubscribes a previously registered draw-state listener.
    fn unsubscribe(&mut self, listener: &StateChangeListener<DrawState>) -> bool;

    /// Subscribes to a specific state slice.
    ///
    /// Uses `selector` to choose data from the full state and only calls
    /// `listener` when the selected value changes.
    fn select<T>(
        &mut self,
        selector: Arc<dyn StateSelector<DrawState, T>>,
        listener: StateChangeListener<T>,
        equals: Option<EqualityFn<T>>,
        change_types: Option<BTreeSet<DrawStateChange>>,
    ) -> VoidCallback
    where
        T: Clone + PartialEq + Send + Sync + 'static;
}
