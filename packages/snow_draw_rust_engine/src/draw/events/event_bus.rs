#![allow(dead_code)]

use std::any::{Any, TypeId};
use std::collections::HashMap;
use std::marker::PhantomData;
use std::sync::{Arc, Mutex};

/// Base trait for draw events.
///
/// This corresponds to the Dart `DrawEvent` base class.
pub trait DrawEvent: Any + Send + Sync {
    /// Returns this value as [`Any`] for typed downcasting.
    fn as_any(&self) -> &dyn Any;

    /// Returns whether this event can be routed to listeners registered for
    /// `expected_type`.
    ///
    /// The default implementation supports:
    /// - listeners for this concrete event type
    /// - listeners for the root `DrawEvent` stream
    fn matches_type(&self, expected_type: TypeId) -> bool {
        expected_type == draw_event_type_id() || self.as_any().type_id() == expected_type
    }
}

impl<T> DrawEvent for T
where
    T: Any + Send + Sync,
{
    fn as_any(&self) -> &dyn Any {
        self
    }
}

/// Shared event reference passed through listeners.
pub type DrawEventRef = Arc<dyn DrawEvent>;

type ErasedEventHandler = Arc<dyn Fn(&dyn DrawEvent) + Send + Sync + 'static>;

#[derive(Clone)]
struct ListenerEntry {
    id: u64,
    handler: ErasedEventHandler,
}

#[derive(Clone)]
struct TypedChannel {
    requested_type: TypeId,
    listeners: Vec<ListenerEntry>,
}

impl TypedChannel {
    fn new(requested_type: TypeId) -> Self {
        Self {
            requested_type,
            listeners: Vec::new(),
        }
    }

    fn has_listeners(&self) -> bool {
        !self.listeners.is_empty()
    }

    fn matches(&self, event: &dyn DrawEvent) -> bool {
        event.matches_type(self.requested_type)
    }

    fn accepts_type(&self, queried_type: TypeId) -> bool {
        self.requested_type == draw_event_type_id() || self.requested_type == queried_type
    }

    fn is_subtype_of(&self, queried_type: TypeId) -> bool {
        queried_type == draw_event_type_id() || self.requested_type == queried_type
    }
}

#[derive(Default)]
struct EventBusState {
    typed_channels: HashMap<TypeId, TypedChannel>,
    next_listener_id: u64,
    is_closed: bool,
}

impl EventBusState {
    fn new() -> Self {
        let mut typed_channels = HashMap::new();
        typed_channels.insert(
            draw_event_type_id(),
            TypedChannel::new(draw_event_type_id()),
        );

        Self {
            typed_channels,
            next_listener_id: 0,
            is_closed: false,
        }
    }

    fn collect_matching_handlers(&self, event: &dyn DrawEvent) -> Vec<ErasedEventHandler> {
        let mut handlers = Vec::new();
        for channel in self.typed_channels.values() {
            if !channel.has_listeners() || !channel.matches(event) {
                continue;
            }

            handlers.extend(
                channel
                    .listeners
                    .iter()
                    .map(|entry| Arc::clone(&entry.handler)),
            );
        }
        handlers
    }
}

/// Handle representing one stream subscription.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct StreamSubscription {
    channel_type_id: TypeId,
    listener_id: Option<u64>,
}

impl StreamSubscription {
    fn inactive(channel_type_id: TypeId) -> Self {
        Self {
            channel_type_id,
            listener_id: None,
        }
    }

    /// Returns `true` when this subscription is currently attached to a bus.
    pub fn is_active(&self) -> bool {
        self.listener_id.is_some()
    }

    /// Cancels this subscription from `bus`.
    pub fn cancel(self, bus: &EventBus) -> bool {
        bus.off(self)
    }
}

/// Read-only stream facade for all events.
pub struct DrawEventStream<'a> {
    bus: &'a EventBus,
}

impl<'a> DrawEventStream<'a> {
    /// Registers a listener for all events.
    pub fn listen<F>(&self, handler: F) -> StreamSubscription
    where
        F: Fn(&dyn DrawEvent) + Send + Sync + 'static,
    {
        self.bus
            .subscribe_erased(draw_event_type_id(), Arc::new(handler))
    }
}

/// Read-only typed stream facade.
pub struct TypedEventStream<'a, T>
where
    T: DrawEvent + 'static,
{
    bus: &'a EventBus,
    _marker: PhantomData<T>,
}

impl<'a, T> TypedEventStream<'a, T>
where
    T: DrawEvent + 'static,
{
    /// Registers a listener for events of type `T`.
    pub fn listen<F>(&self, handler: F) -> StreamSubscription
    where
        F: Fn(&T) + Send + Sync + 'static,
    {
        let wrapped = move |event: &dyn DrawEvent| {
            if let Some(typed) = event.as_any().downcast_ref::<T>() {
                handler(typed);
            }
        };

        self.bus
            .subscribe_erased(TypeId::of::<T>(), Arc::new(wrapped))
    }
}

/// Event bus with typed publish/subscribe semantics.
///
/// Notes:
/// - Disposing the bus clears all channels and future subscriptions become
///   inactive.
/// - Rust does not model Dart class inheritance at runtime in the same way.
///   The default matching logic handles exact event type matches plus
///   listeners on the root `DrawEvent` stream.
pub struct EventBus {
    state: Mutex<EventBusState>,
}

impl EventBus {
    /// Creates a new event bus.
    pub fn new() -> Self {
        Self {
            state: Mutex::new(EventBusState::new()),
        }
    }

    /// Event stream for all events.
    pub fn stream(&self) -> DrawEventStream<'_> {
        DrawEventStream { bus: self }
    }

    /// Whether there are active listeners.
    pub fn has_listeners(&self) -> bool {
        let state = self
            .state
            .lock()
            .expect("EventBus state lock poisoned in has_listeners");
        !state.is_closed
            && state
                .typed_channels
                .values()
                .any(TypedChannel::has_listeners)
    }

    /// Whether the event bus has been disposed.
    pub fn is_disposed(&self) -> bool {
        self.state
            .lock()
            .expect("EventBus state lock poisoned in is_disposed")
            .is_closed
    }

    /// Whether listeners can receive events of type `T`.
    pub fn has_listeners_for<T>(&self) -> bool
    where
        T: DrawEvent + ?Sized + 'static,
    {
        let queried_type = TypeId::of::<T>();
        let state = self
            .state
            .lock()
            .expect("EventBus state lock poisoned in has_listeners_for");

        if state.is_closed {
            return false;
        }

        state.typed_channels.values().any(|channel| {
            channel.has_listeners()
                && (channel.accepts_type(queried_type) || channel.is_subtype_of(queried_type))
        })
    }

    /// Emits an event.
    pub fn emit<E>(&self, event: E)
    where
        E: DrawEvent + 'static,
    {
        let _ = self.try_emit(event);
    }

    /// Emits an event and reports whether it was dispatched.
    pub fn try_emit<E>(&self, event: E) -> bool
    where
        E: DrawEvent + 'static,
    {
        self.try_emit_arc(Arc::new(event))
    }

    /// Builds and emits an event only when listeners can receive it.
    pub fn emit_lazy<T, F>(&self, event_factory: F) -> bool
    where
        T: DrawEvent + 'static,
        F: FnOnce() -> T,
    {
        if !self.has_listeners_for::<T>() {
            return false;
        }

        self.try_emit(event_factory())
    }

    /// Typed stream for a specific event type.
    pub fn stream_of<T>(&self) -> TypedEventStream<'_, T>
    where
        T: DrawEvent + 'static,
    {
        TypedEventStream {
            bus: self,
            _marker: PhantomData,
        }
    }

    /// Subscribes to a specific event type.
    pub fn on<T, F>(&self, handler: F) -> StreamSubscription
    where
        T: DrawEvent + 'static,
        F: Fn(&T) + Send + Sync + 'static,
    {
        self.stream_of::<T>().listen(handler)
    }

    /// Unsubscribes a previously registered listener.
    pub fn off(&self, subscription: StreamSubscription) -> bool {
        let Some(listener_id) = subscription.listener_id else {
            return false;
        };

        let mut state = self
            .state
            .lock()
            .expect("EventBus state lock poisoned in off");
        if state.is_closed {
            return false;
        }

        let Some(channel) = state.typed_channels.get_mut(&subscription.channel_type_id) else {
            return false;
        };

        let before = channel.listeners.len();
        channel.listeners.retain(|entry| entry.id != listener_id);
        before != channel.listeners.len()
    }

    /// Closes the event bus.
    ///
    /// Returns `true` when this call transitions the bus into disposed state.
    pub fn dispose(&self) -> bool {
        let mut state = self
            .state
            .lock()
            .expect("EventBus state lock poisoned in dispose");
        if state.is_closed {
            return false;
        }

        state.is_closed = true;
        state.typed_channels.clear();
        true
    }

    fn subscribe_erased(
        &self,
        channel_type_id: TypeId,
        handler: ErasedEventHandler,
    ) -> StreamSubscription {
        let mut state = self
            .state
            .lock()
            .expect("EventBus state lock poisoned in subscribe_erased");

        if state.is_closed {
            return StreamSubscription::inactive(channel_type_id);
        }

        let listener_id = state.next_listener_id;
        state.next_listener_id = state.next_listener_id.wrapping_add(1);

        let channel = state
            .typed_channels
            .entry(channel_type_id)
            .or_insert_with(|| TypedChannel::new(channel_type_id));
        channel.listeners.push(ListenerEntry {
            id: listener_id,
            handler,
        });

        StreamSubscription {
            channel_type_id,
            listener_id: Some(listener_id),
        }
    }

    fn try_emit_arc(&self, event: DrawEventRef) -> bool {
        let handlers = {
            let state = self
                .state
                .lock()
                .expect("EventBus state lock poisoned in try_emit_arc");

            if state.is_closed {
                return false;
            }

            state.collect_matching_handlers(event.as_ref())
        };

        if handlers.is_empty() {
            return false;
        }

        for handler in handlers {
            handler(event.as_ref());
        }

        true
    }
}

impl Default for EventBus {
    fn default() -> Self {
        Self::new()
    }
}

fn draw_event_type_id() -> TypeId {
    TypeId::of::<dyn DrawEvent>()
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    use super::{DrawEvent, EventBus};

    #[derive(Debug)]
    struct TestEventA;

    #[derive(Debug)]
    struct TestEventB;

    #[test]
    fn typed_and_base_listeners_receive_expected_events() {
        let bus = EventBus::new();
        let typed_calls = Arc::new(AtomicUsize::new(0));
        let all_calls = Arc::new(AtomicUsize::new(0));

        let typed_calls_for_listener = Arc::clone(&typed_calls);
        bus.on::<TestEventA, _>(move |_| {
            typed_calls_for_listener.fetch_add(1, Ordering::Relaxed);
        });

        let all_calls_for_listener = Arc::clone(&all_calls);
        bus.stream().listen(move |_| {
            all_calls_for_listener.fetch_add(1, Ordering::Relaxed);
        });

        bus.emit(TestEventA);
        bus.emit(TestEventB);

        assert_eq!(typed_calls.load(Ordering::Relaxed), 1);
        assert_eq!(all_calls.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn emit_lazy_avoids_factory_when_no_listeners() {
        let bus = EventBus::new();
        let factory_calls = Arc::new(AtomicUsize::new(0));
        let calls_for_factory = Arc::clone(&factory_calls);

        let emitted = bus.emit_lazy::<TestEventA, _>(move || {
            calls_for_factory.fetch_add(1, Ordering::Relaxed);
            TestEventA
        });

        assert!(!emitted);
        assert_eq!(factory_calls.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn cancel_removes_listener() {
        let bus = EventBus::new();
        let calls = Arc::new(AtomicUsize::new(0));
        let calls_for_listener = Arc::clone(&calls);

        let subscription = bus.on::<TestEventA, _>(move |_| {
            calls_for_listener.fetch_add(1, Ordering::Relaxed);
        });

        assert!(subscription.cancel(&bus));
        bus.emit(TestEventA);
        assert_eq!(calls.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn dispose_blocks_future_emits_and_subscriptions() {
        let bus = EventBus::new();
        assert!(bus.dispose());
        assert!(bus.is_disposed());

        let subscription = bus.on::<TestEventA, _>(move |_| {});
        assert!(!subscription.is_active());
        assert!(!bus.try_emit(TestEventA));
    }

    #[test]
    fn has_listeners_for_reflects_active_subscriptions() {
        let bus = EventBus::new();
        assert!(!bus.has_listeners_for::<TestEventA>());
        assert!(!bus.has_listeners_for::<dyn DrawEvent>());

        let subscription = bus.on::<TestEventA, _>(move |_| {});
        assert!(subscription.is_active());

        assert!(bus.has_listeners_for::<TestEventA>());
        assert!(bus.has_listeners_for::<dyn DrawEvent>());
    }
}
