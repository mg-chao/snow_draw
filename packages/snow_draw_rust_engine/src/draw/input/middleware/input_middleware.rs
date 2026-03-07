#![allow(dead_code)]

use std::any::Any;
use std::collections::BTreeMap;
use std::error::Error;
use std::fmt;
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering as AtomicOrdering};
use std::sync::Arc;

use crate::draw::models::draw_state::DrawState;
use crate::draw::services::log::log_service::{LogData, LogService, ModuleLogger};

/// Erased input event payload used by middleware.
///
/// The concrete input-event hierarchy is translated in `input_event.rs`.
/// Until then, middleware works with a shared dynamic event value.
pub type InputEvent = Arc<dyn Any + Send + Sync + 'static>;

/// Boxed async result returned by middleware.
pub type InputMiddlewareFuture = Pin<Box<dyn Future<Output = InputMiddlewareResult> + 'static>>;

/// Boxed async result returned by the pipeline execute API.
pub type InputExecuteFuture = Pin<Box<dyn Future<Output = Option<InputEvent>> + 'static>>;

/// Result type for middleware execution.
pub type InputMiddlewareResult = Result<Option<InputEvent>, InputMiddlewareError>;

/// Callback type for invoking the next middleware in the chain.
pub type NextMiddleware = Arc<dyn Fn(InputEvent) -> InputMiddlewareFuture + 'static>;

/// Stored data payload inside [MiddlewareContext].
pub type MiddlewareDataValue = Arc<dyn Any + Send + Sync + 'static>;

/// Data map passed between middlewares.
pub type MiddlewareDataMap = BTreeMap<String, MiddlewareDataValue>;

/// Errors produced by the input middleware pipeline.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum InputMiddlewareError {
    NextCalledMoreThanOnce { middleware_name: String },
    Message(String),
}

impl InputMiddlewareError {
    /// Creates a generic middleware error with message text.
    pub fn message(message: impl Into<String>) -> Self {
        Self::Message(message.into())
    }

    fn next_called_more_than_once(middleware_name: impl Into<String>) -> Self {
        Self::NextCalledMoreThanOnce {
            middleware_name: middleware_name.into(),
        }
    }
}

impl fmt::Display for InputMiddlewareError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NextCalledMoreThanOnce { middleware_name } => {
                write!(
                    f,
                    "Input middleware \"{middleware_name}\" called next() more than once"
                )
            }
            Self::Message(message) => write!(f, "{message}"),
        }
    }
}

impl Error for InputMiddlewareError {}

/// Middleware context.
///
/// Holds current draw-state and ad-hoc middleware-shared payloads.
#[derive(Clone)]
pub struct MiddlewareContext {
    /// Current state.
    pub state: DrawState,
    /// Custom middleware data payloads.
    pub data: MiddlewareDataMap,
    /// Optional module logger to use for middleware failures.
    pub log: Option<ModuleLogger>,
}

impl MiddlewareContext {
    /// Creates a middleware context.
    pub fn new(
        state: DrawState,
        data: Option<MiddlewareDataMap>,
        log: Option<ModuleLogger>,
    ) -> Self {
        Self {
            state,
            data: data.unwrap_or_default(),
            log,
        }
    }

    /// Returns a copy with one key/value added to `data`.
    pub fn set_data<T>(&self, key: impl Into<String>, value: T) -> Self
    where
        T: Any + Send + Sync + 'static,
    {
        let mut next_data = self.data.clone();
        next_data.insert(key.into(), Arc::new(value));
        Self {
            state: self.state.clone(),
            data: next_data,
            log: self.log.clone(),
        }
    }

    /// Returns typed data by key.
    pub fn get_data<T>(&self, key: &str) -> Option<&T>
    where
        T: Any + Send + Sync + 'static,
    {
        self.data.get(key)?.as_ref().downcast_ref::<T>()
    }

    /// Returns true when a value exists for `key`.
    pub fn has_data(&self, key: &str) -> bool {
        self.data.contains_key(key)
    }

    /// Returns a shallow clone with optional field replacements.
    ///
    /// `log` follows Dart's `copyWith` behavior: when `None`, the current logger
    /// is retained.
    pub fn copy_with(
        &self,
        state: Option<DrawState>,
        data: Option<MiddlewareDataMap>,
        log: Option<ModuleLogger>,
    ) -> Self {
        Self {
            state: state.unwrap_or_else(|| self.state.clone()),
            data: data.unwrap_or_else(|| self.data.clone()),
            log: log.or_else(|| self.log.clone()),
        }
    }
}

impl Default for MiddlewareContext {
    fn default() -> Self {
        Self::new(DrawState::default(), None, None)
    }
}

impl fmt::Debug for MiddlewareContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let keys = self.data.keys().cloned().collect::<Vec<_>>();
        f.debug_struct("MiddlewareContext")
            .field("state", &self.state)
            .field("data_keys", &keys)
            .field("has_log", &self.log.is_some())
            .finish()
    }
}

/// Input middleware contract.
pub trait InputMiddleware: Send + Sync {
    /// Middleware name used by debugging and logging.
    fn name(&self) -> &str;

    /// Processes an event and optionally forwards to the next middleware.
    fn process(
        &self,
        event: InputEvent,
        context: MiddlewareContext,
        next: NextMiddleware,
    ) -> InputMiddlewareFuture;
}

/// Base container that stores only middleware `name`.
///
/// Concrete middleware implementations can embed this struct.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct InputMiddlewareBase {
    name: String,
}

impl InputMiddlewareBase {
    /// Creates base middleware metadata with a fixed name.
    pub fn new(name: impl Into<String>) -> Self {
        Self { name: name.into() }
    }

    /// Returns middleware name.
    pub fn name(&self) -> &str {
        &self.name
    }
}

/// Ordered middleware chain for input-event processing.
#[derive(Clone)]
pub struct InputPipeline {
    middlewares: Arc<[Arc<dyn InputMiddleware>]>,
}

impl Default for InputPipeline {
    fn default() -> Self {
        Self::new(Vec::new())
    }
}

impl InputPipeline {
    /// Creates a pipeline with a fixed middleware order.
    pub fn new(middlewares: Vec<Arc<dyn InputMiddleware>>) -> Self {
        Self {
            middlewares: middlewares.into(),
        }
    }

    /// Executes the middleware chain and returns the transformed event.
    ///
    /// `None` means one middleware intercepted the event or a middleware failed.
    pub fn execute(&self, event: InputEvent, context: MiddlewareContext) -> InputExecuteFuture {
        if self.middlewares.is_empty() {
            return Box::pin(async move { Some(event) });
        }

        self.clone().execute_at_index(event, context, 0)
    }

    /// Returns a copy with middleware appended.
    pub fn add_middleware(&self, middleware: Arc<dyn InputMiddleware>) -> Self {
        let mut next = self.middlewares.iter().cloned().collect::<Vec<_>>();
        next.push(middleware);
        Self::new(next)
    }

    /// Returns a copy with middleware prepended.
    pub fn prepend_middleware(&self, middleware: Arc<dyn InputMiddleware>) -> Self {
        let mut next = Vec::with_capacity(self.middlewares.len() + 1);
        next.push(middleware);
        next.extend(self.middlewares.iter().cloned());
        Self::new(next)
    }

    /// Returns a copy without middleware entries whose name equals `name`.
    pub fn remove_middleware(&self, name: &str) -> Self {
        let next = self
            .middlewares
            .iter()
            .filter(|middleware| middleware.name() != name)
            .cloned()
            .collect::<Vec<_>>();
        Self::new(next)
    }

    /// Creates an empty pipeline.
    pub fn empty() -> Self {
        Self::default()
    }

    /// Returns number of configured middleware entries.
    pub fn len(&self) -> usize {
        self.middlewares.len()
    }

    /// Returns `true` when no middleware is configured.
    pub fn is_empty(&self) -> bool {
        self.middlewares.is_empty()
    }

    /// Borrows configured middleware entries.
    pub fn middlewares(&self) -> &[Arc<dyn InputMiddleware>] {
        self.middlewares.as_ref()
    }

    fn execute_at_index(
        self,
        event: InputEvent,
        context: MiddlewareContext,
        middleware_index: usize,
    ) -> InputExecuteFuture {
        if middleware_index >= self.middlewares.len() {
            return Box::pin(async move { Some(event) });
        }

        let middleware = Arc::clone(&self.middlewares[middleware_index]);
        let middleware_name = middleware.name().to_owned();
        let event_type = input_event_type_name(&event).to_owned();
        let next_called = Arc::new(AtomicBool::new(false));

        let pipeline_for_next = self.clone();
        let context_for_next = context.clone();
        let next_called_for_next = Arc::clone(&next_called);
        let middleware_name_for_next = middleware_name.clone();

        let guarded_next: NextMiddleware = Arc::new(move |next_event: InputEvent| {
            let pipeline = pipeline_for_next.clone();
            let context = context_for_next.clone();
            let next_called = Arc::clone(&next_called_for_next);
            let middleware_name = middleware_name_for_next.clone();

            Box::pin(async move {
                if next_called.swap(true, AtomicOrdering::SeqCst) {
                    return Err(InputMiddlewareError::next_called_more_than_once(
                        middleware_name,
                    ));
                }

                Ok(pipeline
                    .execute_at_index(next_event, context, middleware_index + 1)
                    .await)
            })
        });

        Box::pin(async move {
            match middleware
                .process(event, context.clone(), guarded_next)
                .await
            {
                Ok(processed_event) => processed_event,
                Err(error) => {
                    Self::log_middleware_failure(
                        &context,
                        middleware.as_ref(),
                        event_type.as_str(),
                        &error,
                    );
                    None
                }
            }
        })
    }

    fn log_middleware_failure(
        context: &MiddlewareContext,
        middleware: &dyn InputMiddleware,
        event_type: &str,
        error: &InputMiddlewareError,
    ) {
        let logger = context
            .log
            .clone()
            .unwrap_or_else(|| LogService::fallback().input());

        let mut data = LogData::new();
        data.insert("middleware".to_owned(), middleware.name().to_owned());
        data.insert("event".to_owned(), event_type.to_owned());

        let error_text = error.to_string();
        logger.error(
            "Input middleware failed",
            Some(error_text.as_str()),
            None,
            Some(&data),
        );
    }
}

fn input_event_type_name(event: &InputEvent) -> &'static str {
    std::any::type_name_of_val(event.as_ref())
}
