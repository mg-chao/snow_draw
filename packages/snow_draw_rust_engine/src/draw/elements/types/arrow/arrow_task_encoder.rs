#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::elements::core::typed_element_render_task_encoder::{
    ElementState, RenderTaskList, TypedElementRenderTaskEncoder,
};
use crate::draw::types::edit_context::TextMetricsService;

use super::arrow_data::ArrowData;

/// Element-level render task for arrow payloads.
///
/// Mirrors Dart `ArrowRenderTask(element: ..., data: ..., localeTag: ...)`.
#[derive(Debug, Clone)]
pub struct ArrowRenderTask {
    pub element: ElementState,
    pub data: ArrowData,
    pub locale_tag: Option<String>,
}

impl ArrowRenderTask {
    /// Creates a new arrow render task snapshot.
    pub fn new(element: ElementState, data: ArrowData, locale_tag: Option<String>) -> Self {
        Self {
            element,
            data,
            locale_tag,
        }
    }
}

/// Encodes arrow elements into high-level render tasks.
///
/// Translation of Dart `ArrowTaskEncoder extends TypedElementRenderTaskEncoder<ArrowData>`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ArrowTaskEncoder;

impl ArrowTaskEncoder {
    /// Creates an arrow task encoder.
    pub const fn new() -> Self {
        Self
    }
}

impl TypedElementRenderTaskEncoder<ArrowData> for ArrowTaskEncoder {
    fn encode_typed_tasks(
        &self,
        element: &ElementState,
        data: &ArrowData,
        locale_tag: Option<&str>,
        _text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> RenderTaskList {
        vec![Box::new(ArrowRenderTask::new(
            element.clone(),
            data.clone(),
            locale_tag.map(str::to_owned),
        ))]
    }
}
