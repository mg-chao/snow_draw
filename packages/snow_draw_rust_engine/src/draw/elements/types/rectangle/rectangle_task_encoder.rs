#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::elements::core::typed_element_render_task_encoder::{
    ElementState, RenderTaskList, TypedElementRenderTaskEncoder,
};
use crate::draw::types::edit_context::TextMetricsService;

use super::rectangle_data::RectangleData;

/// Element-level render task for rectangle payloads.
///
/// Mirrors Dart `RectangleRenderTask(element: ..., data: ..., localeTag: ...)`.
#[derive(Debug, Clone)]
pub struct RectangleRenderTask {
    pub element: ElementState,
    pub data: RectangleData,
    pub locale_tag: Option<String>,
}

impl RectangleRenderTask {
    /// Creates a new rectangle render task snapshot.
    pub fn new(element: ElementState, data: RectangleData, locale_tag: Option<String>) -> Self {
        Self {
            element,
            data,
            locale_tag,
        }
    }
}

/// Encodes rectangles into high-level render tasks.
///
/// Translation of Dart
/// `RectangleTaskEncoder extends TypedElementRenderTaskEncoder<RectangleData>`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RectangleTaskEncoder;

impl RectangleTaskEncoder {
    /// Creates a rectangle task encoder.
    pub const fn new() -> Self {
        Self
    }
}

impl TypedElementRenderTaskEncoder<RectangleData> for RectangleTaskEncoder {
    fn encode_typed_tasks(
        &self,
        element: &ElementState,
        data: &RectangleData,
        locale_tag: Option<&str>,
        _text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> RenderTaskList {
        vec![Box::new(RectangleRenderTask::new(
            element.clone(),
            data.clone(),
            locale_tag.map(str::to_owned),
        ))]
    }
}
