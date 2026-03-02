#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::elements::core::typed_element_render_task_encoder::{
    ElementState, RenderTaskList, TypedElementRenderTaskEncoder,
};
use crate::draw::types::edit_context::TextMetricsService;

use super::serial_number_data::SerialNumberData;

/// Element-level render task for serial-number payloads.
///
/// Mirrors Dart
/// `SerialNumberRenderTask(element: ..., data: ..., localeTag: ...)`.
#[derive(Debug, Clone)]
pub struct SerialNumberRenderTask {
    pub element: ElementState,
    pub data: SerialNumberData,
    pub locale_tag: Option<String>,
}

impl SerialNumberRenderTask {
    /// Creates a new serial-number render task snapshot.
    pub fn new(element: ElementState, data: SerialNumberData, locale_tag: Option<String>) -> Self {
        Self {
            element,
            data,
            locale_tag,
        }
    }
}

/// Encodes serial-number elements into high-level render tasks.
///
/// Translation of Dart
/// `SerialNumberTaskEncoder extends TypedElementRenderTaskEncoder<SerialNumberData>`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct SerialNumberTaskEncoder;

impl SerialNumberTaskEncoder {
    /// Creates a serial-number task encoder.
    pub const fn new() -> Self {
        Self
    }
}

impl TypedElementRenderTaskEncoder<SerialNumberData> for SerialNumberTaskEncoder {
    fn encode_typed_tasks(
        &self,
        element: &ElementState,
        data: &SerialNumberData,
        locale_tag: Option<&str>,
        _text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> RenderTaskList {
        vec![Box::new(SerialNumberRenderTask::new(
            element.clone(),
            data.clone(),
            locale_tag.map(str::to_owned),
        ))]
    }
}
