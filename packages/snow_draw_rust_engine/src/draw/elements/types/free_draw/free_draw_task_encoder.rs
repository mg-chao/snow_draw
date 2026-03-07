#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::elements::core::typed_element_render_task_encoder::{
    ElementState, RenderTaskList, TypedElementRenderTaskEncoder,
};
use crate::draw::types::edit_context::TextMetricsService;

use super::free_draw_data::FreeDrawData;

/// Element-level render task for free-draw payloads.
///
/// Mirrors Dart `FreeDrawRenderTask(element: ..., data: ..., localeTag: ...)`.
#[derive(Debug, Clone)]
pub struct FreeDrawRenderTask {
    pub element: ElementState,
    pub data: FreeDrawData,
    pub locale_tag: Option<String>,
}

impl FreeDrawRenderTask {
    /// Creates a new free-draw render task snapshot.
    pub fn new(element: ElementState, data: FreeDrawData, locale_tag: Option<String>) -> Self {
        Self {
            element,
            data,
            locale_tag,
        }
    }
}

/// Encodes free-draw elements into high-level render tasks.
///
/// Translation of Dart
/// `FreeDrawTaskEncoder extends TypedElementRenderTaskEncoder<FreeDrawData>`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct FreeDrawTaskEncoder;

impl FreeDrawTaskEncoder {
    /// Creates a free-draw task encoder.
    pub const fn new() -> Self {
        Self
    }
}

impl TypedElementRenderTaskEncoder<FreeDrawData> for FreeDrawTaskEncoder {
    fn encode_typed_tasks(
        &self,
        element: &ElementState,
        data: &FreeDrawData,
        locale_tag: Option<&str>,
        _text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> RenderTaskList {
        vec![Box::new(FreeDrawRenderTask::new(
            element.clone(),
            data.clone(),
            locale_tag.map(str::to_owned),
        ))]
    }
}
