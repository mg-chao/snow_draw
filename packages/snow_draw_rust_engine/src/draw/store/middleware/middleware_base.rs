#![allow(dead_code)]

/// Backward-compatible re-exports for middleware contracts.
///
/// The canonical contracts live in `middleware_pipeline.rs`; this module keeps
/// older imports compiling while routing everything through the real pipeline
/// types.
pub use super::middleware_context::DispatchContext;
pub use super::middleware_pipeline::{
    DispatchFuture, Middleware, MiddlewareError, MiddlewareInvocationResult, NextFunction,
};
