#![allow(dead_code)]

use std::sync::Arc;

use super::line_data::LineData;
use crate::draw::elements::core::typed_element_render_task_encoder::{
    ElementState, RenderTaskList, TypedElementRenderTaskEncoder,
};
use crate::draw::types::edit_context::TextMetricsService;

/// Element-level render task for line payloads.
///
/// Mirrors Dart `LineRenderTask(element: ..., data: ..., localeTag: ...)`.
#[derive(Debug, Clone)]
pub struct LineRenderTask {
    pub element: ElementState,
    pub data: LineData,
    pub locale_tag: Option<String>,
}

impl LineRenderTask {
    /// Creates a new line render task snapshot.
    pub fn new(element: ElementState, data: LineData, locale_tag: Option<String>) -> Self {
        Self {
            element,
            data,
            locale_tag,
        }
    }
}

/// Encodes lines into high-level render tasks.
///
/// Translation of Dart `LineTaskEncoder extends TypedElementRenderTaskEncoder<LineData>`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct LineTaskEncoder;

impl LineTaskEncoder {
    /// Creates a line task encoder.
    pub const fn new() -> Self {
        Self
    }
}

impl TypedElementRenderTaskEncoder<LineData> for LineTaskEncoder {
    fn encode_typed_tasks(
        &self,
        element: &ElementState,
        data: &LineData,
        locale_tag: Option<&str>,
        _text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> RenderTaskList {
        vec![Box::new(LineRenderTask::new(
            element.clone(),
            data.clone(),
            locale_tag.map(str::to_owned),
        ))]
    }
}
