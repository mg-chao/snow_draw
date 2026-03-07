#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::actions::draw_actions::DrawAction;
use crate::draw::models::draw_state::DrawState;
use crate::draw::store::middleware::middleware_context::DispatchContext;
use crate::draw::store::middleware::middleware_pipeline::{
    DispatchFuture, Middleware, MiddlewareInvocationResult, NextFunction,
};

fn short_action_name(action: &dyn DrawAction) -> String {
    action
        .action_name()
        .rsplit("::")
        .next()
        .unwrap_or(action.action_name())
        .to_owned()
}

/// Action interceptor callback contract.
///
/// Returns `true` to allow action processing to continue and `false` to stop
/// dispatch.
pub trait ActionInterceptor: Send + Sync {
    fn call(&self, state: &DrawState, action: &dyn DrawAction) -> bool;

    /// Human-readable interceptor identifier used for stop diagnostics.
    fn name(&self) -> &'static str {
        std::any::type_name::<Self>()
    }
}

impl<F> ActionInterceptor for F
where
    F: Fn(&DrawState, &dyn DrawAction) -> bool + Send + Sync + 'static,
{
    fn call(&self, state: &DrawState, action: &dyn DrawAction) -> bool {
        self(state, action)
    }
}

/// Interception middleware that allows blocking actions before processing.
///
/// Interceptors inspect the action and current state and decide whether the
/// action should continue through the middleware chain.
#[derive(Default, Clone)]
pub struct InterceptionMiddleware {
    interceptors: Vec<Arc<dyn ActionInterceptor>>,
}

impl InterceptionMiddleware {
    /// High priority value so interception runs early in the pipeline.
    pub const PRIORITY: i32 = 900;

    /// Human-readable middleware name.
    pub const NAME: &'static str = "Interception";

    /// Creates interception middleware with explicit interceptor list.
    pub fn new(interceptors: Vec<Arc<dyn ActionInterceptor>>) -> Self {
        Self { interceptors }
    }

    /// Returns the configured interceptors.
    pub fn interceptors(&self) -> &[Arc<dyn ActionInterceptor>] {
        &self.interceptors
    }

    /// Middleware display name.
    pub const fn name(&self) -> &'static str {
        Self::NAME
    }

    /// Middleware priority (higher runs earlier).
    pub const fn priority(&self) -> i32 {
        Self::PRIORITY
    }

    /// Executes interception checks and blocks dispatch when needed.
    pub fn invoke(
        &self,
        context: DispatchContext,
        next: NextFunction,
    ) -> DispatchFuture<MiddlewareInvocationResult> {
        if self.interceptors.is_empty() {
            return Box::pin(async move { next(context).await });
        }

        for interceptor in &self.interceptors {
            if !interceptor.call(&context.current_state, context.action.as_ref()) {
                let blocked_context =
                    context.with_stop(format!("Action blocked by {}", interceptor.name()));
                return Box::pin(async move { Ok(blocked_context) });
            }
        }

        Box::pin(async move { next(context).await })
    }
}

impl Middleware for InterceptionMiddleware {
    fn invoke(
        &self,
        context: DispatchContext,
        next: NextFunction,
    ) -> DispatchFuture<MiddlewareInvocationResult> {
        let _ = short_action_name(context.action.as_ref());
        InterceptionMiddleware::invoke(self, context, next)
    }

    fn priority(&self) -> i32 {
        InterceptionMiddleware::priority(self)
    }

    fn name(&self) -> &str {
        InterceptionMiddleware::name(self)
    }
}
