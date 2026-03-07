#![allow(dead_code)]

use std::sync::Arc;

use super::highlight_data::HighlightData;
use crate::draw::elements::core::typed_element_render_task_encoder::{
    ElementState, RenderTaskList, TypedElementRenderTaskEncoder,
};
use crate::draw::types::edit_context::TextMetricsService;

/// Element-level render task for highlight payloads.
///
/// Mirrors Dart `HighlightRenderTask(element: ..., data: ..., localeTag: ...)`.
#[derive(Debug, Clone)]
pub struct HighlightRenderTask {
    pub element: ElementState,
    pub data: HighlightData,
    pub locale_tag: Option<String>,
}

impl HighlightRenderTask {
    /// Creates a new highlight render task snapshot.
    pub fn new(element: ElementState, data: HighlightData, locale_tag: Option<String>) -> Self {
        Self {
            element,
            data,
            locale_tag,
        }
    }
}

/// Encodes highlight elements into high-level render tasks.
///
/// Translation of Dart
/// `HighlightTaskEncoder extends TypedElementRenderTaskEncoder<HighlightData>`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct HighlightTaskEncoder;

impl HighlightTaskEncoder {
    /// Creates a highlight task encoder.
    pub const fn new() -> Self {
        Self
    }
}

impl TypedElementRenderTaskEncoder<HighlightData> for HighlightTaskEncoder {
    fn encode_typed_tasks(
        &self,
        element: &ElementState,
        data: &HighlightData,
        locale_tag: Option<&str>,
        _text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> RenderTaskList {
        vec![Box::new(HighlightRenderTask::new(
            element.clone(),
            data.clone(),
            locale_tag.map(str::to_owned),
        ))]
    }
}
