#![allow(dead_code)]
#![allow(unused_imports)]
#![allow(unused_variables)]

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use crate::draw::config::draw_config::{DrawConfig, SnapConfig};
use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::core::creation_strategy::{
    snap_creation_point, CreatingState, CreationFinishResult, CreationMode, CreationStrategy,
    CreationUpdateResult, DrawState, ElementData, ElementState as CreationElementState,
    PointCreationMode, PointCreationStrategy,
};
use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding as DomainLineBinding, ArrowBindingMode as DomainLineBindingMode,
};
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding as DomainArrowBinding, ArrowBindingMode as DomainArrowBindingMode,
    ArrowData as DomainArrowData, ArrowDataPatch as DomainArrowDataPatch,
    NullableField as DomainArrowNullableField,
};
use crate::draw::elements::types::arrow::arrow_like_data::NullableField as DomainArrowLikeNullableField;
use crate::draw::elements::types::arrow::elbow::elbow_fixed_segment::ElbowFixedSegment as DomainLineFixedSegment;
use crate::draw::elements::types::arrow::elbow::elbow_router;
use crate::draw::elements::types::line::line_data::{
    LineData as DomainLineData, LineDataPatch as DomainLineDataPatch,
};
use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::element_state::ElementState as DomainElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::{default_text_metrics_service, TextMetricsService};
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};
use crate::draw::types::snap_guides::SnapGuide;
use crate::draw::utils::camera_zoom::resolve_zoom_adjusted_distance;
use crate::draw::utils::snapping_mode::SnappingMode;

const LOOP_CLOSE_TOLERANCE_MULTIPLIER: f64 = 1.5;
const POINT_EPSILON: f64 = 1e-9;

/// Creation strategy for arrow-like elements (single and multi-point).
///
/// This mirrors the Dart behavior of `ArrowCreationStrategy` while staying
/// compile-friendly during the ongoing Rust model/service translation.
#[derive(Debug, Default, Clone, Copy)]
pub struct ArrowCreationStrategy;

impl ArrowCreationStrategy {
    pub const fn new() -> Self {
        Self
    }
}

impl PointCreationStrategy for ArrowCreationStrategy {}

impl CreationStrategy for ArrowCreationStrategy {
    fn start(
        &self,
        data: Arc<dyn ElementData>,
        start_position: DrawPoint,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        let _ = text_metrics_service.unwrap_or_else(default_text_metrics_service);

        let data_ref = resolve_arrow_like_data(&data, "ArrowCreationStrategy.start");
        let arrow_rect =
            calculate_arrow_rect(&[start_position, start_position], data_ref.arrow_type());
        let normalized_points =
            ArrowGeometry::normalize_points(&[start_position, start_position], arrow_rect);
        let updated_data = data_ref.copy_with(Some(normalized_points), None, None);

        CreationUpdateResult::new(
            updated_data,
            arrow_rect,
            CreationMode::Point(PointCreationMode {
                fixed_points: vec![start_position],
                current_point: Some(start_position),
            }),
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
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        let _ = text_metrics_service.unwrap_or_else(default_text_metrics_service);
        let data_ref = resolve_arrow_like_data(
            creating_state.element_data_ref(),
            "ArrowCreationStrategy.update",
        );

        with_creation_session_data(&creating_state.element.id, |session_data| {
            if data_ref.is_line() {
                return update_line(
                    state,
                    config,
                    creating_state,
                    current_position,
                    snapping_mode,
                    &data_ref,
                    session_data,
                );
            }

            let endpoints = resolve_creation_endpoints(
                state,
                config,
                creating_state,
                data_ref.arrow_type(),
                data_ref.start_arrowhead(),
                data_ref.start_binding(),
                current_position,
                snapping_mode,
                session_data,
            );
            let mut adjusted_current = endpoints.current_position;

            let binding_result = snap_binding_point(
                state,
                config,
                adjusted_current,
                snapping_mode,
                data_ref.arrow_type(),
                data_ref.end_arrowhead(),
                data_ref.end_binding(),
                Some(endpoints.segment_start),
                Some(&mut session_data.end_target_cache),
                ArrowBindingCachePolicy::DefaultPolicy,
            );
            adjusted_current = binding_result.position;
            let mut end_binding = binding_result.binding;

            let close_tolerance =
                config.selection.interaction.handle_tolerance * LOOP_CLOSE_TOLERANCE_MULTIPLIER;
            if data_ref.arrow_type() != ArrowType::Elbow && endpoints.fixed_points.len() >= 2 {
                let start_point = endpoints.fixed_points[0];
                if adjusted_current.distance_squared(start_point)
                    <= close_tolerance * close_tolerance
                {
                    adjusted_current = start_point;
                    end_binding = endpoints.start_binding.clone();
                }
            }

            let all_points = append_current_point(&endpoints.fixed_points, adjusted_current);
            let (arrow_rect, normalized_points) = if data_ref.arrow_type() == ArrowType::Elbow {
                let routed_points = route_elbow_arrow(
                    state,
                    endpoints.start_position,
                    adjusted_current,
                    endpoints.start_binding.clone(),
                    end_binding.clone(),
                    data_ref.start_arrowhead(),
                    data_ref.end_arrowhead(),
                )
                .points;
                let rect = calculate_arrow_rect(&routed_points, data_ref.arrow_type());
                let normalized = ArrowGeometry::normalize_points(&routed_points, rect);
                (rect, normalized)
            } else if endpoints.fixed_points.len() == 1 {
                let layout =
                    compute_arrow_two_point_layout(endpoints.fixed_points[0], adjusted_current);
                (layout.rect, layout.normalized_points)
            } else {
                let rect = calculate_arrow_rect(&all_points, data_ref.arrow_type());
                let normalized = ArrowGeometry::normalize_points(&all_points, rect);
                (rect, normalized)
            };

            let updated_data = data_ref.copy_with(
                Some(normalized_points),
                Some(endpoints.start_binding.clone()),
                Some(end_binding.clone()),
            );

            let fixed_points = if data_ref.arrow_type() == ArrowType::Elbow {
                vec![endpoints.start_position]
            } else {
                endpoints.fixed_points
            };

            CreationUpdateResult::new(
                updated_data,
                arrow_rect,
                CreationMode::Point(PointCreationMode {
                    fixed_points,
                    current_point: Some(adjusted_current),
                }),
                endpoints.snap_guides,
            )
        })
    }

    fn add_point(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        position: DrawPoint,
        snapping_mode: SnappingMode,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> Option<CreationUpdateResult> {
        let _ = text_metrics_service.unwrap_or_else(default_text_metrics_service);
        if !is_point_creation(creating_state) {
            return None;
        }

        let data_ref = resolve_arrow_like_data(
            creating_state.element_data_ref(),
            "ArrowCreationStrategy.addPoint",
        );
        if data_ref.arrow_type() == ArrowType::Elbow {
            return None;
        }

        with_creation_session_data(&creating_state.element.id, |session_data| {
            let endpoints = resolve_creation_endpoints(
                state,
                config,
                creating_state,
                data_ref.arrow_type(),
                data_ref.start_arrowhead(),
                data_ref.start_binding(),
                position,
                snapping_mode,
                session_data,
            );
            let mut adjusted_position = endpoints.current_position;

            let binding_result = snap_binding_point(
                state,
                config,
                adjusted_position,
                snapping_mode,
                data_ref.arrow_type(),
                data_ref.end_arrowhead(),
                data_ref.end_binding(),
                Some(endpoints.segment_start),
                Some(&mut session_data.end_target_cache),
                ArrowBindingCachePolicy::DefaultPolicy,
            );
            adjusted_position = binding_result.position;

            let mut updated_fixed_points = endpoints.fixed_points;
            if updated_fixed_points
                .last()
                .copied()
                .map(|point| point != adjusted_position)
                .unwrap_or(true)
            {
                updated_fixed_points.push(adjusted_position);
            }
            updated_fixed_points =
                apply_bound_start_to_fixed_points(updated_fixed_points, endpoints.start_position);

            let all_points = append_current_point(&updated_fixed_points, adjusted_position);
            let arrow_rect = calculate_arrow_rect(&all_points, data_ref.arrow_type());
            let normalized_points = ArrowGeometry::normalize_points(&all_points, arrow_rect);
            let updated_data = data_ref.copy_with(
                Some(normalized_points),
                Some(endpoints.start_binding),
                Some(binding_result.binding),
            );

            Some(CreationUpdateResult::new(
                updated_data,
                arrow_rect,
                CreationMode::Point(PointCreationMode {
                    fixed_points: updated_fixed_points,
                    current_point: Some(adjusted_position),
                }),
                endpoints.snap_guides,
            ))
        })
    }

    fn finish(
        &self,
        config: &DrawConfig,
        creating_state: &CreatingState,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationFinishResult {
        let _ = text_metrics_service.unwrap_or_else(default_text_metrics_service);
        let data_ref = resolve_arrow_like_data(
            creating_state.element_data_ref(),
            "ArrowCreationStrategy.finish",
        );

        let min_size = config.element.min_create_size;
        let finish_tolerance = config.selection.interaction.handle_tolerance;
        let world_points =
            ArrowGeometry::resolve_world_points(creating_state.current_rect, data_ref.points());
        let final_points =
            if data_ref.arrow_type() == ArrowType::Elbow || !is_point_creation(creating_state) {
                world_points
            } else {
                resolve_final_arrow_points(creating_state, finish_tolerance)
            };
        let close_tolerance = finish_tolerance * LOOP_CLOSE_TOLERANCE_MULTIPLIER;
        let closed_points = if data_ref.arrow_type() == ArrowType::Elbow {
            final_points
        } else {
            close_if_needed(final_points, close_tolerance)
        };

        clear_creation_session_data(&creating_state.element.id);

        if closed_points.len() < 2 {
            return CreationFinishResult::new(
                creating_state.element_data(),
                creating_state.current_rect,
                false,
            );
        }

        let arrow_rect = calculate_arrow_rect(&closed_points, data_ref.arrow_type());
        let normalized_points = ArrowGeometry::normalize_points(&closed_points, arrow_rect);
        let updated_data = data_ref.copy_with(Some(normalized_points), None, None);

        let length = ArrowGeometry::calculate_shaft_length(&closed_points, data_ref.arrow_type());
        if !length.is_finite() || length < min_size {
            return CreationFinishResult::new(
                creating_state.element_data(),
                creating_state.current_rect,
                false,
            );
        }

        CreationFinishResult::new(updated_data, arrow_rect, true)
    }
}

fn update_line(
    state: &DrawState,
    config: &DrawConfig,
    creating_state: &CreatingState,
    current_position: DrawPoint,
    snapping_mode: SnappingMode,
    data_ref: &ArrowLikeDataRef<'_>,
    session_data: &mut ArrowCreationSessionData,
) -> CreationUpdateResult {
    let endpoints = resolve_creation_endpoints(
        state,
        config,
        creating_state,
        data_ref.arrow_type(),
        data_ref.start_arrowhead(),
        data_ref.start_binding(),
        current_position,
        snapping_mode,
        session_data,
    );
    let mut adjusted_current = endpoints.current_position;

    let binding_result = snap_binding_point(
        state,
        config,
        adjusted_current,
        snapping_mode,
        data_ref.arrow_type(),
        data_ref.end_arrowhead(),
        data_ref.end_binding(),
        Some(endpoints.segment_start),
        Some(&mut session_data.end_target_cache),
        ArrowBindingCachePolicy::DefaultPolicy,
    );
    adjusted_current = binding_result.position;
    let mut end_binding = binding_result.binding;

    let close_tolerance =
        config.selection.interaction.handle_tolerance * LOOP_CLOSE_TOLERANCE_MULTIPLIER;
    if endpoints.fixed_points.len() >= 2 {
        let first_point = endpoints.fixed_points[0];
        if adjusted_current.distance_squared(first_point) <= close_tolerance * close_tolerance {
            adjusted_current = first_point;
            end_binding = endpoints.start_binding.clone();
        }
    }

    let (line_rect, normalized_points) = if endpoints.fixed_points.len() == 1 {
        let layout = compute_arrow_two_point_layout(endpoints.fixed_points[0], adjusted_current);
        (layout.rect, layout.normalized_points)
    } else {
        let world_points = append_current_point(&endpoints.fixed_points, adjusted_current);
        let rect = calculate_arrow_rect(&world_points, data_ref.arrow_type());
        let normalized = ArrowGeometry::normalize_points(&world_points, rect);
        (rect, normalized)
    };

    let updated_data = data_ref.copy_with(
        Some(normalized_points),
        Some(endpoints.start_binding),
        Some(end_binding),
    );

    CreationUpdateResult::new(
        updated_data,
        line_rect,
        CreationMode::Point(PointCreationMode {
            fixed_points: endpoints.fixed_points,
            current_point: Some(adjusted_current),
        }),
        endpoints.snap_guides,
    )
}

fn resolve_creation_endpoints(
    state: &DrawState,
    config: &DrawConfig,
    creating_state: &CreatingState,
    arrow_type: ArrowType,
    start_arrowhead: ArrowheadStyle,
    preferred_start_binding: Option<ArrowBinding>,
    current_position: DrawPoint,
    snapping_mode: SnappingMode,
    session_data: &mut ArrowCreationSessionData,
) -> CreationEndpointResolution {
    let mut start_position =
        snap_point_to_grid_if_needed(creating_state.start_position, config, snapping_mode);
    let mut adjusted_current =
        snap_point_to_grid_if_needed(current_position, config, snapping_mode);

    let start_binding_result = resolve_start_binding_point(
        state,
        config,
        start_position,
        snapping_mode,
        arrow_type,
        start_arrowhead,
        preferred_start_binding,
        adjusted_current,
        session_data,
        ArrowBindingCachePolicy::DefaultPolicy,
    );
    start_position = start_binding_result.position;

    let fixed_points =
        apply_bound_start_to_fixed_points(resolve_fixed_points(creating_state), start_position);
    let segment_start = fixed_points.last().copied().unwrap_or(start_position);
    let snap_result =
        snap_create_point(state, config, adjusted_current, snapping_mode, session_data);
    adjusted_current = snap_result.position;

    CreationEndpointResolution {
        start_position,
        fixed_points,
        segment_start,
        current_position: adjusted_current,
        start_binding: start_binding_result.binding,
        snap_guides: snap_result.guides,
    }
}

fn snap_point_to_grid_if_needed(
    point: DrawPoint,
    config: &DrawConfig,
    snapping_mode: SnappingMode,
) -> DrawPoint {
    snap_creation_point(point, config, snapping_mode)
}

/// Calculates arrow bounds. Curved and elbow arrows currently use point-cloud
/// bounds until their dedicated geometry services are translated.
fn calculate_arrow_rect(points: &[DrawPoint], arrow_type: ArrowType) -> DrawRect {
    ArrowGeometry::calculate_path_bounds(points, arrow_type)
}

fn append_current_point(fixed_points: &[DrawPoint], current_point: DrawPoint) -> Vec<DrawPoint> {
    if fixed_points.is_empty() {
        return vec![current_point];
    }
    if fixed_points.last().copied() == Some(current_point) {
        return fixed_points.to_vec();
    }
    let mut points = fixed_points.to_vec();
    points.push(current_point);
    points
}

fn resolve_final_arrow_points(
    interaction: &CreatingState,
    finish_tolerance: f64,
) -> Vec<DrawPoint> {
    let mut points = resolve_fixed_points(interaction);
    let current_point = resolve_current_point(interaction);
    let Some(current_point) = current_point else {
        return points;
    };
    if points.is_empty() {
        points.push(current_point);
        return points;
    }

    let last_point = *points.last().unwrap_or(&current_point);
    if last_point == current_point {
        return points;
    }

    // Avoid creating an extra tiny segment when finishing multi-point arrows.
    if points.len() >= 2
        && last_point.distance_squared(current_point) <= finish_tolerance * finish_tolerance
    {
        return points;
    }

    points.push(current_point);
    points
}

fn close_if_needed(points: Vec<DrawPoint>, close_tolerance: f64) -> Vec<DrawPoint> {
    if points.len() < 3 {
        return points;
    }
    let first = points[0];
    let last = *points.last().unwrap_or(&first);
    if first == last {
        return points;
    }
    if first.distance_squared(last) <= close_tolerance * close_tolerance {
        let mut closed = points;
        if let Some(last_point) = closed.last_mut() {
            *last_point = first;
        }
        return closed;
    }
    points
}

fn snap_create_point(
    state: &DrawState,
    config: &DrawConfig,
    position: DrawPoint,
    snapping_mode: SnappingMode,
    session_data: &mut ArrowCreationSessionData,
) -> PointSnapResult {
    if snapping_mode != SnappingMode::Object {
        return PointSnapResult::new(position, Vec::new());
    }

    let snap_config = &config.snap;
    if !snap_config.enable_point_snaps && !snap_config.enable_gap_snaps {
        return PointSnapResult::new(position, Vec::new());
    }

    let reference_elements = session_data.resolve_reference_elements(state);
    if reference_elements.is_empty() {
        return PointSnapResult::new(position, Vec::new());
    }

    let reference_aabbs = session_data.resolve_reference_element_aabbs(state, &reference_elements);
    let snap_distance =
        resolve_zoom_adjusted_distance(snap_config.distance, resolve_view_zoom(state));
    if snap_distance <= 0.0 {
        return PointSnapResult::new(position, Vec::new());
    }

    let result = snap_point_against_reference_aabbs(
        position,
        &reference_aabbs,
        snap_distance,
        snap_config.enable_point_snaps,
        snap_config.enable_gap_snaps,
    );
    let snapped_position = if result.has_snap() {
        position.copy_with(
            Some(position.x + result.dx),
            Some(position.y + result.dy),
            None,
            None,
        )
    } else {
        position
    };
    let guides = if snap_config.show_guides {
        result.guides
    } else {
        Vec::new()
    };
    PointSnapResult::new(snapped_position, guides)
}

#[allow(clippy::too_many_arguments)]
fn snap_binding_point(
    state: &DrawState,
    config: &DrawConfig,
    position: DrawPoint,
    snapping_mode: SnappingMode,
    arrow_type: ArrowType,
    arrowhead_style: ArrowheadStyle,
    preferred_binding: Option<ArrowBinding>,
    reference_point: Option<DrawPoint>,
    target_cache: Option<&mut ArrowBindingTargetCache>,
    cache_policy: ArrowBindingCachePolicy,
) -> BindingSnapResult {
    let snap_config = &config.snap;
    let should_lookup_bindings =
        ArrowBindingSnapper::should_attempt_binding(snap_config, snapping_mode);
    let binding_distance = if should_lookup_bindings {
        ArrowBindingSnapper::resolve_binding_distance(state, snap_config)
    } else {
        0.0
    };

    if !should_lookup_bindings || binding_distance <= 0.0 {
        if let Some(cache) = target_cache {
            cache.reset();
        }
        return BindingSnapResult::new(position, None);
    }

    let candidate = ArrowBindingSnapper::resolve_endpoint_binding_candidate(
        state,
        position,
        arrow_type,
        arrowhead_style,
        should_lookup_bindings,
        binding_distance,
        true,
        resolve_has_bindable_targets(state),
        preferred_binding,
        reference_point,
        target_cache,
        cache_policy,
    );
    let Some(candidate) = candidate else {
        return BindingSnapResult::new(position, None);
    };

    BindingSnapResult::new(candidate.snap_point, Some(candidate.binding))
}

#[allow(clippy::too_many_arguments)]
fn resolve_start_binding_point(
    state: &DrawState,
    config: &DrawConfig,
    start_position: DrawPoint,
    snapping_mode: SnappingMode,
    arrow_type: ArrowType,
    arrowhead_style: ArrowheadStyle,
    preferred_binding: Option<ArrowBinding>,
    reference_point: DrawPoint,
    session_data: &mut ArrowCreationSessionData,
    cache_policy: ArrowBindingCachePolicy,
) -> BindingSnapResult {
    let snap_config = &config.snap;
    let binding_enabled = ArrowBindingSnapper::should_attempt_binding(snap_config, snapping_mode);
    let binding_distance = if binding_enabled {
        ArrowBindingSnapper::resolve_binding_distance(state, snap_config)
    } else {
        0.0
    };
    let elements_version = resolve_elements_version(state);

    if session_data.can_reuse_start_binding(
        start_position,
        preferred_binding.as_ref(),
        snapping_mode,
        elements_version,
        binding_enabled,
        binding_distance,
    ) {
        if let Some(cached) = session_data.resolve_cached_start_binding(start_position) {
            return cached;
        }
    }

    let resolved = snap_binding_point(
        state,
        config,
        start_position,
        snapping_mode,
        arrow_type,
        arrowhead_style,
        preferred_binding.clone(),
        Some(reference_point),
        Some(&mut session_data.start_target_cache),
        cache_policy,
    );
    session_data.cache_start_binding(
        start_position,
        preferred_binding,
        snapping_mode,
        elements_version,
        binding_enabled,
        binding_distance,
        &resolved,
    );
    resolved
}

#[derive(Debug, Clone)]
struct ArrowCreationSessionData {
    start_target_cache: ArrowBindingTargetCache,
    end_target_cache: ArrowBindingTargetCache,
    cached_start_position: Option<DrawPoint>,
    cached_start_preferred_binding: Option<ArrowBinding>,
    cached_start_binding: Option<ArrowBinding>,
    cached_start_snapping_mode: Option<SnappingMode>,
    cached_start_binding_enabled: Option<bool>,
    cached_start_binding_distance: Option<f64>,
    cached_start_elements_version: i64,
    reference_elements_version: i64,
    reference_elements: Vec<CreationElementState>,
    reference_aabbs_version: i64,
    reference_element_aabbs: Vec<DrawRect>,
}

impl Default for ArrowCreationSessionData {
    fn default() -> Self {
        Self {
            start_target_cache: ArrowBindingTargetCache::default(),
            end_target_cache: ArrowBindingTargetCache::default(),
            cached_start_position: None,
            cached_start_preferred_binding: None,
            cached_start_binding: None,
            cached_start_snapping_mode: None,
            cached_start_binding_enabled: None,
            cached_start_binding_distance: None,
            cached_start_elements_version: -1,
            reference_elements_version: -1,
            reference_elements: Vec::new(),
            reference_aabbs_version: -1,
            reference_element_aabbs: Vec::new(),
        }
    }
}

impl ArrowCreationSessionData {
    fn can_reuse_start_binding(
        &self,
        start_position: DrawPoint,
        preferred_binding: Option<&ArrowBinding>,
        snapping_mode: SnappingMode,
        elements_version: i64,
        binding_enabled: bool,
        binding_distance: f64,
    ) -> bool {
        self.cached_start_position == Some(start_position)
            && self.cached_start_preferred_binding.as_ref() == preferred_binding
            && self.cached_start_snapping_mode == Some(snapping_mode)
            && self.cached_start_binding_enabled == Some(binding_enabled)
            && self.cached_start_binding_distance == Some(binding_distance)
            && self.cached_start_elements_version == elements_version
    }

    fn resolve_cached_start_binding(&self, start_position: DrawPoint) -> Option<BindingSnapResult> {
        if let Some(binding) = self.cached_start_binding.clone() {
            return Some(BindingSnapResult::new(start_position, Some(binding)));
        }
        Some(BindingSnapResult::new(start_position, None))
    }

    #[allow(clippy::too_many_arguments)]
    fn cache_start_binding(
        &mut self,
        start_position: DrawPoint,
        preferred_binding: Option<ArrowBinding>,
        snapping_mode: SnappingMode,
        elements_version: i64,
        binding_enabled: bool,
        binding_distance: f64,
        result: &BindingSnapResult,
    ) {
        self.cached_start_position = Some(start_position);
        self.cached_start_preferred_binding = preferred_binding;
        self.cached_start_binding = result.binding.clone();
        self.cached_start_snapping_mode = Some(snapping_mode);
        self.cached_start_binding_enabled = Some(binding_enabled);
        self.cached_start_binding_distance = Some(binding_distance);
        self.cached_start_elements_version = elements_version;
    }

    fn resolve_reference_elements(&mut self, state: &DrawState) -> Vec<CreationElementState> {
        let elements_version = resolve_elements_version(state);
        if self.reference_elements_version == elements_version {
            return self.reference_elements.clone();
        }
        self.reference_elements_version = elements_version;
        self.reference_elements = resolve_reference_elements(state);
        self.reference_elements.clone()
    }

    fn resolve_reference_element_aabbs(
        &mut self,
        state: &DrawState,
        reference_elements: &[CreationElementState],
    ) -> Vec<DrawRect> {
        let elements_version = resolve_elements_version(state);
        if self.reference_aabbs_version == elements_version
            && self.reference_element_aabbs.len() == reference_elements.len()
        {
            return self.reference_element_aabbs.clone();
        }
        self.reference_aabbs_version = elements_version;
        self.reference_element_aabbs = reference_elements
            .iter()
            .map(|element| element.rect)
            .collect();
        self.reference_element_aabbs.clone()
    }
}

#[derive(Debug, Clone, PartialEq)]
struct CreationEndpointResolution {
    start_position: DrawPoint,
    fixed_points: Vec<DrawPoint>,
    segment_start: DrawPoint,
    current_position: DrawPoint,
    start_binding: Option<ArrowBinding>,
    snap_guides: Vec<SnapGuide>,
}

#[derive(Debug, Clone, PartialEq)]
struct PointSnapResult {
    position: DrawPoint,
    guides: Vec<SnapGuide>,
}

impl PointSnapResult {
    fn new(position: DrawPoint, guides: Vec<SnapGuide>) -> Self {
        Self { position, guides }
    }
}

#[derive(Debug, Clone, PartialEq)]
struct BindingSnapResult {
    position: DrawPoint,
    binding: Option<ArrowBinding>,
}

impl BindingSnapResult {
    fn new(position: DrawPoint, binding: Option<ArrowBinding>) -> Self {
        Self { position, binding }
    }
}

fn apply_bound_start_to_fixed_points(
    fixed_points: Vec<DrawPoint>,
    bound_start: DrawPoint,
) -> Vec<DrawPoint> {
    if fixed_points.is_empty() {
        return fixed_points;
    }
    if fixed_points[0] == bound_start {
        return fixed_points;
    }

    let mut adjusted = fixed_points;
    adjusted[0] = bound_start;
    adjusted
}

#[derive(Clone, Copy, Debug)]
enum ArrowLikeDataRef<'a> {
    Arrow(&'a ArrowLikeData),
    Line(&'a LineData),
    DomainArrow(&'a DomainArrowData),
    DomainLine(&'a DomainLineData),
}

impl<'a> ArrowLikeDataRef<'a> {
    fn is_line(&self) -> bool {
        matches!(self, Self::Line(_) | Self::DomainLine(_))
    }

    fn points(&self) -> &[DrawPoint] {
        match self {
            Self::Arrow(data) => &data.points,
            Self::Line(data) => &data.points,
            Self::DomainArrow(data) => &data.points,
            Self::DomainLine(data) => &data.points,
        }
    }

    fn arrow_type(&self) -> ArrowType {
        match self {
            Self::Arrow(data) => data.arrow_type,
            Self::Line(data) => data.arrow_type(),
            Self::DomainArrow(data) => data.arrow_type,
            Self::DomainLine(data) => data.arrow_type,
        }
    }

    fn start_arrowhead(&self) -> ArrowheadStyle {
        match self {
            Self::Arrow(data) => data.start_arrowhead,
            Self::Line(data) => data.start_arrowhead(),
            Self::DomainArrow(data) => data.start_arrowhead,
            Self::DomainLine(data) => data.start_arrowhead,
        }
    }

    fn end_arrowhead(&self) -> ArrowheadStyle {
        match self {
            Self::Arrow(data) => data.end_arrowhead,
            Self::Line(data) => data.end_arrowhead(),
            Self::DomainArrow(data) => data.end_arrowhead,
            Self::DomainLine(data) => data.end_arrowhead,
        }
    }

    fn start_binding(&self) -> Option<ArrowBinding> {
        match self {
            Self::Arrow(data) => data.start_binding.clone(),
            Self::Line(data) => data.start_binding.clone(),
            Self::DomainArrow(data) => data
                .start_binding
                .as_ref()
                .map(domain_arrow_binding_to_local),
            Self::DomainLine(data) => data
                .start_binding
                .as_ref()
                .map(domain_line_binding_to_local),
        }
    }

    fn end_binding(&self) -> Option<ArrowBinding> {
        match self {
            Self::Arrow(data) => data.end_binding.clone(),
            Self::Line(data) => data.end_binding.clone(),
            Self::DomainArrow(data) => data.end_binding.as_ref().map(domain_arrow_binding_to_local),
            Self::DomainLine(data) => data.end_binding.as_ref().map(domain_line_binding_to_local),
        }
    }

    fn copy_with(
        &self,
        points: Option<Vec<DrawPoint>>,
        start_binding: Option<Option<ArrowBinding>>,
        end_binding: Option<Option<ArrowBinding>>,
    ) -> Arc<dyn ElementData> {
        match self {
            Self::Arrow(data) => Arc::new(data.copy_with(points, start_binding, end_binding)),
            Self::Line(data) => Arc::new(data.copy_with(points, start_binding, end_binding)),
            Self::DomainArrow(data) => Arc::new(data.copy_with(DomainArrowDataPatch {
                points,
                start_binding: to_domain_arrow_nullable_binding(start_binding),
                end_binding: to_domain_arrow_nullable_binding(end_binding),
                ..DomainArrowDataPatch::default()
            })),
            Self::DomainLine(data) => Arc::new(data.copy_with(DomainLineDataPatch {
                points,
                start_binding: to_domain_line_nullable_binding(start_binding),
                end_binding: to_domain_line_nullable_binding(end_binding),
                ..DomainLineDataPatch::default()
            })),
        }
    }
}

fn resolve_arrow_like_data<'a>(
    data: &'a Arc<dyn ElementData>,
    strategy_name: &str,
) -> ArrowLikeDataRef<'a> {
    if let Some(arrow_data) = data.as_ref().as_any().downcast_ref::<ArrowLikeData>() {
        return ArrowLikeDataRef::Arrow(arrow_data);
    }
    if let Some(line_data) = data.as_ref().as_any().downcast_ref::<LineData>() {
        return ArrowLikeDataRef::Line(line_data);
    }
    if let Some(arrow_data) = data.as_ref().as_any().downcast_ref::<DomainArrowData>() {
        return ArrowLikeDataRef::DomainArrow(arrow_data);
    }
    if let Some(line_data) = data.as_ref().as_any().downcast_ref::<DomainLineData>() {
        return ArrowLikeDataRef::DomainLine(line_data);
    }
    panic!(
        "{strategy_name} expects {}, {}, {} or {} but received {}.",
        std::any::type_name::<ArrowLikeData>(),
        std::any::type_name::<LineData>(),
        std::any::type_name::<DomainArrowData>(),
        std::any::type_name::<DomainLineData>(),
        data.as_ref().runtime_type_name()
    );
}

/// Minimal arrow-like element payload used by `ArrowCreationStrategy`.
///
/// Dedicated `arrow_data.rs` / `arrow_like_data.rs` modules are still being
/// translated, so this local model preserves creation behavior in the interim.
#[derive(Clone, Debug, PartialEq)]
pub struct ArrowLikeData {
    pub points: Vec<DrawPoint>,
    pub arrow_type: ArrowType,
    pub start_arrowhead: ArrowheadStyle,
    pub end_arrowhead: ArrowheadStyle,
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
}

impl Default for ArrowLikeData {
    fn default() -> Self {
        Self {
            points: vec![DrawPoint::new(0.0, 0.0), DrawPoint::new(1.0, 1.0)],
            arrow_type: ArrowType::Straight,
            start_arrowhead: ArrowheadStyle::None,
            end_arrowhead: ArrowheadStyle::Standard,
            start_binding: None,
            end_binding: None,
        }
    }
}

impl ArrowLikeData {
    fn copy_with(
        &self,
        points: Option<Vec<DrawPoint>>,
        start_binding: Option<Option<ArrowBinding>>,
        end_binding: Option<Option<ArrowBinding>>,
    ) -> Self {
        Self {
            points: points.unwrap_or_else(|| self.points.clone()),
            arrow_type: self.arrow_type,
            start_arrowhead: self.start_arrowhead,
            end_arrowhead: self.end_arrowhead,
            start_binding: start_binding.unwrap_or_else(|| self.start_binding.clone()),
            end_binding: end_binding.unwrap_or_else(|| self.end_binding.clone()),
        }
    }
}

/// Minimal line payload implementing the arrow-like creation contract.
#[derive(Clone, Debug, PartialEq)]
pub struct LineData {
    pub points: Vec<DrawPoint>,
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
}

impl Default for LineData {
    fn default() -> Self {
        Self {
            points: vec![DrawPoint::new(0.0, 0.0), DrawPoint::new(1.0, 1.0)],
            start_binding: None,
            end_binding: None,
        }
    }
}

impl LineData {
    fn arrow_type(&self) -> ArrowType {
        ArrowType::Curved
    }

    fn start_arrowhead(&self) -> ArrowheadStyle {
        ArrowheadStyle::None
    }

    fn end_arrowhead(&self) -> ArrowheadStyle {
        ArrowheadStyle::None
    }

    fn copy_with(
        &self,
        points: Option<Vec<DrawPoint>>,
        start_binding: Option<Option<ArrowBinding>>,
        end_binding: Option<Option<ArrowBinding>>,
    ) -> Self {
        Self {
            points: points.unwrap_or_else(|| self.points.clone()),
            start_binding: start_binding.unwrap_or_else(|| self.start_binding.clone()),
            end_binding: end_binding.unwrap_or_else(|| self.end_binding.clone()),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowBinding {
    pub element_id: String,
    pub anchor: DrawPoint,
    pub mode: ArrowBindingMode,
}

impl ArrowBinding {
    pub fn new(element_id: impl Into<String>, anchor: DrawPoint, mode: ArrowBindingMode) -> Self {
        Self {
            element_id: element_id.into(),
            anchor,
            mode,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ArrowBindingMode {
    Inside,
    Orbit,
}

fn domain_arrow_binding_mode_to_local(mode: DomainArrowBindingMode) -> ArrowBindingMode {
    match mode {
        DomainArrowBindingMode::Inside => ArrowBindingMode::Inside,
        DomainArrowBindingMode::Orbit => ArrowBindingMode::Orbit,
    }
}

fn domain_line_binding_mode_to_local(mode: DomainLineBindingMode) -> ArrowBindingMode {
    match mode {
        DomainLineBindingMode::Inside => ArrowBindingMode::Inside,
        DomainLineBindingMode::Orbit => ArrowBindingMode::Orbit,
    }
}

fn local_binding_mode_to_domain_arrow(mode: ArrowBindingMode) -> DomainArrowBindingMode {
    match mode {
        ArrowBindingMode::Inside => DomainArrowBindingMode::Inside,
        ArrowBindingMode::Orbit => DomainArrowBindingMode::Orbit,
    }
}

fn local_binding_mode_to_domain_line(mode: ArrowBindingMode) -> DomainLineBindingMode {
    match mode {
        ArrowBindingMode::Inside => DomainLineBindingMode::Inside,
        ArrowBindingMode::Orbit => DomainLineBindingMode::Orbit,
    }
}

fn domain_arrow_binding_to_local(binding: &DomainArrowBinding) -> ArrowBinding {
    ArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        domain_arrow_binding_mode_to_local(binding.mode),
    )
}

fn domain_line_binding_to_local(binding: &DomainLineBinding) -> ArrowBinding {
    ArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        domain_line_binding_mode_to_local(binding.mode),
    )
}

fn local_binding_to_domain_arrow(binding: &ArrowBinding) -> DomainArrowBinding {
    DomainArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        local_binding_mode_to_domain_arrow(binding.mode),
    )
}

fn local_binding_to_domain_line(binding: &ArrowBinding) -> DomainLineBinding {
    DomainLineBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        local_binding_mode_to_domain_line(binding.mode),
    )
}

fn to_domain_arrow_nullable_binding(
    value: Option<Option<ArrowBinding>>,
) -> DomainArrowNullableField<DomainArrowBinding> {
    match value {
        None => DomainArrowNullableField::Unset,
        Some(None) => DomainArrowNullableField::Null,
        Some(Some(binding)) => {
            DomainArrowNullableField::Value(local_binding_to_domain_arrow(&binding))
        }
    }
}

fn to_domain_line_nullable_binding(
    value: Option<Option<ArrowBinding>>,
) -> DomainArrowLikeNullableField<DomainLineBinding> {
    match value {
        None => DomainArrowLikeNullableField::Unset,
        Some(None) => DomainArrowLikeNullableField::Null,
        Some(Some(binding)) => {
            DomainArrowLikeNullableField::Value(local_binding_to_domain_line(&binding))
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
struct ArrowBindingTargetCache;

impl ArrowBindingTargetCache {
    fn reset(&mut self) {}
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ArrowBindingCachePolicy {
    DefaultPolicy,
}

#[derive(Clone, Debug, PartialEq)]
struct ArrowBindingCandidate {
    snap_point: DrawPoint,
    binding: ArrowBinding,
}

struct ArrowBindingSnapper;

impl ArrowBindingSnapper {
    fn should_attempt_binding(snap_config: &SnapConfig, snapping_mode: SnappingMode) -> bool {
        snapping_mode == SnappingMode::Object
            && snap_config.enabled
            && snap_config.enable_arrow_binding
    }

    fn resolve_binding_distance(state: &DrawState, snap_config: &SnapConfig) -> f64 {
        resolve_zoom_adjusted_distance(snap_config.arrow_binding_distance, resolve_view_zoom(state))
    }

    #[allow(clippy::too_many_arguments)]
    fn resolve_endpoint_binding_candidate(
        state: &DrawState,
        world_point: DrawPoint,
        arrow_type: ArrowType,
        arrowhead_style: ArrowheadStyle,
        should_lookup_bindings: bool,
        snap_distance: f64,
        allow_new_binding: bool,
        has_bindable_targets: bool,
        preferred_binding: Option<ArrowBinding>,
        reference_point: Option<DrawPoint>,
        cache: Option<&mut ArrowBindingTargetCache>,
        cache_policy: ArrowBindingCachePolicy,
    ) -> Option<ArrowBindingCandidate> {
        let _ = cache_policy;

        if !should_lookup_bindings || snap_distance <= 0.0 {
            if let Some(cache) = cache {
                cache.reset();
            }
            return None;
        }

        if let Some(preferred) = preferred_binding.as_ref() {
            if let Some(target) = state
                .domain
                .document
                .get_element_by_id(preferred.element_id.as_str())
            {
                if target.opacity > 0.0 && is_bindable_target_element(target) {
                    let preferred_point = resolve_bound_point_for_binding(
                        target,
                        preferred,
                        arrow_type,
                        arrowhead_style,
                        reference_point,
                    );
                    let preferred_distance = preferred_point.distance(world_point);
                    let sticky_distance = snap_distance * 1.3;
                    if preferred_distance <= sticky_distance || !allow_new_binding {
                        return Some(ArrowBindingCandidate {
                            snap_point: preferred_point,
                            binding: preferred.clone(),
                        });
                    }
                }
            }
        }

        if !allow_new_binding || !has_bindable_targets {
            return None;
        }

        let mut best: Option<(f64, i64, ArrowBindingCandidate)> = None;
        for candidate in &state.domain.document.elements {
            if candidate.opacity <= 0.0 || !is_bindable_target_element(candidate) {
                continue;
            }

            let snapped = DrawPoint::new(
                world_point
                    .x
                    .clamp(candidate.rect.min_x, candidate.rect.max_x),
                world_point
                    .y
                    .clamp(candidate.rect.min_y, candidate.rect.max_y),
            );
            let distance = snapped.distance(world_point);
            if !distance.is_finite() || distance > snap_distance {
                continue;
            }

            let width = candidate.rect.width();
            let height = candidate.rect.height();
            if width.abs() <= POINT_EPSILON || height.abs() <= POINT_EPSILON {
                continue;
            }

            let local = if candidate.rotation.abs() <= POINT_EPSILON {
                snapped
            } else {
                ElementSpace::new(candidate.rotation, candidate.rect.center()).from_world(snapped)
            };
            let anchor = DrawPoint::new(
                ((local.x - candidate.rect.min_x) / width).clamp(0.0, 1.0),
                ((local.y - candidate.rect.min_y) / height).clamp(0.0, 1.0),
            );

            let candidate_binding = ArrowBindingCandidate {
                snap_point: snapped,
                binding: ArrowBinding::new(candidate.id.clone(), anchor, ArrowBindingMode::Orbit),
            };
            let is_better = match best {
                None => true,
                Some((best_distance, best_z, _)) => {
                    distance < best_distance
                        || ((distance - best_distance).abs() <= POINT_EPSILON
                            && candidate.z_index > best_z)
                }
            };
            if is_better {
                best = Some((distance, candidate.z_index, candidate_binding));
            }
        }

        if let Some(cache) = cache {
            cache.reset();
        }

        best.map(|(_, _, candidate)| candidate)
    }
}

#[derive(Clone, Debug, PartialEq)]
struct ArrowTwoPointLayout {
    rect: DrawRect,
    normalized_points: Vec<DrawPoint>,
}

fn compute_arrow_two_point_layout(first: DrawPoint, second: DrawPoint) -> ArrowTwoPointLayout {
    let rect = calculate_arrow_rect(&[first, second], ArrowType::Straight);
    let normalized_points = ArrowGeometry::normalize_points(&[first, second], rect);
    ArrowTwoPointLayout {
        rect,
        normalized_points,
    }
}

#[derive(Clone, Debug, PartialEq)]
struct ElbowRouteResult {
    points: Vec<DrawPoint>,
}

#[allow(clippy::too_many_arguments)]
fn route_elbow_arrow(
    state: &DrawState,
    start: DrawPoint,
    end: DrawPoint,
    start_binding: Option<ArrowBinding>,
    end_binding: Option<ArrowBinding>,
    start_arrowhead: ArrowheadStyle,
    end_arrowhead: ArrowheadStyle,
) -> ElbowRouteResult {
    let elements_by_id = state.domain.document.element_map();
    let start_binding = start_binding.as_ref().map(local_binding_to_domain_arrow);
    let end_binding = end_binding.as_ref().map(local_binding_to_domain_arrow);
    let routed = elbow_router::route_elbow_arrow(
        start,
        end,
        &elements_by_id,
        start_binding.as_ref(),
        end_binding.as_ref(),
        start_arrowhead,
        end_arrowhead,
    );
    ElbowRouteResult {
        points: routed.points,
    }
}

struct ArrowGeometry;

impl ArrowGeometry {
    fn normalize_points(world_points: &[DrawPoint], rect: DrawRect) -> Vec<DrawPoint> {
        let width = rect.width();
        let height = rect.height();
        world_points
            .iter()
            .map(|point| {
                let x = if width.abs() <= POINT_EPSILON {
                    0.0
                } else {
                    (point.x - rect.min_x) / width
                };
                let y = if height.abs() <= POINT_EPSILON {
                    0.0
                } else {
                    (point.y - rect.min_y) / height
                };
                point.copy_with(Some(x), Some(y), None, None)
            })
            .collect()
    }

    fn resolve_world_points(rect: DrawRect, normalized_points: &[DrawPoint]) -> Vec<DrawPoint> {
        let width = rect.width();
        let height = rect.height();
        normalized_points
            .iter()
            .map(|point| {
                let x = rect.min_x + point.x * width;
                let y = rect.min_y + point.y * height;
                point.copy_with(Some(x), Some(y), None, None)
            })
            .collect()
    }

    fn calculate_path_bounds(world_points: &[DrawPoint], _arrow_type: ArrowType) -> DrawRect {
        DrawRect::from_point_cloud(world_points.iter().copied())
    }

    fn calculate_shaft_length(points: &[DrawPoint], _arrow_type: ArrowType) -> f64 {
        if points.len() < 2 {
            return 0.0;
        }
        points
            .windows(2)
            .map(|segment| segment[0].distance(segment[1]))
            .sum()
    }
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

const REFERENCE_ANCHORS: [SnapAxisAnchor; 3] = [
    SnapAxisAnchor::Start,
    SnapAxisAnchor::Center,
    SnapAxisAnchor::End,
];

#[derive(Clone, Debug, Default, PartialEq)]
struct ObjectPointSnapResult {
    dx: f64,
    dy: f64,
    guides: Vec<SnapGuide>,
}

impl ObjectPointSnapResult {
    fn has_snap(&self) -> bool {
        self.dx != 0.0 || self.dy != 0.0
    }
}

fn snap_point_against_reference_aabbs(
    position: DrawPoint,
    reference_aabbs: &[DrawRect],
    snap_distance: f64,
    enable_point_snaps: bool,
    enable_gap_snaps: bool,
) -> ObjectPointSnapResult {
    if snap_distance <= 0.0
        || reference_aabbs.is_empty()
        || (!enable_point_snaps && !enable_gap_snaps)
    {
        return ObjectPointSnapResult::default();
    }

    // Gap snapping depends on nearest-neighbor topology that is still missing
    // in the translated object snap service.
    let _ = enable_gap_snaps;

    let dx = if enable_point_snaps {
        find_best_axis_offset(SnapAxis::X, position, reference_aabbs, snap_distance)
    } else {
        0.0
    };
    let dy = if enable_point_snaps {
        find_best_axis_offset(SnapAxis::Y, position, reference_aabbs, snap_distance)
    } else {
        0.0
    };

    ObjectPointSnapResult {
        dx,
        dy,
        guides: Vec::new(),
    }
}

fn find_best_axis_offset(
    axis: SnapAxis,
    position: DrawPoint,
    reference_aabbs: &[DrawRect],
    snap_distance: f64,
) -> f64 {
    let mut best_offset = 0.0;
    let mut best_distance = f64::INFINITY;
    let target = match axis {
        SnapAxis::X => position.x,
        SnapAxis::Y => position.y,
    };

    for rect in reference_aabbs {
        for anchor in REFERENCE_ANCHORS {
            let reference = axis_anchor_position(*rect, axis, anchor);
            let offset = reference - target;
            let distance = offset.abs();
            if distance <= snap_distance && distance < best_distance {
                best_distance = distance;
                best_offset = offset;
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

fn is_point_creation(creating_state: &CreatingState) -> bool {
    matches!(creating_state.creation_mode, CreationMode::Point(_))
}

fn resolve_fixed_points(creating_state: &CreatingState) -> Vec<DrawPoint> {
    match &creating_state.creation_mode {
        CreationMode::Point(mode) => mode.fixed_points.clone(),
        CreationMode::Rect => Vec::new(),
    }
}

fn resolve_current_point(creating_state: &CreatingState) -> Option<DrawPoint> {
    match &creating_state.creation_mode {
        CreationMode::Point(mode) => mode.current_point,
        CreationMode::Rect => None,
    }
}

fn resolve_bound_point_for_binding(
    target: &DomainElementState,
    binding: &ArrowBinding,
    arrow_type: ArrowType,
    arrowhead_style: ArrowheadStyle,
    reference_point: Option<DrawPoint>,
) -> DrawPoint {
    let _ = (arrow_type, arrowhead_style, reference_point);
    let rect = target.rect;
    let local = DrawPoint::new(
        rect.min_x + rect.width() * binding.anchor.x,
        rect.min_y + rect.height() * binding.anchor.y,
    );
    if target.rotation.abs() <= POINT_EPSILON {
        local
    } else {
        ElementSpace::new(target.rotation, rect.center()).to_world(local)
    }
}

fn is_bindable_target_element(element: &DomainElementState) -> bool {
    matches!(
        element.data.type_id().as_str(),
        RectangleData::TYPE_ID_TOKEN | TextData::TYPE_ID_TOKEN | SerialNumberData::TYPE_ID_TOKEN
    )
}

fn resolve_elements_version(state: &DrawState) -> i64 {
    state.domain.document.elements_version
}

fn resolve_view_zoom(state: &DrawState) -> f64 {
    state.application.view.camera.zoom
}

fn resolve_has_bindable_targets(state: &DrawState) -> bool {
    state
        .domain
        .document
        .elements
        .iter()
        .any(is_bindable_target_element)
}

fn resolve_reference_elements(state: &DrawState) -> Vec<CreationElementState> {
    state
        .domain
        .document
        .elements
        .iter()
        .filter(|element| element.opacity > 0.0)
        .map(|element| CreationElementState {
            id: element.id.clone(),
            type_id_value: element.type_id().as_str().to_owned(),
            rect: element.rect,
            rotation: element.rotation,
            opacity: element.opacity,
            z_index: element.z_index,
            data: Arc::new(()),
        })
        .collect()
}

fn session_store() -> &'static Mutex<HashMap<String, ArrowCreationSessionData>> {
    static STORE: OnceLock<Mutex<HashMap<String, ArrowCreationSessionData>>> = OnceLock::new();
    STORE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn with_creation_session_data<R>(
    element_id: &str,
    f: impl FnOnce(&mut ArrowCreationSessionData) -> R,
) -> R {
    let mut store = session_store()
        .lock()
        .expect("arrow creation session mutex poisoned");
    let session = store.entry(element_id.to_owned()).or_default();
    f(session)
}

fn clear_creation_session_data(element_id: &str) {
    let mut store = session_store()
        .lock()
        .expect("arrow creation session mutex poisoned");
    store.remove(element_id);
}
