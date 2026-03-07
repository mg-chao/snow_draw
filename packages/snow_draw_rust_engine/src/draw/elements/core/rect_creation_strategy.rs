#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::config::draw_config::DrawConfig;
use crate::draw::elements::core::creation_strategy::{
    finish_creation_with_current_rect, snap_creation_point, CreatingState, CreationFinishResult,
    CreationMode, CreationStrategy, CreationUpdateResult, DrawState, ElementData,
};
use crate::draw::models::element_state::ElementState as DomainElementState;
use crate::draw::services::object_snap_service::{
    ObjectSnapService, SnapAxisAnchor as ObjectSnapAxisAnchor, OBJECT_SNAP_SERVICE,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::{default_text_metrics_service, TextMetricsService};
use crate::draw::types::snap_guides::SnapGuide;
use crate::draw::utils::calculators::create_calculator::CreateCalculator;
use crate::draw::utils::camera_zoom::resolve_zoom_adjusted_distance;
use crate::draw::utils::snapping_mode::SnappingMode;
use crate::draw::utils::visible_elements::resolve_visible_elements;

const START_ANCHORS: [ObjectSnapAxisAnchor; 1] = [ObjectSnapAxisAnchor::Start];
const END_ANCHORS: [ObjectSnapAxisAnchor; 1] = [ObjectSnapAxisAnchor::End];
const REFERENCE_ANCHORS: [SnapAxisAnchor; 3] = [
    SnapAxisAnchor::Start,
    SnapAxisAnchor::Center,
    SnapAxisAnchor::End,
];

/// Default creation strategy for rect-based elements (rectangle, text, etc.).
#[derive(Debug, Default, Clone, Copy)]
pub struct RectCreationStrategy;

impl RectCreationStrategy {
    pub const fn new() -> Self {
        Self
    }
}

impl CreationStrategy for RectCreationStrategy {
    fn start(
        &self,
        data: Arc<dyn ElementData>,
        start_position: DrawPoint,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        let _ = text_metrics_service.unwrap_or_else(default_text_metrics_service);

        CreationUpdateResult::new(
            data,
            DrawRect::from_point(start_position),
            CreationMode::Rect,
            Vec::new(),
        )
    }

    fn update(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        current_position: DrawPoint,
        maintain_aspect_ratio: bool,
        create_from_center: bool,
        snapping_mode: SnappingMode,
        _snap_override_active: bool,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        let _ = text_metrics_service.unwrap_or_else(default_text_metrics_service);

        let start_position =
            snap_creation_point(creating_state.start_position, config, snapping_mode);
        let current = snap_creation_point(current_position, config, snapping_mode);
        let mut rect = CreateCalculator::calculate_create_rect(
            start_position,
            current,
            maintain_aspect_ratio,
            create_from_center,
        );

        let snap_config = &config.snap;
        let should_object_snap = snapping_mode == SnappingMode::Object
            && !create_from_center
            && (snap_config.enable_point_snaps || snap_config.enable_gap_snaps);
        if !should_object_snap {
            return CreationUpdateResult::new(
                creating_state.element_data(),
                rect,
                creating_state.creation_mode.clone(),
                Vec::new(),
            );
        }

        let snap_distance =
            resolve_zoom_adjusted_distance(snap_config.distance, resolve_view_zoom(state));
        let cached_mode = resolve_cached_snap_references(state, &creating_state.creation_mode);
        let move_min_x = current_position.x < creating_state.start_position.x;
        let move_min_y = current_position.y < creating_state.start_position.y;

        let result = snap_rect(
            rect,
            &cached_mode.reference_elements,
            snap_distance,
            if move_min_x {
                &START_ANCHORS
            } else {
                &END_ANCHORS
            },
            if move_min_y {
                &START_ANCHORS
            } else {
                &END_ANCHORS
            },
            Some(cached_mode.reference_aabbs.as_slice()),
            snap_config.enable_point_snaps,
            snap_config.enable_gap_snaps,
        );

        if result.has_snap() {
            rect = DrawRect::new(
                rect.min_x + if move_min_x { result.dx } else { 0.0 },
                rect.min_y + if move_min_y { result.dy } else { 0.0 },
                rect.max_x + if move_min_x { 0.0 } else { result.dx },
                rect.max_y + if move_min_y { 0.0 } else { result.dy },
            );
        }

        CreationUpdateResult::new(
            creating_state.element_data(),
            rect,
            creating_state.creation_mode.clone(),
            if snap_config.show_guides {
                result.guides
            } else {
                Vec::new()
            },
        )
    }

    fn finish(
        &self,
        _state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationFinishResult {
        let _ = text_metrics_service.unwrap_or_else(default_text_metrics_service);
        finish_creation_with_current_rect(config, creating_state)
    }
}

#[derive(Clone, Debug, Default)]
struct CachedRectCreationMode {
    reference_elements: Vec<DomainElementState>,
    reference_aabbs: Vec<DrawRect>,
    elements_version: i64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SnapAxis {
    X,
    Y,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SnapAxisAnchor {
    Start,
    Center,
    End,
}

#[derive(Clone, Debug, Default)]
struct RectSnapResult {
    dx: f64,
    dy: f64,
    guides: Vec<SnapGuide>,
}

impl RectSnapResult {
    fn has_snap(&self) -> bool {
        self.dx != 0.0 || self.dy != 0.0
    }
}

fn resolve_cached_snap_references(
    state: &DrawState,
    _creation_mode: &CreationMode,
) -> CachedRectCreationMode {
    let reference_elements = resolve_reference_elements(state);
    let reference_aabbs = build_reference_aabbs(&reference_elements);

    CachedRectCreationMode {
        reference_elements,
        reference_aabbs,
        elements_version: resolve_elements_version(state),
    }
}

fn resolve_reference_elements(state: &DrawState) -> Vec<DomainElementState> {
    resolve_visible_elements(state.domain.document.elements.iter().cloned(), None)
}

fn build_reference_aabbs(reference_elements: &[DomainElementState]) -> Vec<DrawRect> {
    ObjectSnapService::build_reference_aabbs(reference_elements)
}

fn resolve_elements_version(state: &DrawState) -> i64 {
    state.domain.document.elements_version
}

fn resolve_view_zoom(state: &DrawState) -> f64 {
    state.application.view.camera.zoom
}

fn snap_rect(
    target_rect: DrawRect,
    reference_elements: &[DomainElementState],
    snap_distance: f64,
    target_anchors_x: &[ObjectSnapAxisAnchor],
    target_anchors_y: &[ObjectSnapAxisAnchor],
    reference_aabbs: Option<&[DrawRect]>,
    enable_point_snaps: bool,
    enable_gap_snaps: bool,
) -> RectSnapResult {
    let result = OBJECT_SNAP_SERVICE.snap_rect(
        target_rect,
        reference_elements,
        snap_distance,
        target_anchors_x,
        target_anchors_y,
        reference_aabbs,
        enable_point_snaps,
        enable_gap_snaps,
    );

    RectSnapResult {
        dx: result.dx,
        dy: result.dy,
        guides: result.guides,
    }
}

fn find_best_axis_offset(
    axis: SnapAxis,
    target_rect: DrawRect,
    reference_aabbs: &[DrawRect],
    target_anchors: &[SnapAxisAnchor],
    snap_distance: f64,
) -> f64 {
    let mut best_offset = 0.0;
    let mut best_distance = f64::INFINITY;

    for reference_rect in reference_aabbs {
        for &target_anchor in target_anchors {
            let target = axis_anchor_position(target_rect, axis, target_anchor);
            for &reference_anchor in &REFERENCE_ANCHORS {
                let reference = axis_anchor_position(*reference_rect, axis, reference_anchor);
                let offset = reference - target;
                let distance = offset.abs();

                if distance <= snap_distance && distance < best_distance {
                    best_distance = distance;
                    best_offset = offset;
                }
            }
        }
    }

    if best_distance.is_finite() {
        best_offset
    } else {
        0.0
    }
}

fn axis_anchor_position(rect: DrawRect, axis: SnapAxis, anchor: SnapAxisAnchor) -> f64 {
    match (axis, anchor) {
        (SnapAxis::X, SnapAxisAnchor::Start) => rect.min_x,
        (SnapAxis::X, SnapAxisAnchor::Center) => rect.center_x(),
        (SnapAxis::X, SnapAxisAnchor::End) => rect.max_x,
        (SnapAxis::Y, SnapAxisAnchor::Start) => rect.min_y,
        (SnapAxis::Y, SnapAxisAnchor::Center) => rect.center_y(),
        (SnapAxis::Y, SnapAxisAnchor::End) => rect.max_y,
    }
}
