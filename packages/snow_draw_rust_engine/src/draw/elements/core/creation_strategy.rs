#![allow(dead_code)]
#![allow(unused_imports)]
#![allow(unused_variables)]

use std::any::{type_name, Any};
use std::fmt;
use std::sync::Arc;

use crate::draw::config::draw_config::{DrawConfig, ElementConfig};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::{default_text_metrics_service, TextMetricsService};
use crate::draw::types::snap_guides::SnapGuide;
use crate::draw::utils::snapping_mode::SnappingMode;

/// Type-specific, immutable element payload used by creation strategies.
///
/// This local trait mirrors the Dart `ElementData` contract closely enough for
/// strategy translation while the dedicated element-data module is still
/// migrating.
pub trait ElementData: Any + fmt::Debug + Send + Sync {
    fn as_any(&self) -> &dyn Any;

    fn runtime_type_name(&self) -> &'static str {
        std::any::type_name_of_val(self.as_any())
    }
}

impl<T> ElementData for T
where
    T: Any + fmt::Debug + Send + Sync,
{
    fn as_any(&self) -> &dyn Any {
        self
    }
}

/// Aggregate draw-state used by creation strategy signatures.
///
/// This aliases the translated domain/application state model so creation
/// strategies can consume real document/view data (elements, versions, zoom).
pub type DrawState = crate::draw::models::draw_state::DrawState;

/// Point-based creation session details.
#[derive(Clone, Default)]
pub struct PointCreationMode {
    pub fixed_points: Vec<DrawPoint>,
    pub current_point: Option<DrawPoint>,
    pub session_data: Option<Arc<dyn Any + Send + Sync>>,
}

impl PartialEq for PointCreationMode {
    fn eq(&self, other: &Self) -> bool {
        self.fixed_points == other.fixed_points && self.current_point == other.current_point
    }
}

impl fmt::Debug for PointCreationMode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PointCreationMode")
            .field("fixed_points_len", &self.fixed_points.len())
            .field("current_point", &self.current_point)
            .field("has_session_data", &self.session_data.is_some())
            .finish()
    }
}

/// Discriminator for creation mode within [`CreatingState`].
#[derive(Clone, Debug, Default, PartialEq)]
pub enum CreationMode {
    #[default]
    Rect,
    Point(PointCreationMode),
}

/// Element state snapshot used during creation.
#[derive(Clone, Debug)]
pub struct ElementState {
    pub id: String,
    pub type_id_value: String,
    pub rect: DrawRect,
    pub rotation: f64,
    pub opacity: f64,
    pub z_index: i64,
    pub data: Arc<dyn ElementData>,
}

impl ElementState {
    pub fn copy_with(
        &self,
        id: Option<String>,
        rect: Option<DrawRect>,
        rotation: Option<f64>,
        opacity: Option<f64>,
        z_index: Option<i64>,
        data: Option<Arc<dyn ElementData>>,
    ) -> Self {
        Self {
            id: id.unwrap_or_else(|| self.id.clone()),
            type_id_value: self.type_id_value.clone(),
            rect: rect.unwrap_or(self.rect),
            rotation: rotation.unwrap_or(self.rotation),
            opacity: opacity.unwrap_or(self.opacity),
            z_index: z_index.unwrap_or(self.z_index),
            data: data.unwrap_or_else(|| Arc::clone(&self.data)),
        }
    }

    pub fn is_valid_with(&self, config: &ElementConfig) -> bool {
        self.rect.width() >= config.min_valid_size && self.rect.height() >= config.min_valid_size
    }
}

/// In-progress creation interaction state.
#[derive(Clone, Debug)]
pub struct CreatingState {
    pub element: ElementState,
    pub start_position: DrawPoint,
    pub current_rect: DrawRect,
    pub snap_guides: Vec<SnapGuide>,
    pub creation_mode: CreationMode,
}

impl CreatingState {
    pub fn element_data(&self) -> Arc<dyn ElementData> {
        Arc::clone(&self.element.data)
    }

    pub fn element_data_ref(&self) -> &Arc<dyn ElementData> {
        &self.element.data
    }

    pub fn copy_with(
        &self,
        element: Option<ElementState>,
        start_position: Option<DrawPoint>,
        current_rect: Option<DrawRect>,
        snap_guides: Option<Vec<SnapGuide>>,
        creation_mode: Option<CreationMode>,
    ) -> Self {
        Self {
            element: element.unwrap_or_else(|| self.element.clone()),
            start_position: start_position.unwrap_or(self.start_position),
            current_rect: current_rect.unwrap_or(self.current_rect),
            snap_guides: snap_guides.unwrap_or_else(|| self.snap_guides.clone()),
            creation_mode: creation_mode.unwrap_or_else(|| self.creation_mode.clone()),
        }
    }
}

/// Result for creation start/update phases.
#[derive(Clone, Debug)]
pub struct CreationUpdateResult {
    pub data: Arc<dyn ElementData>,
    pub rect: DrawRect,
    pub creation_mode: CreationMode,
    pub snap_guides: Vec<SnapGuide>,
}

impl CreationUpdateResult {
    pub fn new(
        data: Arc<dyn ElementData>,
        rect: DrawRect,
        creation_mode: CreationMode,
        snap_guides: Vec<SnapGuide>,
    ) -> Self {
        Self {
            data,
            rect,
            creation_mode,
            snap_guides,
        }
    }
}

/// Result for creation finish.
#[derive(Clone, Debug)]
pub struct CreationFinishResult {
    pub data: Arc<dyn ElementData>,
    pub rect: DrawRect,
    pub should_commit: bool,
}

impl CreationFinishResult {
    pub fn new(data: Arc<dyn ElementData>, rect: DrawRect, should_commit: bool) -> Self {
        Self {
            data,
            rect,
            should_commit,
        }
    }
}

/// Strategy for element creation.
pub trait CreationStrategy {
    fn start(
        &self,
        data: Arc<dyn ElementData>,
        start_position: DrawPoint,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult;

    fn update(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        current_position: DrawPoint,
        maintain_aspect_ratio: bool,
        create_from_center: bool,
        snapping_mode: SnappingMode,
        snap_override_active: bool,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult;

    /// Applies a batch of pointer positions to the current creation session.
    ///
    /// The default implementation falls back to repeatedly calling [`Self::update`].
    /// Strategies with high-frequency workflows (for example free draw) can
    /// override this to process a whole sample batch with less overhead.
    fn update_batch(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        positions: &[DrawPoint],
        maintain_aspect_ratio: bool,
        create_from_center: bool,
        snapping_mode: SnappingMode,
        snap_override_active: bool,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        if positions.is_empty() {
            return CreationUpdateResult::new(
                creating_state.element_data(),
                creating_state.current_rect,
                creating_state.creation_mode.clone(),
                creating_state.snap_guides.clone(),
            );
        }

        let text_metrics_service =
            text_metrics_service.unwrap_or_else(default_text_metrics_service);

        let mut working = creating_state.clone();
        for position in positions {
            let update_result = self.update(
                state,
                config,
                &working,
                *position,
                maintain_aspect_ratio,
                create_from_center,
                snapping_mode,
                snap_override_active,
                Some(Arc::clone(&text_metrics_service)),
            );

            let base_element = working.element.clone();
            let updated_element = if Arc::ptr_eq(&update_result.data, &working.element.data) {
                base_element
            } else {
                base_element.copy_with(None, None, None, None, None, Some(update_result.data))
            };

            working = working.copy_with(
                Some(updated_element),
                None,
                Some(update_result.rect),
                Some(update_result.snap_guides),
                Some(update_result.creation_mode),
            );
        }

        CreationUpdateResult::new(
            working.element_data(),
            working.current_rect,
            working.creation_mode.clone(),
            working.snap_guides.clone(),
        )
    }

    fn add_point(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        position: DrawPoint,
        snapping_mode: SnappingMode,
        snap_override_active: bool,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> Option<CreationUpdateResult> {
        None
    }

    fn finish(
        &self,
        config: &DrawConfig,
        creating_state: &CreatingState,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationFinishResult;
}

/// Creation strategy marker for point-based workflows.
pub trait PointCreationStrategy: CreationStrategy {}

/// Casts `data` to `T` for a concrete creation strategy.
///
/// Creation strategies are wired by element definition, so receiving a
/// mismatched data type indicates a programming error.
pub fn require_creation_data_type<'a, T>(
    data: &'a Arc<dyn ElementData>,
    strategy_name: &str,
) -> &'a T
where
    T: ElementData + 'static,
{
    data.as_ref()
        .as_any()
        .downcast_ref::<T>()
        .unwrap_or_else(|| {
            panic!(
                "{strategy_name} expects {} but received {}.",
                type_name::<T>(),
                data.as_ref().runtime_type_name()
            )
        })
}

/// Casts `CreatingState.element_data` to `T` for a concrete strategy phase.
pub fn require_creating_element_data_type<'a, T>(
    creating_state: &'a CreatingState,
    strategy_name: &str,
) -> &'a T
where
    T: ElementData + 'static,
{
    require_creation_data_type::<T>(creating_state.element_data_ref(), strategy_name)
}

/// Returns whether the creation result should be committed to the document.
///
/// The element must satisfy both minimum size and element-level validity
/// constraints from `config`.
pub fn should_commit_creation_result(
    config: &DrawConfig,
    creating_state: &CreatingState,
    rect: Option<DrawRect>,
) -> bool {
    let resolved_rect = rect.unwrap_or(creating_state.current_rect);
    let min_size = config.element.min_create_size;
    resolved_rect.width() >= min_size
        && resolved_rect.height() >= min_size
        && creating_state
            .element
            .copy_with(None, Some(resolved_rect), None, None, None, None)
            .is_valid_with(&config.element)
}

/// Builds a standard finish result using the current creation rect.
pub fn finish_creation_with_current_rect(
    config: &DrawConfig,
    creating_state: &CreatingState,
) -> CreationFinishResult {
    let rect = creating_state.current_rect;
    CreationFinishResult::new(
        creating_state.element_data(),
        rect,
        should_commit_creation_result(config, creating_state, Some(rect)),
    )
}

/// Snaps `point` to the creation grid when grid snapping is active.
pub fn snap_creation_point(
    point: DrawPoint,
    config: &DrawConfig,
    snapping_mode: SnappingMode,
) -> DrawPoint {
    if snapping_mode != SnappingMode::Grid {
        return point;
    }

    let snapped_x = snap_value(point.x, config.grid.size);
    let snapped_y = snap_value(point.y, config.grid.size);
    if same_coordinate(snapped_x, point.x) && same_coordinate(snapped_y, point.y) {
        return point;
    }

    point.copy_with(Some(snapped_x), Some(snapped_y), None, None)
}

fn snap_value(value: f64, grid_size: f64) -> f64 {
    if !value.is_finite() || !grid_size.is_finite() || grid_size <= 0.0 {
        return value;
    }

    let snapped = (value / grid_size).round() * grid_size;
    if snapped.is_finite() {
        snapped
    } else {
        value
    }
}

fn same_coordinate(a: f64, b: f64) -> bool {
    a == b || (a.is_nan() && b.is_nan())
}
