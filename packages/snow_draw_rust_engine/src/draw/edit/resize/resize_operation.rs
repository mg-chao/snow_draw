#![allow(dead_code)]

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};

use crate::draw::config::draw_config::DrawConfig;
use crate::draw::core::coordinates::overlay_space::OverlaySpace;
use crate::draw::core::geometry::resize_geometry::ResizeGeometry;
use crate::draw::edit::apply::edit_apply::EditApply;
use crate::draw::edit::core::edit_compute_pipeline::{
    finalize_domain_result, ordered_element_ids_from_element_map,
};
use crate::draw::edit::core::edit_computed_result::EditComputedResult;
use crate::draw::edit::core::edit_modifiers::EditModifiers;
use crate::draw::edit::core::edit_operation::{
    EditOperation, EditOperationParams, EditPreview, EditUpdateResult,
};
use crate::draw::edit::core::edit_operation_helpers::resolve_reference_elements;
use crate::draw::edit::core::standard_finish_mixin::StandardFinishMixin;
use crate::draw::edit::resize::bounds::bounds_calculation::{
    calculate_resize_bounds, ResizeBoundsParams,
};
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::history::history_metadata::HistoryMetadata;
use crate::draw::models::application_state::SelectionOverlayState;
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::multi_select_lifecycle::MultiSelectOverlayState;
use crate::draw::services::grid_snap_service::GRID_SNAP_SERVICE;
use crate::draw::services::object_snap_service::{
    ObjectSnapService, SnapAxisAnchor as ObjectSnapAxisAnchor, OBJECT_SNAP_SERVICE,
};
use crate::draw::services::selection_data_computer::SelectionDataComputer;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::{
    default_text_metrics_service, EditContext, ElementState as ResizeReferenceElement,
    ResizeEditContext, TextMetricsService,
};
use crate::draw::types::edit_operation_id::{EditOperationId, EditOperationIds};
use crate::draw::types::edit_transform::{EditTransform, ResizeTransform};
use crate::draw::types::element_geometry::ElementResizeSnapshot;
use crate::draw::types::resize_mode::ResizeMode;
use crate::draw::types::snap_guides::SnapGuide;
use crate::draw::utils::camera_zoom::resolve_zoom_adjusted_distance;
use crate::draw::utils::handle_calculator::HandleCalculator;
use crate::draw::utils::snapping_mode::{resolve_effective_snapping_mode_for_config, SnappingMode};
use crate::draw::utils::transforms::edit_transform_context::EditTransformContext;
use crate::draw::utils::transforms::resize_anchor_point::opposite_bound_point_local;

const DEFAULT_SELECTION_PADDING: f64 = 0.0;

/// Compatibility params for `ResizeOperation`.
///
/// The current translated `EditOperation` trait only carries base params, so
/// this type keeps resize-specific settings available in this module.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ResizeOperationParams {
    pub resize_mode: ResizeMode,
    pub handle_offset: Option<DrawPoint>,
    pub selection_padding: f64,
    pub initial_selection_bounds: Option<DrawRect>,
}

impl ResizeOperationParams {
    pub fn from_base(params: &EditOperationParams) -> Self {
        if let Some(value) = params.as_resize() {
            return Self {
                resize_mode: value.resize_mode,
                handle_offset: value.handle_offset,
                selection_padding: value.selection_padding,
                initial_selection_bounds: value.initial_selection_bounds,
            };
        }

        Self {
            resize_mode: ResizeMode::BottomRight,
            handle_offset: None,
            selection_padding: DEFAULT_SELECTION_PADDING,
            initial_selection_bounds: params.initial_selection_bounds(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SnapAxisAnchor {
    Start,
    End,
}

#[derive(Clone, Debug)]
struct AxisAnchors {
    x: Vec<SnapAxisAnchor>,
    y: Vec<SnapAxisAnchor>,
}

#[derive(Clone, Debug)]
struct SnappedBoundsResult {
    bounds: DrawRect,
    guides: Vec<SnapGuide>,
}

#[derive(Clone, Debug)]
struct ResizeContextFingerprint {
    start_position: DrawPoint,
    start_bounds: DrawRect,
    selected_ids_at_start: HashSet<String>,
    selected_ids_at_start_in_order: Vec<String>,
    selection_version: i64,
    elements_version: i64,
}

impl ResizeContextFingerprint {
    fn from_context(context: &EditContext) -> Self {
        Self {
            start_position: context.start_position,
            start_bounds: context.start_bounds,
            selected_ids_at_start: context.selected_ids_at_start.clone(),
            selected_ids_at_start_in_order: context.selected_ids_at_start_in_order.clone(),
            selection_version: context.selection_version,
            elements_version: context.elements_version,
        }
    }

    fn matches(&self, context: &EditContext) -> bool {
        self.start_position == context.start_position
            && self.start_bounds == context.start_bounds
            && self.selected_ids_at_start == context.selected_ids_at_start
            && self.selected_ids_at_start_in_order == context.selected_ids_at_start_in_order
            && self.selection_version == context.selection_version
            && self.elements_version == context.elements_version
    }
}

#[derive(Clone, Debug)]
struct ResizeOperationSession {
    context_fingerprint: ResizeContextFingerprint,
    resize_mode: ResizeMode,
    handle_offset: DrawPoint,
    rotation: f64,
    selection_padding: f64,
    element_snapshots: HashMap<String, ElementResizeSnapshot>,
    reference_elements: Vec<ResizeReferenceElement>,
    reference_element_aabbs: Vec<DrawRect>,
    force_serial_number_aspect_ratio: bool,
    text_metrics_service: Arc<dyn TextMetricsService>,
}

impl ResizeOperationSession {
    fn from_context(context: &EditContext) -> Self {
        Self {
            context_fingerprint: ResizeContextFingerprint::from_context(context),
            resize_mode: ResizeMode::BottomRight,
            handle_offset: DrawPoint::ZERO,
            rotation: 0.0,
            selection_padding: DEFAULT_SELECTION_PADDING,
            element_snapshots: HashMap::new(),
            reference_elements: Vec::new(),
            reference_element_aabbs: Vec::new(),
            force_serial_number_aspect_ratio: false,
            text_metrics_service: default_text_metrics_service(),
        }
    }

    fn to_resize_edit_context(&self, base: EditContext) -> ResizeEditContext {
        let mut context = ResizeEditContext::new(
            base,
            self.resize_mode,
            self.handle_offset,
            self.rotation,
            self.element_snapshots.clone(),
        );
        context.selection_padding = self.selection_padding;
        context.reference_elements = self.reference_elements.clone();
        context.reference_element_aabbs = self.reference_element_aabbs.clone();
        context.force_serial_number_aspect_ratio = self.force_serial_number_aspect_ratio;
        context.text_metrics_service = self.text_metrics_service.clone();
        context
    }
}

/// Translation of Dart `ResizeOperation`.
#[derive(Debug, Default)]
pub struct ResizeOperation {
    session: Mutex<Option<ResizeOperationSession>>,
}

impl ResizeOperation {
    pub fn new() -> Self {
        Self::default()
    }

    fn replace_session(&self, session: Option<ResizeOperationSession>) {
        let mut guard = self
            .session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        *guard = session;
    }

    fn resolve_session(&self, context: &EditContext) -> ResizeOperationSession {
        let guard = self
            .session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());

        if let Some(cached) = guard.as_ref() {
            if cached.context_fingerprint.matches(context) {
                return cached.clone();
            }
        }

        ResizeOperationSession::from_context(context)
    }

    fn resolve_start_bounds(
        &self,
        params: ResizeOperationParams,
        pointer_position: DrawPoint,
    ) -> DrawRect {
        params
            .initial_selection_bounds
            .unwrap_or_else(|| DrawRect::from_point(pointer_position))
    }

    fn resolve_handle_offset(
        &self,
        params: ResizeOperationParams,
        pointer_position: DrawPoint,
        start_bounds: DrawRect,
        rotation: f64,
        rotation_center: DrawPoint,
    ) -> DrawPoint {
        if let Some(offset) = params.handle_offset {
            return offset;
        }

        let overlay_space = OverlaySpace::new(rotation, rotation_center);
        let local_pointer_position = overlay_space.from_world(pointer_position);
        let handle_position = HandleCalculator::get_resize_handle_position(
            start_bounds,
            params.resize_mode,
            params.selection_padding,
        );

        DrawPoint::new(
            handle_position.x - local_pointer_position.x,
            handle_position.y - local_pointer_position.y,
        )
    }

    fn should_lock_serial_number_aspect_ratio(
        &self,
        state: &DrawState,
        selected_ids: &HashSet<String>,
    ) -> bool {
        !selected_ids.is_empty()
            && selected_ids.iter().all(|id| {
                state
                    .domain
                    .document
                    .get_element_by_id(id)
                    .is_some_and(|element| {
                        element.data.type_id().as_str() == SerialNumberData::TYPE_ID_TOKEN
                    })
            })
    }

    fn incomplete_update(&self, current_position: DrawPoint) -> EditUpdateResult<EditTransform> {
        EditUpdateResult::new(EditTransform::Resize(ResizeTransform::incomplete(
            current_position,
        )))
    }

    fn should_return_incomplete_transform(&self, context: &EditContext) -> bool {
        context.selected_ids_at_start.is_empty()
            || (context.is_multi_select()
                && (context.start_bounds.width() == 0.0 || context.start_bounds.height() == 0.0))
    }

    fn should_skip_compute(&self, context: &EditContext, transform: &ResizeTransform) -> bool {
        context.selected_ids_at_start.is_empty()
            || !transform.is_complete()
            || transform.is_identity()
            || (context.is_multi_select()
                && (context.start_bounds.width() <= 0.0 || context.start_bounds.height() <= 0.0))
    }

    fn resolve_anchors(&self, mode: ResizeMode) -> AxisAnchors {
        match mode {
            ResizeMode::TopLeft => AxisAnchors {
                x: vec![SnapAxisAnchor::Start],
                y: vec![SnapAxisAnchor::Start],
            },
            ResizeMode::Top => AxisAnchors {
                x: Vec::new(),
                y: vec![SnapAxisAnchor::Start],
            },
            ResizeMode::TopRight => AxisAnchors {
                x: vec![SnapAxisAnchor::End],
                y: vec![SnapAxisAnchor::Start],
            },
            ResizeMode::Right => AxisAnchors {
                x: vec![SnapAxisAnchor::End],
                y: Vec::new(),
            },
            ResizeMode::BottomRight => AxisAnchors {
                x: vec![SnapAxisAnchor::End],
                y: vec![SnapAxisAnchor::End],
            },
            ResizeMode::Bottom => AxisAnchors {
                x: Vec::new(),
                y: vec![SnapAxisAnchor::End],
            },
            ResizeMode::BottomLeft => AxisAnchors {
                x: vec![SnapAxisAnchor::Start],
                y: vec![SnapAxisAnchor::End],
            },
            ResizeMode::Left => AxisAnchors {
                x: vec![SnapAxisAnchor::Start],
                y: Vec::new(),
            },
        }
    }

    fn resolve_snapped_bounds(
        &self,
        state: &DrawState,
        session: &ResizeOperationSession,
        modifiers: EditModifiers,
        config: &DrawConfig,
        maintain_aspect_ratio: bool,
        bounds: DrawRect,
        anchors_x: &[SnapAxisAnchor],
        anchors_y: &[SnapAxisAnchor],
    ) -> SnappedBoundsResult {
        let can_snap = session.rotation == 0.0 && !modifiers.from_center;
        if !can_snap {
            return Self::unsnapped(bounds);
        }

        let snapping_mode =
            resolve_effective_snapping_mode_for_config(config, modifiers.snap_override);
        let snap_min_x = anchors_x.contains(&SnapAxisAnchor::Start);
        let snap_max_x = anchors_x.contains(&SnapAxisAnchor::End);
        let snap_min_y = anchors_y.contains(&SnapAxisAnchor::Start);
        let snap_max_y = anchors_y.contains(&SnapAxisAnchor::End);

        if snapping_mode == SnappingMode::Grid && !maintain_aspect_ratio {
            let snapped = GRID_SNAP_SERVICE.snap_rect(
                bounds,
                config.grid.size,
                snap_min_x,
                snap_max_x,
                snap_min_y,
                snap_max_y,
            );
            return SnappedBoundsResult {
                bounds: snapped,
                guides: Vec::new(),
            };
        }

        let should_object_snap = snapping_mode == SnappingMode::Object
            && config.snap.enable_point_snaps
            && !session.reference_elements.is_empty();
        if !should_object_snap {
            return Self::unsnapped(bounds);
        }

        let _snap_distance =
            resolve_zoom_adjusted_distance(config.snap.distance, self.resolve_zoom(state));
        let target_anchors_x = to_object_snap_anchors(anchors_x);
        let target_anchors_y = to_object_snap_anchors(anchors_y);
        let snap_result = OBJECT_SNAP_SERVICE.snap_resize(
            bounds,
            &session.reference_elements,
            _snap_distance,
            &target_anchors_x,
            &target_anchors_y,
            Some(session.reference_element_aabbs.as_slice()),
            config.snap.enable_point_snaps,
        );

        let snapped_bounds = if snap_result.has_snap() {
            DrawRect::new(
                bounds.min_x + if snap_min_x { snap_result.dx } else { 0.0 },
                bounds.min_y + if snap_min_y { snap_result.dy } else { 0.0 },
                bounds.max_x + if snap_max_x { snap_result.dx } else { 0.0 },
                bounds.max_y + if snap_max_y { snap_result.dy } else { 0.0 },
            )
        } else {
            bounds
        };

        SnappedBoundsResult {
            bounds: snapped_bounds,
            guides: if config.snap.show_guides {
                snap_result.guides
            } else {
                Vec::new()
            },
        }
    }

    fn resolve_zoom(&self, state: &DrawState) -> f64 {
        state.application.view.camera.zoom
    }

    fn unsnapped(bounds: DrawRect) -> SnappedBoundsResult {
        SnappedBoundsResult {
            bounds,
            guides: Vec::new(),
        }
    }
}

impl EditOperation for ResizeOperation {
    fn id(&self) -> EditOperationId {
        EditOperationIds::RESIZE
    }

    fn create_history_metadata(
        &self,
        context: &EditContext,
        _transform: &EditTransform,
    ) -> HistoryMetadata {
        HistoryMetadata::for_resize(context.selected_ids_at_start.clone())
    }

    fn create_context(
        &self,
        state: &DrawState,
        position: DrawPoint,
        params: &EditOperationParams,
    ) -> EditContext {
        let typed_params = ResizeOperationParams::from_base(params);
        let selection_data = SelectionDataComputer::compute(state);
        let selected_ids_at_start = state
            .domain
            .selection
            .selected_ids
            .iter()
            .cloned()
            .collect::<HashSet<_>>();
        let start_bounds = typed_params
            .initial_selection_bounds
            .or(selection_data.overlay_bounds)
            .or(selection_data.selection_bounds)
            .unwrap_or_else(|| self.resolve_start_bounds(typed_params, position));

        let rotation = selection_data.overlay_rotation.unwrap_or(0.0);
        let rotation_center = selection_data
            .overlay_center
            .unwrap_or_else(|| start_bounds.center());
        let handle_offset = self.resolve_handle_offset(
            typed_params,
            position,
            start_bounds,
            rotation,
            rotation_center,
        );
        let element_snapshots = selection_data
            .selected_elements
            .iter()
            .map(|element| {
                (
                    element.id.clone(),
                    ElementResizeSnapshot {
                        rect: element.rect,
                        rotation: element.rotation,
                    },
                )
            })
            .collect::<HashMap<_, _>>();
        let reference_elements = resolve_reference_elements(state, &selected_ids_at_start);
        let reference_element_aabbs = ObjectSnapService::build_reference_aabbs(&reference_elements);
        let force_serial_number_aspect_ratio =
            self.should_lock_serial_number_aspect_ratio(state, &selected_ids_at_start);

        let selected_ids_at_start_in_order = selection_data
            .selected_elements
            .iter()
            .map(|element| element.id.clone())
            .collect::<Vec<_>>();
        let context = EditContext::new_with_order(
            position,
            start_bounds,
            selected_ids_at_start,
            selected_ids_at_start_in_order,
            state.domain.selection.selection_version as i64,
            state.domain.document.elements_version,
        );

        let session = ResizeOperationSession {
            context_fingerprint: ResizeContextFingerprint::from_context(&context),
            resize_mode: typed_params.resize_mode,
            handle_offset,
            rotation,
            selection_padding: typed_params.selection_padding,
            element_snapshots,
            reference_elements,
            reference_element_aabbs,
            force_serial_number_aspect_ratio,
            text_metrics_service: default_text_metrics_service(),
        };
        self.replace_session(Some(session));

        context
    }

    fn attach_text_metrics_service(
        &self,
        context: &EditContext,
        text_metrics_service: Arc<dyn TextMetricsService>,
    ) {
        let mut guard = self
            .session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let Some(cached) = guard.as_mut() else {
            return;
        };
        if cached.context_fingerprint.matches(context) {
            cached.text_metrics_service = text_metrics_service;
        }
    }

    fn initial_transform(
        &self,
        _state: &DrawState,
        _context: &EditContext,
        start_position: DrawPoint,
    ) -> EditTransform {
        EditTransform::Resize(ResizeTransform::incomplete(start_position))
    }

    fn update(
        &self,
        state: &DrawState,
        context: &EditContext,
        _transform: &EditTransform,
        current_position: DrawPoint,
        modifiers: EditModifiers,
        config: &DrawConfig,
    ) -> EditUpdateResult<EditTransform> {
        if self.should_return_incomplete_transform(context) {
            return self.incomplete_update(current_position);
        }

        let session = self.resolve_session(context);
        let start_bounds = context.start_bounds;
        let transform_context =
            EditTransformContext::new(start_bounds, session.rotation, start_bounds.center());
        let maintain_aspect_ratio =
            modifiers.maintain_aspect_ratio || session.force_serial_number_aspect_ratio;

        let bounds_result = calculate_resize_bounds(ResizeBoundsParams {
            transform_context,
            mode: session.resize_mode,
            current_pointer_world: current_position,
            handle_offset_local: session.handle_offset,
            selection_padding: session.selection_padding,
            maintain_aspect_ratio,
            resize_from_center: modifiers.from_center,
        });

        let anchors = self.resolve_anchors(session.resize_mode);
        let snapped_result = self.resolve_snapped_bounds(
            state,
            &session,
            modifiers,
            config,
            maintain_aspect_ratio,
            bounds_result.bounds,
            anchors.x.as_slice(),
            anchors.y.as_slice(),
        );

        let scales = ResizeGeometry::calculate_scale(
            start_bounds,
            snapped_result.bounds,
            bounds_result.flip_x,
            bounds_result.flip_y,
        );

        let anchor = if modifiers.from_center {
            start_bounds.center()
        } else {
            opposite_bound_point_local(start_bounds, session.resize_mode)
        };

        let next_transform = ResizeTransform::complete(
            current_position,
            snapped_result.bounds,
            scales.scale_x,
            scales.scale_y,
            anchor,
        );

        EditUpdateResult::with_snap_guides(
            EditTransform::Resize(next_transform),
            snapped_result.guides,
        )
    }

    fn finish(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> DrawState {
        self.finish_standard(state, context, transform)
    }

    fn build_preview(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> EditPreview {
        self.build_preview_standard(state, context, transform)
    }
}

impl StandardFinishMixin for ResizeOperation {
    fn compute_result(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> Option<EditComputedResult> {
        let EditTransform::Resize(typed_transform) = transform else {
            return None;
        };
        if self.should_skip_compute(context, typed_transform) {
            return None;
        }

        let new_selection_bounds = typed_transform.new_selection_bounds?;
        let scale_x = typed_transform.scale_x?;
        let scale_y = typed_transform.scale_y?;
        let anchor = typed_transform.anchor?;

        let session = self.resolve_session(context);
        let resize_context = session.to_resize_edit_context(context.clone());

        let current_elements_by_id = state.domain.document.element_map();
        let updated_by_id = EditApply::apply_resize_to_elements(
            &session.element_snapshots,
            &context.selected_ids_at_start,
            &resize_context,
            new_selection_bounds,
            scale_x,
            scale_y,
            anchor,
            &current_elements_by_id,
        );

        if updated_by_id.is_empty() {
            return None;
        }

        let multi_select_bounds = if context.is_multi_select() {
            Some(new_selection_bounds)
        } else {
            None
        };
        let ordered_element_ids = ordered_element_ids_from_element_map(&current_elements_by_id);

        finalize_domain_result(
            &current_elements_by_id,
            updated_by_id,
            ordered_element_ids.as_slice(),
            multi_select_bounds,
            None,
            None,
        )
    }

    fn update_overlay(
        &self,
        current: SelectionOverlayState,
        result: &EditComputedResult,
        context: &EditContext,
    ) -> SelectionOverlayState {
        if !context.is_multi_select() {
            return current;
        }

        match result.multi_select_bounds {
            Some(new_bounds) => {
                let rotation = current
                    .multi_select_overlay
                    .map(|overlay| overlay.rotation)
                    .unwrap_or(0.0);
                current.copy_with(
                    Some(MultiSelectOverlayState::with_rotation(new_bounds, rotation)),
                    false,
                )
            }
            None => current,
        }
    }
}

fn to_object_snap_anchors(anchors: &[SnapAxisAnchor]) -> Vec<ObjectSnapAxisAnchor> {
    anchors
        .iter()
        .map(|anchor| match anchor {
            SnapAxisAnchor::Start => ObjectSnapAxisAnchor::Start,
            SnapAxisAnchor::End => ObjectSnapAxisAnchor::End,
        })
        .collect()
}
