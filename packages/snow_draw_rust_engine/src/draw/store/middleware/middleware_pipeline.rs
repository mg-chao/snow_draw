#![allow(dead_code)]

use std::cmp::Ordering;
use std::error::Error;
use std::fmt;
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering as AtomicOrdering};
use std::sync::{Arc, Mutex};

use super::middleware_context::DispatchContext;

/// Boxed async value used by middleware callbacks.
pub type DispatchFuture<T> = Pin<Box<dyn Future<Output = T> + Send + 'static>>;

/// Result of one middleware invocation.
pub type MiddlewareInvocationResult = Result<DispatchContext, MiddlewareError>;

/// Callback that advances middleware execution to the next step.
pub type NextFunction = Arc<
    dyn Fn(DispatchContext) -> DispatchFuture<MiddlewareInvocationResult> + Send + Sync + 'static,
>;

/// Middleware contract for the dispatch pipeline.
pub trait Middleware: Send + Sync {
    /// Executes middleware logic for `context`.
    fn invoke(
        &self,
        context: DispatchContext,
        next: NextFunction,
    ) -> DispatchFuture<MiddlewareInvocationResult>;

    /// Priority used for middleware ordering (higher runs first).
    fn priority(&self) -> i32 {
        0
    }

    /// Human-readable middleware name for logs and debugging.
    fn name(&self) -> &str {
        std::any::type_name::<Self>()
    }
}

/// Error type for middleware execution failures.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MiddlewareError {
    NextCalledMoreThanOnce { middleware_name: String },
    Message(String),
}

impl MiddlewareError {
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

impl fmt::Display for MiddlewareError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NextCalledMoreThanOnce { middleware_name } => {
                write!(
                    f,
                    "Middleware \"{middleware_name}\" called next() more than once"
                )
            }
            Self::Message(message) => write!(f, "{message}"),
        }
    }
}

impl Error for MiddlewareError {}

/// Main middleware pipeline orchestrator.
///
/// Executes middlewares in sequence with basic error handling.
#[derive(Clone, Default)]
pub struct MiddlewarePipeline {
    middlewares: Arc<[Arc<dyn Middleware>]>,
}

impl MiddlewarePipeline {
    /// Creates a pipeline from the provided middlewares.
    pub fn new(middlewares: Vec<Arc<dyn Middleware>>) -> Self {
        Self {
            middlewares: middlewares.into(),
        }
    }

    /// Execute the pipeline with the given initial context.
    ///
    /// Returns the final context after all middlewares have executed.
    pub fn execute(&self, initial_context: DispatchContext) -> DispatchFuture<DispatchContext> {
        if self.middlewares.is_empty() || initial_context.is_terminal() {
            return Box::pin(async move { initial_context });
        }

        self.clone().execute_from_index(initial_context, 0)
    }

    fn execute_from_index(
        self,
        context: DispatchContext,
        index: usize,
    ) -> DispatchFuture<DispatchContext> {
        if index >= self.middlewares.len() || context.is_terminal() {
            return Box::pin(async move { context });
        }

        let middleware = Arc::clone(&self.middlewares[index]);
        self.invoke_middleware(context, index, middleware)
    }

    fn invoke_middleware(
        self,
        context: DispatchContext,
        index: usize,
        middleware: Arc<dyn Middleware>,
    ) -> DispatchFuture<DispatchContext> {
        let next_called = Arc::new(AtomicBool::new(false));
        let downstream_context = Arc::new(Mutex::new(None::<DispatchContext>));
        let middleware_name = middleware.name().to_owned();

        let pipeline_for_next = self.clone();
        let next_called_for_next = Arc::clone(&next_called);
        let downstream_context_for_next = Arc::clone(&downstream_context);
        let middleware_name_for_next = middleware_name.clone();

        let guarded_next: NextFunction = Arc::new(move |next_context: DispatchContext| {
            let pipeline = pipeline_for_next.clone();
            let next_called = Arc::clone(&next_called_for_next);
            let downstream_context = Arc::clone(&downstream_context_for_next);
            let middleware_name = middleware_name_for_next.clone();

            Box::pin(async move {
                if next_called.swap(true, AtomicOrdering::SeqCst) {
                    return Err(MiddlewareError::next_called_more_than_once(middleware_name));
                }

                let resolved_context = pipeline.execute_from_index(next_context, index + 1).await;
                let mut downstream_guard = downstream_context
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner());
                *downstream_guard = Some(resolved_context.clone());
                Ok(resolved_context)
            })
        });

        Box::pin(async move {
            let fallback_context = context.clone();

            match middleware.invoke(context, guarded_next).await {
                Ok(final_context) => final_context,
                Err(error) => {
                    let base_context = downstream_context
                        .lock()
                        .unwrap_or_else(|poisoned| poisoned.into_inner())
                        .clone()
                        .unwrap_or(fallback_context);
                    base_context.with_error(error, "", Some(middleware_name))
                }
            }
        })
    }

    /// Create a new pipeline with an additional middleware.
    pub fn add_middleware(&self, middleware: Arc<dyn Middleware>) -> Self {
        let mut next = self.middlewares.iter().cloned().collect::<Vec<_>>();
        next.push(middleware);
        Self::new(next)
    }

    /// Create a new pipeline with a middleware prepended.
    pub fn prepend_middleware(&self, middleware: Arc<dyn Middleware>) -> Self {
        let mut next = Vec::with_capacity(self.middlewares.len() + 1);
        next.push(middleware);
        next.extend(self.middlewares.iter().cloned());
        Self::new(next)
    }

    /// Create a pipeline with middlewares sorted by priority.
    ///
    /// Returns this instance when middlewares are already sorted.
    pub fn sort_by_priority(&self) -> Self {
        if self.is_sorted_by_priority() {
            return self.clone();
        }

        let mut indexed_middlewares = self
            .middlewares
            .iter()
            .cloned()
            .enumerate()
            .collect::<Vec<(usize, Arc<dyn Middleware>)>>();

        indexed_middlewares.sort_by(|left, right| {
            let by_priority = right.1.priority().cmp(&left.1.priority());
            if by_priority != Ordering::Equal {
                return by_priority;
            }
            left.0.cmp(&right.0)
        });

        let sorted = indexed_middlewares
            .into_iter()
            .map(|(_, middleware)| middleware)
            .collect::<Vec<_>>();

        Self::new(sorted)
    }

    fn is_sorted_by_priority(&self) -> bool {
        if self.middlewares.len() < 2 {
            return true;
        }

        let mut previous_priority = self.middlewares[0].priority();
        for middleware in self.middlewares.iter().skip(1) {
            let current_priority = middleware.priority();
            if previous_priority < current_priority {
                return false;
            }
            previous_priority = current_priority;
        }

        true
    }

    /// Returns the number of middlewares.
    pub fn len(&self) -> usize {
        self.middlewares.len()
    }

    /// Returns true when no middleware is configured.
    pub fn is_empty(&self) -> bool {
        self.middlewares.is_empty()
    }

    /// Returns true when middleware entries are present.
    pub fn is_not_empty(&self) -> bool {
        !self.is_empty()
    }

    /// Borrow the middleware list.
    pub fn middlewares(&self) -> &[Arc<dyn Middleware>] {
        self.middlewares.as_ref()
    }
}
