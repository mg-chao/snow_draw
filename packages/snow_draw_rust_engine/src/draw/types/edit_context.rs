#![allow(dead_code)]

use crate::draw::elements::types::text::text_editing_geometry::{
    FallbackTextMetricsService as GeometryFallbackTextMetricsService,
    TextLayoutRequest as GeometryTextLayoutRequest, TextMetrics as GeometryTextMetrics,
    TextMetricsService as GeometryTextMetricsService,
};
use crate::draw::services::text::text_metrics_service::{
    FallbackTextMetricsService as ResizeFallbackTextMetricsService,
    TextMetricsService as ResizeTextMetricsService,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_geometry::{
    ElementMoveSnapshot, ElementResizeSnapshot, ElementRotateSnapshot,
};
use crate::draw::types::resize_mode::ResizeMode;
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::sync::Arc;

/// Shared base context captured at edit-start.
///
/// This snapshot is immutable for the lifetime of an edit session and
/// represents invariants that preview and commit logic should rely on.
#[derive(Clone, Debug)]
pub struct EditContext {
    /// Pointer position at the start of the edit operation (world coordinates).
    pub start_position: DrawPoint,

    /// Selection overlay bounds at the start of the edit operation.
    pub start_bounds: DrawRect,

    /// Selected element ids at the start of the edit operation.
    pub selected_ids_at_start: HashSet<String>,

    /// Selected element ids in the observable iteration order captured at edit start.
    pub selected_ids_at_start_in_order: Vec<String>,

    /// Selection version captured when the edit session started.
    pub selection_version: i64,

    /// Elements version captured when the edit session started.
    pub elements_version: i64,
}

impl EditContext {
    pub fn new(
        start_position: DrawPoint,
        start_bounds: DrawRect,
        selected_ids_at_start: HashSet<String>,
        selection_version: i64,
        elements_version: i64,
    ) -> Self {
        let selected_ids_at_start_in_order = selected_ids_at_start.iter().cloned().collect();
        Self::new_with_order(
            start_position,
            start_bounds,
            selected_ids_at_start,
            selected_ids_at_start_in_order,
            selection_version,
            elements_version,
        )
    }

    pub fn new_with_order(
        start_position: DrawPoint,
        start_bounds: DrawRect,
        selected_ids_at_start: HashSet<String>,
        selected_ids_at_start_in_order: Vec<String>,
        selection_version: i64,
        elements_version: i64,
    ) -> Self {
        Self {
            start_position,
            start_bounds,
            selected_ids_at_start,
            selected_ids_at_start_in_order,
            selection_version,
            elements_version,
        }
    }

    pub fn start_center(&self) -> DrawPoint {
        self.start_bounds.center()
    }

    pub fn is_single_select(&self) -> bool {
        self.selected_ids_at_start.len() == 1
    }

    pub fn is_multi_select(&self) -> bool {
        self.selected_ids_at_start.len() > 1
    }

    pub fn selected_ids_at_start_in_order(&self) -> &[String] {
        &self.selected_ids_at_start_in_order
    }
}

/// Behavior shared by concrete edit-context kinds.
pub trait EditContextLike {
    fn base(&self) -> &EditContext;

    fn start_center(&self) -> DrawPoint {
        self.base().start_center()
    }

    fn is_single_select(&self) -> bool {
        self.base().is_single_select()
    }

    fn is_multi_select(&self) -> bool {
        self.base().is_multi_select()
    }

    fn has_snapshots(&self) -> bool {
        false
    }
}

impl EditContextLike for EditContext {
    fn base(&self) -> &EditContext {
        self
    }
}

/// Reference element snapshot used by snapping contexts.
pub type ElementState = crate::draw::models::element_state::ElementState;

/// Context for move operations.
///
/// Stores only per-element centers using [`ElementMoveSnapshot`] to keep the
/// session snapshot lean.
#[derive(Clone, Debug)]
pub struct MoveEditContext {
    pub base: EditContext,
    pub element_snapshots: HashMap<String, ElementMoveSnapshot>,
    pub snap_bounds_at_start: Option<DrawRect>,
    pub reference_elements: Vec<ElementState>,
    pub reference_element_aabbs: Vec<DrawRect>,
}

impl MoveEditContext {
    pub fn new(base: EditContext, element_snapshots: HashMap<String, ElementMoveSnapshot>) -> Self {
        Self {
            base,
            element_snapshots,
            snap_bounds_at_start: None,
            reference_elements: Vec::new(),
            reference_element_aabbs: Vec::new(),
        }
    }

    pub fn snap_bounds(&self) -> DrawRect {
        self.snap_bounds_at_start.unwrap_or(self.base.start_bounds)
    }
}

impl EditContextLike for MoveEditContext {
    fn base(&self) -> &EditContext {
        &self.base
    }

    fn has_snapshots(&self) -> bool {
        !self.element_snapshots.is_empty()
    }
}

/// Text metrics abstraction used by resize calculations.
///
/// The same service is also consulted by text-editing reducers. Implementers
/// can optionally expose a text-editing compatible view.
pub trait TextMetricsService: fmt::Debug + Send + Sync {
    fn as_text_editing_metrics_service(&self) -> Option<&dyn GeometryTextMetricsService> {
        None
    }

    fn as_text_resize_metrics_service(&self) -> Option<&dyn ResizeTextMetricsService> {
        None
    }
}

#[derive(Debug, Default)]
pub struct DefaultTextMetricsService;

impl TextMetricsService for DefaultTextMetricsService {
    fn as_text_editing_metrics_service(&self) -> Option<&dyn GeometryTextMetricsService> {
        Some(self)
    }

    fn as_text_resize_metrics_service(&self) -> Option<&dyn ResizeTextMetricsService> {
        Some(self)
    }
}

impl GeometryTextMetricsService for DefaultTextMetricsService {
    fn measure(&self, request: &GeometryTextLayoutRequest<'_>) -> GeometryTextMetrics {
        let fallback = GeometryFallbackTextMetricsService;
        fallback.measure(request)
    }
}

impl ResizeTextMetricsService for DefaultTextMetricsService {
    fn measure(
        &self,
        request: &crate::draw::services::text::text_metrics_service::TextLayoutRequest<'_>,
    ) -> crate::draw::services::text::text_metrics_service::TextMetrics {
        let fallback = ResizeFallbackTextMetricsService;
        fallback.measure(request)
    }
}

/// Returns the default text metrics implementation for resize sessions.
pub fn default_text_metrics_service() -> Arc<dyn TextMetricsService> {
    Arc::new(DefaultTextMetricsService)
}

/// Context for resize operations.
///
/// Stores the minimum geometry needed for deterministic resize behavior across
/// the full drag session.
#[derive(Clone, Debug)]
pub struct ResizeEditContext {
    pub base: EditContext,
    pub resize_mode: ResizeMode,
    pub handle_offset: DrawPoint,
    pub rotation: f64,
    pub selection_padding: f64,
    pub element_snapshots: HashMap<String, ElementResizeSnapshot>,
    pub reference_elements: Vec<ElementState>,
    pub reference_element_aabbs: Vec<DrawRect>,
    pub force_serial_number_aspect_ratio: bool,
    pub text_metrics_service: Arc<dyn TextMetricsService>,
}

impl ResizeEditContext {
    pub fn new(
        base: EditContext,
        resize_mode: ResizeMode,
        handle_offset: DrawPoint,
        rotation: f64,
        element_snapshots: HashMap<String, ElementResizeSnapshot>,
    ) -> Self {
        Self {
            base,
            resize_mode,
            handle_offset,
            rotation,
            selection_padding: 0.0,
            element_snapshots,
            reference_elements: Vec::new(),
            reference_element_aabbs: Vec::new(),
            force_serial_number_aspect_ratio: false,
            text_metrics_service: default_text_metrics_service(),
        }
    }

    pub fn has_rotation(&self) -> bool {
        self.rotation != 0.0
    }

    pub fn with_text_metrics_service(
        &self,
        text_metrics_service: Arc<dyn TextMetricsService>,
    ) -> Self {
        if Arc::ptr_eq(&self.text_metrics_service, &text_metrics_service) {
            return self.clone();
        }

        let mut updated = self.clone();
        updated.text_metrics_service = text_metrics_service;
        updated
    }
}

impl EditContextLike for ResizeEditContext {
    fn base(&self) -> &EditContext {
        &self.base
    }

    fn has_snapshots(&self) -> bool {
        !self.element_snapshots.is_empty()
    }
}

/// Context for rotate operations.
///
/// Captures initial pointer angle, base rotation and per-element rotation
/// snapshots used to compute deterministic rotation deltas.
#[derive(Clone, Debug)]
pub struct RotateEditContext {
    pub base: EditContext,
    pub start_angle: f64,
    pub base_rotation: f64,
    pub rotation_snap_angle: f64,
    pub element_snapshots: HashMap<String, ElementRotateSnapshot>,
}

impl RotateEditContext {
    pub fn new(
        base: EditContext,
        start_angle: f64,
        base_rotation: f64,
        rotation_snap_angle: f64,
        element_snapshots: HashMap<String, ElementRotateSnapshot>,
    ) -> Self {
        Self {
            base,
            start_angle,
            base_rotation,
            rotation_snap_angle,
            element_snapshots,
        }
    }
}

impl EditContextLike for RotateEditContext {
    fn base(&self) -> &EditContext {
        &self.base
    }

    fn has_snapshots(&self) -> bool {
        !self.element_snapshots.is_empty()
    }
}
