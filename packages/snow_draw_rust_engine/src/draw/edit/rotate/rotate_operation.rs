#![allow(dead_code)]

use std::collections::{HashMap, HashSet};

use crate::draw::config::draw_config::DrawConfig;
use crate::draw::edit::apply::edit_apply::EditApply;
use crate::draw::edit::core::edit_compute_pipeline::finalize_domain_result;
use crate::draw::edit::core::edit_computed_result::EditComputedResult;
use crate::draw::edit::core::edit_modifiers::EditModifiers;
use crate::draw::edit::core::edit_operation_params::RotateOperationParams;
use crate::draw::edit::core::edit_result::EditUpdateResult;
use crate::draw::edit::core::edit_validation::EditValidation;
use crate::draw::edit::rotate::angle_calculator::{
    apply_discrete_snap, normalize_delta, raw_angle,
};
use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::history::history_metadata::HistoryMetadata;
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::element_state::ElementState;
use crate::draw::models::multi_select_lifecycle::{MultiSelectLifecycle, SelectionOverlayState};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::{EditContext, RotateEditContext};
use crate::draw::types::edit_operation_id::{EditOperationId, EditOperationIds};
use crate::draw::types::edit_transform::{EditTransform, RotateTransform};
use crate::draw::types::element_geometry::ElementRotateSnapshot;
use crate::draw::types::element_style::ArrowType;

/// Additional state access needed by [`RotateOperation`].
///
/// The translated engine currently has multiple in-progress `DrawState`
/// compatibility layers, so rotate logic reads through this trait and stays
/// compile-friendly even when a concrete state cannot expose full geometry.
pub trait RotateOperationState {
    /// Returns selected ids captured at edit start.
    fn selected_ids_at_start(&self) -> HashSet<String>;

    /// Selection version at edit start.
    fn selection_version(&self) -> i64 {
        0
    }

    /// Elements version at edit start.
    fn elements_version(&self) -> i64 {
        0
    }

    /// Selected elements snapshot source used to build rotate snapshots.
    fn selected_elements_for_rotate(&self, _selected_ids: &HashSet<String>) -> Vec<ElementState> {
        Vec::new()
    }

    /// Current multi-select overlay rotation (radians), when available.
    fn multi_select_overlay_rotation(&self) -> Option<f64> {
        None
    }

    /// Current element map by id used to compute previews/commit payloads.
    fn current_elements_by_id(&self) -> Option<HashMap<String, ElementState>> {
        None
    }
}

impl RotateOperationState for DrawState {
    fn selected_ids_at_start(&self) -> HashSet<String> {
        self.domain.selection.selected_ids.iter().cloned().collect()
    }

    fn selection_version(&self) -> i64 {
        self.domain.selection.selection_version as i64
    }

    fn elements_version(&self) -> i64 {
        self.domain.document.elements_version
    }

    fn selected_elements_for_rotate(&self, selected_ids: &HashSet<String>) -> Vec<ElementState> {
        selected_ids
            .iter()
            .filter_map(|id| self.domain.document.get_element_by_id(id).cloned())
            .collect()
    }

    fn multi_select_overlay_rotation(&self) -> Option<f64> {
        self.application
            .selection_overlay
            .multi_select_overlay
            .map(|overlay| overlay.rotation)
    }

    fn current_elements_by_id(&self) -> Option<HashMap<String, ElementState>> {
        Some(self.domain.document.element_map())
    }
}

/// Translation of Dart `RotateOperation`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct RotateOperation;

impl RotateOperation {
    pub const fn new() -> Self {
        Self
    }

    pub const fn id(&self) -> EditOperationId {
        EditOperationIds::ROTATE
    }

    pub fn create_history_metadata(
        &self,
        context: &RotateEditContext,
        _transform: RotateTransform,
    ) -> HistoryMetadata {
        HistoryMetadata::for_rotate(context.base.selected_ids_at_start.clone())
    }

    /// Creates rotate context from state-access adapters.
    pub fn create_context(
        &self,
        state: &impl RotateOperationState,
        position: DrawPoint,
        params: RotateOperationParams,
    ) -> RotateEditContext {
        let selected_ids = state.selected_ids_at_start();
        let selected_elements = state.selected_elements_for_rotate(&selected_ids);

        self.create_context_from_elements(
            position,
            params,
            selected_ids,
            state.selection_version(),
            state.elements_version(),
            &selected_elements,
            state.multi_select_overlay_rotation(),
        )
    }

    /// Creates rotate context from explicit selected element list.
    pub fn create_context_from_elements(
        &self,
        start_position: DrawPoint,
        params: RotateOperationParams,
        selected_ids_at_start: HashSet<String>,
        selection_version: i64,
        elements_version: i64,
        selected_elements: &[ElementState],
        multi_select_overlay_rotation: Option<f64>,
    ) -> RotateEditContext {
        let start_bounds = params
            .initial_selection_bounds
            .or_else(|| compute_selection_bounds_for_elements(selected_elements))
            .unwrap_or_else(|| DrawRect::from_point(start_position));
        let element_snapshots = build_rotate_snapshots(selected_elements);
        let start_angle = params
            .start_rotation_angle
            .unwrap_or_else(|| raw_angle(start_position, start_bounds.center()));
        let base_rotation = resolve_base_rotation(
            &selected_ids_at_start,
            &element_snapshots,
            multi_select_overlay_rotation,
        );

        let base = EditContext::new(
            start_position,
            start_bounds,
            selected_ids_at_start,
            selection_version,
            elements_version,
        );

        RotateEditContext::new(
            base,
            start_angle,
            base_rotation,
            params.rotation_snap_angle,
            element_snapshots,
        )
    }

    pub fn update(
        &self,
        _state: &impl RotateOperationState,
        context: &RotateEditContext,
        transform: RotateTransform,
        current_position: DrawPoint,
        modifiers: EditModifiers,
        _config: &DrawConfig,
    ) -> EditUpdateResult<RotateTransform> {
        let raw_angle_value = raw_angle(current_position, context.base.start_center());
        let previous_raw_angle = transform.last_raw_angle.unwrap_or(context.start_angle);
        let next_raw_accumulated =
            transform.raw_accumulated_angle + normalize_delta(raw_angle_value - previous_raw_angle);

        let applied_delta = if modifiers.discrete_angle && context.rotation_snap_angle > 0.0 {
            apply_discrete_snap(
                next_raw_accumulated,
                context.base_rotation,
                context.rotation_snap_angle,
            )
        } else {
            next_raw_accumulated
        };

        let next_transform = transform.copy_with(
            Some(next_raw_accumulated),
            Some(applied_delta),
            Some(raw_angle_value),
            false,
        );

        EditUpdateResult::new(next_transform)
    }

    pub fn initial_transform(
        &self,
        _state: &impl RotateOperationState,
        context: &RotateEditContext,
        _start_position: DrawPoint,
    ) -> RotateTransform {
        RotateTransform::ZERO.copy_with(None, None, Some(context.start_angle), false)
    }

    /// Computes rotate geometry result using `state.current_elements_by_id()`.
    ///
    /// Returns `None` when context/transform are invalid or when the adapter
    /// cannot expose a current element map yet.
    pub fn compute_result(
        &self,
        state: &impl RotateOperationState,
        context: &RotateEditContext,
        transform: RotateTransform,
    ) -> Option<EditComputedResult> {
        let current_elements = state.current_elements_by_id()?;
        self.compute_result_with_element_map(context, transform, &current_elements)
    }

    /// Computes rotate geometry result against an explicit element map.
    pub fn compute_result_with_element_map(
        &self,
        context: &RotateEditContext,
        transform: RotateTransform,
        current_elements_by_id: &HashMap<String, ElementState>,
    ) -> Option<EditComputedResult> {
        let typed_transform = EditTransform::Rotate(transform);
        if EditValidation::should_skip_compute_with_default_bounds(context, &typed_transform) {
            return None;
        }

        let updated_by_id = EditApply::apply_rotate_to_elements(
            &context.element_snapshots,
            &context.base.selected_ids_at_start,
            context.base.start_bounds.center(),
            transform.applied_angle,
            current_elements_by_id,
        );
        if updated_by_id.is_empty() {
            return None;
        }

        let selected_ids = context.base.selected_ids_at_start.clone();
        finalize_domain_result(
            current_elements_by_id,
            updated_by_id,
            None,
            Some(context.base_rotation + transform.applied_angle),
            Some(&|id, element| selected_ids.contains(id) && is_elbow_arrow_element(element)),
        )
    }

    pub fn update_overlay(
        &self,
        current: SelectionOverlayState,
        result: &EditComputedResult,
        context: &RotateEditContext,
    ) -> SelectionOverlayState {
        if !context.base.is_multi_select() {
            return current;
        }

        match result.multi_select_rotation {
            Some(new_rotation) => MultiSelectLifecycle::on_rotate_finished(
                current,
                new_rotation,
                context.base.start_bounds,
            ),
            None => current,
        }
    }
}

fn resolve_base_rotation(
    selected_ids: &HashSet<String>,
    element_snapshots: &HashMap<String, ElementRotateSnapshot>,
    multi_select_overlay_rotation: Option<f64>,
) -> f64 {
    if selected_ids.len() > 1 {
        return multi_select_overlay_rotation.unwrap_or(0.0);
    }

    selected_ids
        .iter()
        .next()
        .and_then(|id| element_snapshots.get(id))
        .map_or(0.0, |snapshot| snapshot.rotation)
}

fn build_rotate_snapshots(elements: &[ElementState]) -> HashMap<String, ElementRotateSnapshot> {
    elements
        .iter()
        .map(|element| {
            (
                element.id.clone(),
                ElementRotateSnapshot {
                    center: element.rect.center(),
                    rotation: element.rotation,
                },
            )
        })
        .collect()
}

fn compute_selection_bounds_for_elements(elements: &[ElementState]) -> Option<DrawRect> {
    let first = elements.first()?;
    if elements.len() == 1 {
        return Some(first.rect);
    }

    let mut bounds = element_world_aabb(first);
    for element in &elements[1..] {
        let aabb = element_world_aabb(element);
        bounds = DrawRect::new(
            bounds.min_x.min(aabb.min_x),
            bounds.min_y.min(aabb.min_y),
            bounds.max_x.max(aabb.max_x),
            bounds.max_y.max(aabb.max_y),
        );
    }
    Some(bounds)
}

fn element_world_aabb(element: &ElementState) -> DrawRect {
    if element.rotation == 0.0 {
        return element.rect;
    }

    let center = element.rect.center();
    let half_width = element.rect.width().abs() / 2.0;
    let half_height = element.rect.height().abs() / 2.0;
    let cos_theta = element.rotation.cos().abs();
    let sin_theta = element.rotation.sin().abs();
    let x_extent = half_width * cos_theta + half_height * sin_theta;
    let y_extent = half_width * sin_theta + half_height * cos_theta;

    DrawRect::new(
        center.x - x_extent,
        center.y - y_extent,
        center.x + x_extent,
        center.y + y_extent,
    )
}

fn is_elbow_arrow_element(element: &ElementState) -> bool {
    if element.data.type_id().as_str() != ArrowData::TYPE_ID_TOKEN {
        return false;
    }

    let payload = element.data.to_json_value();
    ArrowData::from_json_value(&payload)
        .map(|data| data.arrow_type == ArrowType::Elbow)
        .unwrap_or(false)
}
