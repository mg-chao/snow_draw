#![allow(dead_code)]

use crate::draw::reducers::interaction::interaction_state_machine::{
    interaction_state_machine, InteractionStateMachine,
};
use crate::draw::store::middleware::middleware_context::DispatchContext;
use crate::draw::store::middleware::middleware_pipeline::{
    DispatchFuture, Middleware, MiddlewareInvocationResult, NextFunction,
};

/// Reduction middleware that executes the interaction state machine.
///
/// This middleware transforms state based on the incoming action and forwards
/// the updated context to the next middleware.
#[derive(Debug, Default, Clone, Copy)]
pub struct ReductionMiddleware;

impl ReductionMiddleware {
    /// High-level reducer name used by diagnostics.
    pub const NAME: &'static str = "Reduction";

    /// Pipeline priority. Higher values execute earlier.
    pub const PRIORITY: i32 = 500;

    /// Creates a stateless reduction middleware instance.
    pub const fn new() -> Self {
        Self
    }

    /// Executes state reduction and forwards updated context.
    pub fn invoke_runtime(
        &self,
        context: DispatchContext,
        next: NextFunction,
    ) -> DispatchFuture<MiddlewareInvocationResult> {
        let transition = Self::state_machine().reduce(
            context.current_state.clone(),
            &context.action,
            &context.draw_context,
            context.edit_session_service.as_ref(),
            &context.session_id_generator,
        );

        Box::pin(async move { next(context.with_current_state(transition.next_state)).await })
    }

    fn state_machine() -> InteractionStateMachine {
        interaction_state_machine()
    }
}

impl Middleware for ReductionMiddleware {
    fn invoke(
        &self,
        context: DispatchContext,
        next: NextFunction,
    ) -> DispatchFuture<MiddlewareInvocationResult> {
        self.invoke_runtime(context, next)
    }

    fn priority(&self) -> i32 {
        Self::PRIORITY
    }

    fn name(&self) -> &str {
        Self::NAME
    }
}

/// Shared stateless middleware constant, mirroring Dart `const` behavior.
pub const REDUCTION_MIDDLEWARE: ReductionMiddleware = ReductionMiddleware;
