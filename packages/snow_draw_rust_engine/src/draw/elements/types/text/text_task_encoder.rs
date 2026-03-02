#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::elements::core::typed_element_render_task_encoder::{
    ElementState, RenderTaskList, TypedElementRenderTaskEncoder,
};
use crate::draw::types::edit_context::TextMetricsService;

use super::text_data::TextData;

/// Element-level render task for text payloads.
///
/// Mirrors Dart `TextRenderTask(element: ..., data: ..., localeTag: ...)`.
#[derive(Debug, Clone)]
pub struct TextRenderTask {
    pub element: ElementState,
    pub data: TextData,
    pub locale_tag: Option<String>,
}

impl TextRenderTask {
    /// Creates a new text render task snapshot.
    pub fn new(element: ElementState, data: TextData, locale_tag: Option<String>) -> Self {
        Self {
            element,
            data,
            locale_tag,
        }
    }
}

/// Encodes text elements into high-level render tasks.
///
/// Translation of Dart
/// `TextTaskEncoder extends TypedElementRenderTaskEncoder<TextData>`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct TextTaskEncoder;

impl TextTaskEncoder {
    /// Creates a text task encoder.
    pub const fn new() -> Self {
        Self
    }
}

impl TypedElementRenderTaskEncoder<TextData> for TextTaskEncoder {
    fn encode_typed_tasks(
        &self,
        element: &ElementState,
        data: &TextData,
        locale_tag: Option<&str>,
        _text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> RenderTaskList {
        vec![Box::new(TextRenderTask::new(
            element.clone(),
            data.clone(),
            locale_tag.map(str::to_owned),
        ))]
    }
}
