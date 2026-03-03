#![allow(dead_code)]

use std::any::{type_name, type_name_of_val, Any};
use std::fmt;
use std::sync::Arc;

use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::TextMetricsService;

use super::element_data::ElementData as CoreElementData;

/// Extension of core element data with runtime downcasting support.
///
/// Dart performs a runtime `is! T` check before calling `encodeTypedTasks`.
/// This trait provides the same capability for Rust translations.
pub trait TypedElementData: CoreElementData + Any + Send + Sync {
    fn as_any(&self) -> &dyn Any;

    fn runtime_type_name(&self) -> &'static str {
        type_name_of_val(self.as_any())
    }
}

impl<T> TypedElementData for T
where
    T: CoreElementData + Any + Send + Sync,
{
    fn as_any(&self) -> &dyn Any {
        self
    }
}

/// Minimal element snapshot needed by render-task encoders.
///
/// This local struct keeps encoder contracts object-safe and independent from
/// higher-level model containers.
#[derive(Clone)]
pub struct ElementState {
    pub id: String,
    pub rect: DrawRect,
    pub rotation: f64,
    pub opacity: f64,
    pub z_index: i64,
    pub data: Arc<dyn TypedElementData>,
}

impl fmt::Debug for ElementState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ElementState")
            .field("id", &self.id)
            .field("rect", &self.rect)
            .field("rotation", &self.rotation)
            .field("opacity", &self.opacity)
            .field("z_index", &self.z_index)
            .field("data_type", &self.data.runtime_type_name())
            .finish()
    }
}

impl ElementState {
    pub fn copy_with(
        &self,
        id: Option<String>,
        rect: Option<DrawRect>,
        rotation: Option<f64>,
        opacity: Option<f64>,
        z_index: Option<i64>,
        data: Option<Arc<dyn TypedElementData>>,
    ) -> Self {
        Self {
            id: id.unwrap_or_else(|| self.id.clone()),
            rect: rect.unwrap_or(self.rect),
            rotation: rotation.unwrap_or(self.rotation),
            opacity: opacity.unwrap_or(self.opacity),
            z_index: z_index.unwrap_or(self.z_index),
            data: data.unwrap_or_else(|| Arc::clone(&self.data)),
        }
    }
}

/// Object-safe marker for render tasks produced by an encoder.
pub trait RenderTask: Send + Sync {}

impl<T> RenderTask for T where T: Send + Sync {}

/// Dynamic render task list consumed by downstream renderer stages.
pub type RenderTaskList = Vec<Box<dyn RenderTask>>;

/// Base implementation for strongly-typed render-task encoders.
///
/// Mirrors Dart's `TypedElementRenderTaskEncoder<T extends ElementData>`:
/// `encode_tasks` performs runtime type checks, then delegates to
/// `encode_typed_tasks`.
pub trait TypedElementRenderTaskEncoder<T>
where
    T: TypedElementData + 'static,
{
    fn encode_tasks(
        &self,
        element: &ElementState,
        locale_tag: Option<&str>,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> RenderTaskList {
        if let Some(locale_tag) = locale_tag {
            assert!(
                !locale_tag.is_empty(),
                "locale_tag must be None or non-empty."
            );
        }

        let data = require_element_data_type::<T>(element, type_name::<Self>());
        self.encode_typed_tasks(element, data, locale_tag, text_metrics_service)
    }

    /// Encodes `element` into typed render tasks using `data`.
    fn encode_typed_tasks(
        &self,
        element: &ElementState,
        data: &T,
        locale_tag: Option<&str>,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> RenderTaskList;
}

/// Casts `element.data` to `T` for a concrete render-task encoder.
///
/// Encoders are wired by element definitions, so a mismatch indicates a
/// programming error in registration logic.
pub fn require_element_data_type<'a, T>(element: &'a ElementState, encoder_name: &str) -> &'a T
where
    T: TypedElementData + 'static,
{
    element
        .data
        .as_ref()
        .as_any()
        .downcast_ref::<T>()
        .unwrap_or_else(|| {
            panic!(
                "{encoder_name} can only encode {} (got {}).",
                type_name::<T>(),
                element.data.runtime_type_name()
            )
        })
}
