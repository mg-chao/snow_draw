#![allow(dead_code)]

use std::collections::{BTreeMap, HashMap, HashSet};
use std::fmt;
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde_json::Value;

use crate::draw::models::draw_state::DrawState;
use crate::draw::services::log::log_service::{LogData, LogService, ModuleLogger};
use crate::draw::types::draw_point::DrawPoint;

const SLOW_EVENT_THRESHOLD: Duration = Duration::from_millis(16);

/// Event kind used by input middleware.
///
/// This mirrors the Dart event classes (`PointerDownInputEvent`,
/// `PointerMoveInputEvent`, and so on) with an idiomatic Rust enum.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum InputEventKind {
    PointerDown,
    PointerMove,
    PointerHover,
    PointerUp,
    PointerCancel,
    Unknown,
}

impl InputEventKind {
    fn as_str(self) -> &'static str {
        match self {
            Self::PointerDown => "PointerDownInputEvent",
            Self::PointerMove => "PointerMoveInputEvent",
            Self::PointerHover => "PointerHoverInputEvent",
            Self::PointerUp => "PointerUpInputEvent",
            Self::PointerCancel => "PointerCancelInputEvent",
            Self::Unknown => "InputEvent",
        }
    }
}

/// Keyboard modifier state carried with input events.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct KeyModifiers {
    pub shift: bool,
    pub control: bool,
    pub alt: bool,
}

impl fmt::Display for KeyModifiers {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "KeyModifiers(shift: {}, ctrl: {}, alt: {})",
            self.shift, self.control, self.alt
        )
    }
}

/// Base input event routed through middleware.
#[derive(Clone, Debug, PartialEq)]
pub struct InputEvent {
    pub kind: InputEventKind,
    pub position: DrawPoint,
    pub modifiers: KeyModifiers,
    pub pressure: f64,
}

impl InputEvent {
    pub const fn new(kind: InputEventKind, position: DrawPoint, modifiers: KeyModifiers) -> Self {
        Self {
            kind,
            position,
            modifiers,
            pressure: 0.0,
        }
    }

    pub const fn with_pressure(
        kind: InputEventKind,
        position: DrawPoint,
        modifiers: KeyModifiers,
        pressure: f64,
    ) -> Self {
        Self {
            kind,
            position,
            modifiers,
            pressure,
        }
    }

    pub fn event_type(&self) -> &'static str {
        self.kind.as_str()
    }
}

/// Middleware context.
///
/// Carries draw state, optional logger, and a key/value bag for middleware
/// coordination.
#[derive(Clone, Debug)]
pub struct MiddlewareContext {
    pub state: DrawState,
    pub data: BTreeMap<String, Value>,
    pub log: Option<ModuleLogger>,
}

impl MiddlewareContext {
    pub fn new(state: DrawState, log: Option<ModuleLogger>) -> Self {
        Self {
            state,
            data: BTreeMap::new(),
            log,
        }
    }

    pub fn set_data(&self, key: impl Into<String>, value: impl Into<Value>) -> MiddlewareContext {
        let mut next_data = self.data.clone();
        next_data.insert(key.into(), value.into());

        Self {
            state: self.state.clone(),
            data: next_data,
            log: self.log.clone(),
        }
    }

    pub fn get_data(&self, key: &str) -> Option<&Value> {
        self.data.get(key)
    }

    pub fn has_data(&self, key: &str) -> bool {
        self.data.contains_key(key)
    }

    pub fn copy_with(
        &self,
        state: Option<DrawState>,
        data: Option<BTreeMap<String, Value>>,
        log: Option<Option<ModuleLogger>>,
    ) -> MiddlewareContext {
        Self {
            state: state.unwrap_or_else(|| self.state.clone()),
            data: data.unwrap_or_else(|| self.data.clone()),
            log: log.unwrap_or_else(|| self.log.clone()),
        }
    }
}

/// Boxed async middleware result.
pub type MiddlewareFuture = Pin<Box<dyn Future<Output = Option<InputEvent>> + Send + 'static>>;

/// Callback to continue middleware execution.
pub type NextMiddleware = Arc<dyn Fn(InputEvent) -> MiddlewareFuture + Send + Sync + 'static>;

/// Middleware contract for input-event processing.
pub trait InputMiddleware: Send + Sync {
    fn name(&self) -> &str;

    fn process(
        &self,
        event: InputEvent,
        context: Arc<MiddlewareContext>,
        next: NextMiddleware,
    ) -> MiddlewareFuture;
}

fn logger_for(context: &MiddlewareContext) -> ModuleLogger {
    context
        .log
        .clone()
        .unwrap_or_else(|| LogService::fallback().input())
}

fn log_data(pairs: [(&str, String); 1]) -> LogData {
    let mut data = LogData::new();
    for (key, value) in pairs {
        data.insert(key.to_owned(), value);
    }
    data
}

/// Logging middleware.
///
/// Records all input events for debugging.
#[derive(Clone, Debug)]
pub struct LoggingMiddleware {
    pub verbose: bool,
}

impl LoggingMiddleware {
    pub const fn new(verbose: bool) -> Self {
        Self { verbose }
    }
}

impl Default for LoggingMiddleware {
    fn default() -> Self {
        Self { verbose: false }
    }
}

impl InputMiddleware for LoggingMiddleware {
    fn name(&self) -> &str {
        "Logging"
    }

    fn process(
        &self,
        event: InputEvent,
        context: Arc<MiddlewareContext>,
        next: NextMiddleware,
    ) -> MiddlewareFuture {
        let event_type = event.event_type().to_owned();
        let log = logger_for(context.as_ref());
        let verbose = self.verbose;
        let state = context.state.clone();

        if verbose {
            let mut data = LogData::new();
            data.insert("type".to_owned(), event_type.clone());
            data.insert("position".to_owned(), event.position.to_string());
            data.insert("modifiers".to_owned(), event.modifiers.to_string());
            data.insert(
                "isEditing".to_owned(),
                state.application.is_editing().to_string(),
            );
            data.insert(
                "isCreating".to_owned(),
                state.application.is_creating().to_string(),
            );
            data.insert(
                "hasSelection".to_owned(),
                state.domain.selection.has_selection().to_string(),
            );
            log.trace("Input event", Some(&data));
        } else {
            let data = log_data([("type", event_type.clone())]);
            log.debug("Input event", Some(&data));
        }

        Box::pin(async move {
            let result = next(event).await;
            if verbose && result.is_some() {
                let data = log_data([("type", event_type)]);
                log.debug("Input event processed", Some(&data));
            }
            result
        })
    }
}

/// Event filter middleware.
///
/// Filters events based on a predicate.
#[derive(Clone)]
pub struct EventFilterMiddleware {
    predicate: Arc<dyn Fn(&InputEvent, &MiddlewareContext) -> bool + Send + Sync + 'static>,
}

impl fmt::Debug for EventFilterMiddleware {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("EventFilterMiddleware")
            .finish_non_exhaustive()
    }
}

impl EventFilterMiddleware {
    pub fn new<F>(predicate: F) -> Self
    where
        F: Fn(&InputEvent, &MiddlewareContext) -> bool + Send + Sync + 'static,
    {
        Self {
            predicate: Arc::new(predicate),
        }
    }
}

impl InputMiddleware for EventFilterMiddleware {
    fn name(&self) -> &str {
        "EventFilter"
    }

    fn process(
        &self,
        event: InputEvent,
        context: Arc<MiddlewareContext>,
        next: NextMiddleware,
    ) -> MiddlewareFuture {
        if !(self.predicate)(&event, context.as_ref()) {
            return Box::pin(async { None });
        }

        next(event)
    }
}

/// Throttle middleware.
///
/// Limits event handling frequency (primarily for pointer move).
#[derive(Debug)]
pub struct ThrottleMiddleware {
    pub duration: Duration,
    last_process_times: Mutex<HashMap<InputEventKind, Instant>>,
    throttled_event_types: HashSet<InputEventKind>,
}

impl ThrottleMiddleware {
    pub fn new(duration: Duration, throttled_event_types: Option<HashSet<InputEventKind>>) -> Self {
        let throttled = throttled_event_types.unwrap_or_else(|| {
            let mut defaults = HashSet::new();
            defaults.insert(InputEventKind::PointerMove);
            defaults
        });

        Self {
            duration,
            last_process_times: Mutex::new(HashMap::new()),
            throttled_event_types: throttled,
        }
    }
}

impl InputMiddleware for ThrottleMiddleware {
    fn name(&self) -> &str {
        "Throttle"
    }

    fn process(
        &self,
        event: InputEvent,
        _context: Arc<MiddlewareContext>,
        next: NextMiddleware,
    ) -> MiddlewareFuture {
        if !self.throttled_event_types.contains(&event.kind) {
            return next(event);
        }

        let now = Instant::now();
        {
            let mut last_process_times = self
                .last_process_times
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());

            if let Some(last_time) = last_process_times.get(&event.kind) {
                if now.duration_since(*last_time) < self.duration {
                    return Box::pin(async { None });
                }
            }

            last_process_times.insert(event.kind, now);
        }

        next(event)
    }
}

/// Performance middleware.
///
/// Measures event processing time.
#[derive(Clone)]
pub struct PerformanceMiddleware {
    on_measure: Option<Arc<dyn Fn(&str, Duration) + Send + Sync + 'static>>,
}

impl fmt::Debug for PerformanceMiddleware {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PerformanceMiddleware")
            .field("has_on_measure", &self.on_measure.is_some())
            .finish()
    }
}

impl PerformanceMiddleware {
    pub fn new(on_measure: Option<Arc<dyn Fn(&str, Duration) + Send + Sync + 'static>>) -> Self {
        Self { on_measure }
    }
}

impl Default for PerformanceMiddleware {
    fn default() -> Self {
        Self { on_measure: None }
    }
}

impl InputMiddleware for PerformanceMiddleware {
    fn name(&self) -> &str {
        "Performance"
    }

    fn process(
        &self,
        event: InputEvent,
        context: Arc<MiddlewareContext>,
        next: NextMiddleware,
    ) -> MiddlewareFuture {
        let event_type = event.event_type().to_owned();
        let on_measure = self.on_measure.clone();
        let log = logger_for(context.as_ref());

        Box::pin(async move {
            let started = Instant::now();
            let result = next(event).await;
            let elapsed = started.elapsed();

            if let Some(on_measure) = on_measure {
                on_measure(&event_type, elapsed);
            } else if elapsed > SLOW_EVENT_THRESHOLD {
                let mut data = LogData::new();
                data.insert("type".to_owned(), event_type);
                data.insert("duration_ms".to_owned(), elapsed.as_millis().to_string());
                log.warning("Slow input event", Some(&data));
            }

            result
        })
    }
}

/// Event validation middleware.
///
/// Validates event data.
#[derive(Clone, Copy, Debug, Default)]
pub struct ValidationMiddleware;

impl ValidationMiddleware {
    pub const fn new() -> Self {
        Self
    }
}

impl InputMiddleware for ValidationMiddleware {
    fn name(&self) -> &str {
        "Validation"
    }

    fn process(
        &self,
        event: InputEvent,
        context: Arc<MiddlewareContext>,
        next: NextMiddleware,
    ) -> MiddlewareFuture {
        let position = event.position;
        if !position.x.is_finite() || !position.y.is_finite() {
            let log = logger_for(context.as_ref());
            let mut data = LogData::new();
            data.insert("position".to_owned(), position.to_string());
            log.warning("Invalid input position", Some(&data));
            return Box::pin(async { None });
        }

        next(event)
    }
}
