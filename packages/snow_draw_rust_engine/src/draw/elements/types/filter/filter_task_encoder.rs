#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::elements::core::typed_element_render_task_encoder::{
    ElementState, RenderTaskList, TypedElementRenderTaskEncoder,
};
use crate::draw::types::edit_context::TextMetricsService;

use super::filter_data::FilterData;

/// Element-level render task for filter payloads.
///
/// Mirrors Dart `FilterRenderTask(element: ..., data: ..., localeTag: ...)`.
#[derive(Debug, Clone)]
pub struct FilterRenderTask {
    pub element: ElementState,
    pub data: FilterData,
    pub locale_tag: Option<String>,
}

impl FilterRenderTask {
    /// Creates a new filter render task snapshot.
    pub fn new(element: ElementState, data: FilterData, locale_tag: Option<String>) -> Self {
        Self {
            element,
            data,
            locale_tag,
        }
    }
}

/// Encodes filter elements into high-level render tasks.
///
/// Translation of Dart
/// `FilterTaskEncoder extends TypedElementRenderTaskEncoder<FilterData>`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct FilterTaskEncoder;

impl FilterTaskEncoder {
    /// Creates a filter task encoder.
    pub const fn new() -> Self {
        Self
    }
}

impl TypedElementRenderTaskEncoder<FilterData> for FilterTaskEncoder {
    fn encode_typed_tasks(
        &self,
        element: &ElementState,
        data: &FilterData,
        locale_tag: Option<&str>,
        _text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> RenderTaskList {
        vec![Box::new(FilterRenderTask::new(
            element.clone(),
            data.clone(),
            locale_tag.map(str::to_owned),
        ))]
    }
}
