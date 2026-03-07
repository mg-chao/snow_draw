#![allow(dead_code)]

use std::sync::Arc;

use super::middleware_pipeline::{Middleware, MiddlewarePipeline};
use super::middlewares::history_middleware::HistoryMiddleware;
use super::middlewares::interception_middleware::{ActionInterceptor, InterceptionMiddleware};
use super::middlewares::reduction_middleware::ReductionMiddleware;
use super::middlewares::validation_middleware::ValidationMiddleware;

/// Factory for creating middleware pipelines.
#[derive(Debug, Default, Clone, Copy)]
pub struct MiddlewarePipelineFactory;

impl MiddlewarePipelineFactory {
    /// Creates a factory instance.
    pub const fn new() -> Self {
        Self
    }

    /// Creates the standard middleware pipeline.
    ///
    /// Execution order by priority:
    /// 1. `ValidationMiddleware` (1000)
    /// 2. `InterceptionMiddleware` (900, optional)
    /// 3. `ReductionMiddleware` (500)
    /// 4. `HistoryMiddleware` (400)
    pub fn create_default(
        &self,
        interceptors: Vec<Arc<dyn ActionInterceptor>>,
    ) -> MiddlewarePipeline {
        self.create_custom(self.default_middlewares(interceptors))
    }

    /// Creates a pipeline that extends the default middleware chain.
    pub fn extend_default(
        &self,
        additional_middlewares: Vec<Arc<dyn Middleware>>,
        interceptors: Vec<Arc<dyn ActionInterceptor>>,
    ) -> MiddlewarePipeline {
        let mut middlewares = self.default_middlewares(interceptors);
        middlewares.extend(additional_middlewares);
        self.create_custom(middlewares)
    }

    /// Creates a minimal pipeline with only reduction middleware.
    pub fn create_minimal(&self) -> MiddlewarePipeline {
        self.create_custom(vec![Arc::new(ReductionMiddleware)])
    }

    /// Creates a custom pipeline and sorts middleware by priority.
    pub fn create_custom(&self, middlewares: Vec<Arc<dyn Middleware>>) -> MiddlewarePipeline {
        MiddlewarePipeline::new(middlewares).sort_by_priority()
    }

    fn default_middlewares(
        &self,
        interceptors: Vec<Arc<dyn ActionInterceptor>>,
    ) -> Vec<Arc<dyn Middleware>> {
        let mut middlewares: Vec<Arc<dyn Middleware>> = Vec::with_capacity(4);
        middlewares.push(Arc::new(ValidationMiddleware));

        if !interceptors.is_empty() {
            middlewares.push(Arc::new(InterceptionMiddleware::new(interceptors)));
        }

        middlewares.push(Arc::new(ReductionMiddleware));
        middlewares.push(Arc::new(HistoryMiddleware));
        middlewares
    }
}

/// Shared stateless factory instance, mirroring the Dart singleton constant.
pub const MIDDLEWARE_PIPELINE_FACTORY: MiddlewarePipelineFactory = MiddlewarePipelineFactory;
