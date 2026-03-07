#![allow(dead_code)]

use std::collections::{HashMap, HashSet};

use crate::draw::config::draw_config::DrawConfig;
use crate::draw::core::geometry::move_geometry::MoveGeometry;
use crate::draw::edit::apply::edit_apply::EditApply;
use crate::draw::edit::core::edit_compute_pipeline::{
    finalize_domain_result, ordered_element_ids_from_element_map,
};
use crate::draw::edit::core::edit_computed_result::EditComputedResult;
use crate::draw::edit::core::edit_modifiers::EditModifiers;
use crate::draw::edit::core::edit_operation_params::MoveOperationParams;
use crate::draw::edit::core::edit_result::EditUpdateResult;
use crate::draw::edit::core::edit_validation::EditValidation;
use crate::draw::history::history_metadata::HistoryMetadata;
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::element_state::ElementState;
use crate::draw::models::multi_select_lifecycle::{MultiSelectLifecycle, SelectionOverlayState};
use crate::draw::services::object_snap_service::OBJECT_SNAP_SERVICE;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::{
    EditContext, ElementState as MoveReferenceElementState, MoveEditContext,
};
use crate::draw::types::edit_operation_id::{EditOperationId, EditOperationIds};
use crate::draw::types::edit_transform::{EditTransform, MoveTransform};
use crate::draw::types::element_geometry::ElementMoveSnapshot;
use crate::draw::types::snap_guides::{SnapGuide, SnapGuideAxis, SnapGuideKind};
use crate::draw::utils::camera_zoom::resolve_zoom_adjusted_distance;
use crate::draw::utils::snapping_mode::{resolve_effective_snapping_mode_for_config, SnappingMode};

/// Additional state access needed by [`MoveOperation`].
///
/// Move logic reads state through this trait to keep the operation reusable
/// and testable across state containers.
pub trait MoveOperationState {
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

    /// Current camera zoom used for zoom-adjusted snapping distance.
    fn view_zoom(&self) -> f64 {
        1.0
    }

    /// Selected elements snapshot source used to build move snapshots.
    fn selected_elements_for_move(&self, _selected_ids: &HashSet<String>) -> Vec<ElementState> {
        Vec::new()
    }

    /// Reference elements used for object snapping.
    fn reference_elements_for_move(&self, _selected_ids: &HashSet<String>) -> Vec<ElementState> {
        Vec::new()
    }

    /// Current element map by id used to compute previews/commit payloads.
    fn current_elements_by_id(&self) -> Option<HashMap<String, ElementState>> {
        None
    }
}

impl MoveOperationState for DrawState {
    fn selected_ids_at_start(&self) -> HashSet<String> {
        self.domain.selection.selected_ids.iter().cloned().collect()
    }

    fn selection_version(&self) -> i64 {
        self.domain.selection.selection_version as i64
    }

    fn elements_version(&self) -> i64 {
        self.domain.document.elements_version
    }

    fn view_zoom(&self) -> f64 {
        self.application.view.camera.zoom
    }

    fn selected_elements_for_move(&self, selected_ids: &HashSet<String>) -> Vec<ElementState> {
        selected_ids
            .iter()
            .filter_map(|id| self.domain.document.get_element_by_id(id).cloned())
            .collect()
    }

    fn reference_elements_for_move(&self, selected_ids: &HashSet<String>) -> Vec<ElementState> {
        self.domain
            .document
            .elements
            .iter()
            .filter(|element| !selected_ids.contains(&element.id))
            .cloned()
            .collect()
    }

    fn current_elements_by_id(&self) -> Option<HashMap<String, ElementState>> {
        Some(self.domain.document.element_map())
    }
}

/// Translation of Dart `MoveOperation`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct MoveOperation;

impl MoveOperation {
    pub const fn new() -> Self {
        Self
    }

    pub const fn id(&self) -> EditOperationId {
        EditOperationIds::MOVE
    }

    pub fn create_history_metadata(
        &self,
        context: &MoveEditContext,
        _transform: MoveTransform,
    ) -> HistoryMetadata {
        HistoryMetadata::for_move(context.base.selected_ids_at_start.clone())
    }

    /// Creates move context from state-access adapters.
    pub fn create_context(
        &self,
        state: &impl MoveOperationState,
        position: DrawPoint,
        params: MoveOperationParams,
    ) -> MoveEditContext {
        let selected_ids = state.selected_ids_at_start();
        let selected_elements = state.selected_elements_for_move(&selected_ids);
        let reference_elements = state.reference_elements_for_move(&selected_ids);

        self.create_context_from_elements(
            position,
            params.initial_selection_bounds,
            selected_ids,
            state.selection_version(),
            state.elements_version(),
            &selected_elements,
            &reference_elements,
        )
    }

    /// Creates move context from explicit selected/reference element lists.
    pub fn create_context_from_elements(
        &self,
        start_position: DrawPoint,
        initial_selection_bounds: Option<DrawRect>,
        selected_ids_at_start: HashSet<String>,
        selection_version: i64,
        elements_version: i64,
        selected_elements: &[ElementState],
        reference_elements: &[ElementState],
    ) -> MoveEditContext {
        let start_bounds = initial_selection_bounds
            .or_else(|| compute_selection_bounds_for_elements(selected_elements))
            .unwrap_or_else(|| DrawRect::from_point(start_position));
        let snap_bounds =
            compute_selection_bounds_for_elements(selected_elements).unwrap_or(start_bounds);

        let base = EditContext::new(
            start_position,
            start_bounds,
            selected_ids_at_start,
            selection_version,
            elements_version,
        );

        MoveEditContext {
            base,
            element_snapshots: build_move_snapshots(selected_elements),
            snap_bounds_at_start: Some(snap_bounds),
            reference_elements: reference_elements
                .iter()
                .map(|element| MoveReferenceElementState {
                    id: element.id.clone(),
                    rect: element.rect,
                    rotation: element.rotation,
                    opacity: element.opacity,
                    z_index: element.z_index,
                    data: element.data.clone(),
                })
                .collect(),
            reference_element_aabbs: reference_elements.iter().map(element_world_aabb).collect(),
        }
    }

    pub fn update(
        &self,
        state: &impl MoveOperationState,
        context: &MoveEditContext,
        _transform: MoveTransform,
        current_position: DrawPoint,
        modifiers: EditModifiers,
        config: &DrawConfig,
    ) -> EditUpdateResult<MoveTransform> {
        let displacement =
            MoveGeometry::calculate_displacement(context.base.start_position, current_position);
        if displacement.dx == 0.0 && displacement.dy == 0.0 {
            return EditUpdateResult::new(MoveTransform::ZERO);
        }

        let snapped = self.resolve_snapped_displacement(
            state,
            context,
            displacement.dx,
            displacement.dy,
            modifiers,
            config,
        );

        let next_transform = MoveTransform::new(snapped.dx, snapped.dy);
        if snapped.guides.is_empty() {
            EditUpdateResult::new(next_transform)
        } else {
            EditUpdateResult::with_snap_guides(next_transform, snapped.guides)
        }
    }

    pub const fn initial_transform(
        &self,
        _state: &impl MoveOperationState,
        _context: &MoveEditContext,
        _start_position: DrawPoint,
    ) -> MoveTransform {
        MoveTransform::ZERO
    }

    /// Computes move geometry result using `state.current_elements_by_id()`.
    ///
    /// Returns `None` when context/transform are invalid or when the adapter
    /// cannot expose a current element map yet.
    pub fn compute_result(
        &self,
        state: &impl MoveOperationState,
        context: &MoveEditContext,
        transform: MoveTransform,
    ) -> Option<EditComputedResult> {
        let current_elements = state.current_elements_by_id()?;
        self.compute_result_with_element_map(context, transform, &current_elements)
    }

    /// Computes move geometry result against an explicit element map.
    pub fn compute_result_with_element_map(
        &self,
        context: &MoveEditContext,
        transform: MoveTransform,
        current_elements_by_id: &HashMap<String, ElementState>,
    ) -> Option<EditComputedResult> {
        let typed_transform = EditTransform::Move(transform);
        if EditValidation::should_skip_compute_with_default_bounds(context, &typed_transform) {
            return None;
        }

        let updated_by_id = EditApply::apply_move_to_elements(
            &context.element_snapshots,
            &context.base.selected_ids_at_start,
            transform.dx,
            transform.dy,
            current_elements_by_id,
        );

        if updated_by_id.is_empty() {
            return None;
        }

        let translated_bounds = context
            .base
            .start_bounds
            .translate(DrawPoint::new(transform.dx, transform.dy));
        let multi_select_bounds = context.base.is_multi_select().then_some(translated_bounds);
        let ordered_element_ids = ordered_element_ids_from_element_map(current_elements_by_id);

        finalize_domain_result(
            current_elements_by_id,
            updated_by_id,
            ordered_element_ids.as_slice(),
            multi_select_bounds,
            None,
            None,
        )
    }

    pub fn update_overlay(
        &self,
        current: SelectionOverlayState,
        result: &EditComputedResult,
        context: &MoveEditContext,
    ) -> SelectionOverlayState {
        if !context.base.is_multi_select() {
            return current;
        }

        match result.multi_select_bounds {
            Some(bounds) => MultiSelectLifecycle::on_move_finished(current, bounds),
            None => current,
        }
    }

    fn resolve_snapped_displacement(
        &self,
        state: &impl MoveOperationState,
        context: &MoveEditContext,
        base_dx: f64,
        base_dy: f64,
        modifiers: EditModifiers,
        config: &DrawConfig,
    ) -> MoveSnappedDisplacement {
        let target_offset = DrawPoint::new(base_dx, base_dy);
        let target_rect = context.snap_bounds().translate(target_offset);
        let snap_config = &config.snap;
        let snapping_mode =
            resolve_effective_snapping_mode_for_config(config, modifiers.snap_override);

        match snapping_mode {
            SnappingMode::Grid => {
                let snapped_rect = snap_rect_to_grid_min_corner(target_rect, config.grid.size);
                MoveSnappedDisplacement {
                    dx: base_dx + snapped_rect.min_x - target_rect.min_x,
                    dy: base_dy + snapped_rect.min_y - target_rect.min_y,
                    guides: Vec::new(),
                }
            }
            SnappingMode::Object => {
                if !snap_config.enable_point_snaps && !snap_config.enable_gap_snaps {
                    return MoveSnappedDisplacement::new(base_dx, base_dy);
                }

                let snap_distance =
                    resolve_zoom_adjusted_distance(snap_config.distance, state.view_zoom());
                let snap_result = OBJECT_SNAP_SERVICE.snap_move(
                    target_rect,
                    &context.reference_elements,
                    snap_distance,
                    Some(context.reference_element_aabbs.as_slice()),
                    snap_config.enable_point_snaps,
                    snap_config.enable_gap_snaps,
                );

                MoveSnappedDisplacement {
                    dx: base_dx + snap_result.dx,
                    dy: base_dy + snap_result.dy,
                    guides: if snap_config.show_guides {
                        snap_result.guides
                    } else {
                        Vec::new()
                    },
                }
            }
            SnappingMode::None => MoveSnappedDisplacement::new(base_dx, base_dy),
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
struct MoveSnappedDisplacement {
    dx: f64,
    dy: f64,
    guides: Vec<SnapGuide>,
}

impl MoveSnappedDisplacement {
    fn new(dx: f64, dy: f64) -> Self {
        Self {
            dx,
            dy,
            guides: Vec::new(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct AxisSnapCandidate {
    delta: f64,
    reference_line: f64,
    reference_rect: DrawRect,
}

fn build_move_snapshots(elements: &[ElementState]) -> HashMap<String, ElementMoveSnapshot> {
    elements
        .iter()
        .map(|element| {
            (
                element.id.clone(),
                ElementMoveSnapshot {
                    center: element.rect.center(),
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

fn snap_rect_to_grid_min_corner(rect: DrawRect, grid_size: f64) -> DrawRect {
    if !(grid_size.is_finite() && grid_size > 0.0) {
        return rect;
    }

    let snapped_min_x = (rect.min_x / grid_size).round() * grid_size;
    let snapped_min_y = (rect.min_y / grid_size).round() * grid_size;
    let dx = snapped_min_x - rect.min_x;
    let dy = snapped_min_y - rect.min_y;
    rect.translate(DrawPoint::new(dx, dy))
}

fn snap_to_reference_aabbs(
    target_rect: DrawRect,
    reference_aabbs: &[DrawRect],
    snap_distance: f64,
    show_guides: bool,
) -> MoveSnappedDisplacement {
    if reference_aabbs.is_empty() {
        return MoveSnappedDisplacement::default();
    }
    if !snap_distance.is_finite() || snap_distance < 0.0 {
        return MoveSnappedDisplacement::default();
    }

    let target_x_lines = [target_rect.min_x, target_rect.max_x, target_rect.center_x()];
    let target_y_lines = [target_rect.min_y, target_rect.max_y, target_rect.center_y()];

    let x_snap = resolve_axis_snap(target_x_lines, reference_aabbs, snap_distance, true);
    let y_snap = resolve_axis_snap(target_y_lines, reference_aabbs, snap_distance, false);

    let dx = x_snap.map_or(0.0, |candidate| candidate.delta);
    let dy = y_snap.map_or(0.0, |candidate| candidate.delta);

    if !show_guides {
        return MoveSnappedDisplacement {
            dx,
            dy,
            guides: Vec::new(),
        };
    }

    let snapped_target = target_rect.translate(DrawPoint::new(dx, dy));
    let mut guides = Vec::new();
    if let Some(candidate) = x_snap {
        guides.push(build_axis_guide(
            true,
            candidate.reference_line,
            snapped_target,
            candidate.reference_rect,
        ));
    }
    if let Some(candidate) = y_snap {
        guides.push(build_axis_guide(
            false,
            candidate.reference_line,
            snapped_target,
            candidate.reference_rect,
        ));
    }

    MoveSnappedDisplacement { dx, dy, guides }
}

fn resolve_axis_snap(
    target_lines: [f64; 3],
    reference_aabbs: &[DrawRect],
    snap_distance: f64,
    x_axis: bool,
) -> Option<AxisSnapCandidate> {
    let mut best: Option<AxisSnapCandidate> = None;

    for reference_rect in reference_aabbs {
        let reference_lines = if x_axis {
            [
                reference_rect.min_x,
                reference_rect.max_x,
                reference_rect.center_x(),
            ]
        } else {
            [
                reference_rect.min_y,
                reference_rect.max_y,
                reference_rect.center_y(),
            ]
        };

        for target_line in target_lines {
            for reference_line in reference_lines {
                let delta = reference_line - target_line;
                if delta.abs() > snap_distance {
                    continue;
                }

                match best {
                    None => {
                        best = Some(AxisSnapCandidate {
                            delta,
                            reference_line,
                            reference_rect: *reference_rect,
                        })
                    }
                    Some(current) => {
                        if delta.abs() < current.delta.abs() {
                            best = Some(AxisSnapCandidate {
                                delta,
                                reference_line,
                                reference_rect: *reference_rect,
                            });
                        }
                    }
                }
            }
        }
    }

    best
}

fn build_axis_guide(
    x_axis: bool,
    reference_line: f64,
    target_rect: DrawRect,
    reference_rect: DrawRect,
) -> SnapGuide {
    if x_axis {
        let min_y = target_rect.min_y.min(reference_rect.min_y);
        let max_y = target_rect.max_y.max(reference_rect.max_y);
        return SnapGuide::new(
            SnapGuideKind::Point,
            SnapGuideAxis::Vertical,
            DrawPoint::new(reference_line, min_y),
            DrawPoint::new(reference_line, max_y),
        );
    }

    let min_x = target_rect.min_x.min(reference_rect.min_x);
    let max_x = target_rect.max_x.max(reference_rect.max_x);
    SnapGuide::new(
        SnapGuideKind::Point,
        SnapGuideAxis::Horizontal,
        DrawPoint::new(min_x, reference_line),
        DrawPoint::new(max_x, reference_line),
    )
}
