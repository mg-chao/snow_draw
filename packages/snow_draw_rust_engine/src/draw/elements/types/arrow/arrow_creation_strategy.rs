#![allow(dead_code)]
#![allow(unused_imports)]
#![allow(unused_variables)]

use std::collections::HashMap;
use std::sync::Arc;

use crate::draw::config::draw_config::DrawConfig;
use crate::draw::elements::core::creation_strategy::{
    snap_creation_point, CreatingState, CreationFinishResult, CreationMode, CreationStrategy,
    CreationUpdateResult, DrawState, ElementData, PointCreationMode, PointCreationStrategy,
};
use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding, ArrowBindingMode, ArrowBindingResult, ArrowBindingUtils,
};
use crate::draw::elements::types::arrow::arrow_binding_snapper::{
    ArrowBindingCachePolicy, ArrowBindingElement, ArrowBindingResolver as BindingResolver,
    ArrowBindingSnapper, ArrowBindingState, ArrowBindingTargetCache,
};
use crate::draw::elements::types::arrow::arrow_core::DEFAULT_MAX_COORDINATE;
use crate::draw::elements::types::arrow::arrow_core_bridge::build_core_engine_context;
use crate::draw::elements::types::arrow::arrow_core_bridge::ConnectorSourceData;
use crate::draw::elements::types::arrow::arrow_core_endpoint_drag::finalize_connector_core_endpoint_drag_result;
use crate::draw::elements::types::arrow::arrow_core_ops::{
    resolve_core_max_binding_distance, resolve_endpoint_drag_binding_enabled,
    ArrowCoreEndpointBindingOptions,
};
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding as DomainArrowBinding, ArrowBindingMode as DomainArrowBindingMode,
    ArrowData as DomainArrowData, ArrowDataPatch as DomainArrowDataPatch,
    NullableField as DomainArrowNullableField,
};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::elements::types::arrow::arrow_like_data::NullableField as DomainArrowLikeNullableField;
use crate::draw::elements::types::arrow::arrow_two_point_layout::compute_arrow_two_point_layout;
use crate::draw::elements::types::arrow::elbow::elbow_router;
use crate::draw::elements::types::line::line_data::{
    LineData as DomainLineData, LineDataPatch as DomainLineDataPatch,
};
use crate::draw::models::element_state::ElementState as DomainElementState;
use crate::draw::services::object_snap_service::{
    ObjectSnapService, SnapAxisAnchor as ObjectSnapAxisAnchor,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::{default_text_metrics_service, TextMetricsService};
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};
use crate::draw::types::snap_guides::SnapGuide;
use crate::draw::utils::camera_zoom::resolve_zoom_adjusted_distance;
use crate::draw::utils::snapping_mode::SnappingMode;
use crate::draw::utils::visible_elements::resolve_visible_elements;

const LOOP_CLOSE_TOLERANCE_MULTIPLIER: f64 = 1.5;
const OBJECT_POINT_ANCHORS: [ObjectSnapAxisAnchor; 1] = [ObjectSnapAxisAnchor::Center];
const OBJECT_SNAP_SERVICE: ObjectSnapService = ObjectSnapService::new();

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
                session_data: Some(Arc::new(ArrowCreationSessionData::default())),
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
        snap_override_active: bool,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        let _ = text_metrics_service.unwrap_or_else(default_text_metrics_service);
        let data_ref = resolve_arrow_like_data(
            creating_state.element_data_ref(),
            "ArrowCreationStrategy.update",
        );
        let mut session_data = resolve_creation_session_data(creating_state);
        if data_ref.is_line() {
            return update_line(
                state,
                config,
                creating_state,
                current_position,
                snapping_mode,
                snap_override_active,
                maintain_aspect_ratio,
                create_from_center,
                &data_ref,
                &mut session_data,
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
            snap_override_active,
            maintain_aspect_ratio,
            create_from_center,
            &mut session_data,
        );
        let mut adjusted_current = endpoints.current_position;

        let binding_result = snap_binding_point(
            state,
            config,
            adjusted_current,
            snap_override_active,
            data_ref.arrow_type(),
            data_ref.end_arrowhead(),
            data_ref.end_binding(),
            Some(endpoints.segment_start),
            maintain_aspect_ratio,
            create_from_center,
            Some(&mut session_data.end_target_cache),
            ArrowBindingCachePolicy::default(),
        );
        session_data.allow_binding_on_finalize = binding_result.allow_binding_on_finalize;
        adjusted_current = binding_result.position;
        let mut end_binding = binding_result.binding;

        let close_tolerance =
            config.selection.interaction.handle_tolerance * LOOP_CLOSE_TOLERANCE_MULTIPLIER;
        if data_ref.arrow_type() != ArrowType::Elbow && endpoints.fixed_points.len() >= 2 {
            let start_point = endpoints.fixed_points[0];
            if adjusted_current.distance_squared(start_point) <= close_tolerance * close_tolerance {
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
                session_data: Some(Arc::new(session_data)),
            }),
            endpoints.snap_guides,
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

        let mut session_data = resolve_creation_session_data(creating_state);
        let endpoints = resolve_creation_endpoints(
            state,
            config,
            creating_state,
            data_ref.arrow_type(),
            data_ref.start_arrowhead(),
            data_ref.start_binding(),
            position,
            snapping_mode,
            snap_override_active,
            false,
            false,
            &mut session_data,
        );
        let mut adjusted_position = endpoints.current_position;

        let binding_result = snap_binding_point(
            state,
            config,
            adjusted_position,
            snap_override_active,
            data_ref.arrow_type(),
            data_ref.end_arrowhead(),
            data_ref.end_binding(),
            Some(endpoints.segment_start),
            false,
            false,
            Some(&mut session_data.end_target_cache),
            ArrowBindingCachePolicy::default(),
        );
        session_data.allow_binding_on_finalize = binding_result.allow_binding_on_finalize;
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
                session_data: Some(Arc::new(session_data)),
            }),
            endpoints.snap_guides,
        ))
    }

    fn finish(
        &self,
        state: &DrawState,
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

        if closed_points.len() < 2 {
            return CreationFinishResult::new(
                creating_state.element_data(),
                creating_state.current_rect,
                false,
                None,
            );
        }

        let mut finish_rect = calculate_arrow_rect(&closed_points, data_ref.arrow_type());
        let normalized_points = ArrowGeometry::normalize_points(&closed_points, finish_rect);
        let mut finalized_data = data_ref.copy_with(Some(normalized_points), None, None);
        let session_data = resolve_creation_session_data(creating_state);
        let mut ordered_element_ids = None;
        if config.snap.enable_arrow_binding {
            let finalized = finalize_connector_creation_bindings(
                state,
                config,
                creating_state.element.id.as_str(),
                &finish_rect,
                &finalized_data,
                &session_data,
            );
            finish_rect = finalized.rect;
            finalized_data = finalized.data;
            ordered_element_ids = finalized.ordered_element_ids;
        }
        let updated_data_ref =
            resolve_arrow_like_data(&finalized_data, "ArrowCreationStrategy.finish.length");
        let updated_world_points =
            ArrowGeometry::resolve_world_points(finish_rect, updated_data_ref.points());
        let length = ArrowGeometry::calculate_shaft_length(
            &updated_world_points,
            updated_data_ref.arrow_type(),
        );
        if !length.is_finite() || length < min_size {
            return CreationFinishResult::new(
                creating_state.element_data(),
                creating_state.current_rect,
                false,
                None,
            );
        }

        CreationFinishResult::new(finalized_data, finish_rect, true, ordered_element_ids)
    }
}

#[derive(Debug)]
struct ConnectorCreationFinishState {
    rect: DrawRect,
    data: Arc<dyn ElementData>,
    ordered_element_ids: Option<Vec<String>>,
}

fn finalize_connector_creation_bindings(
    state: &DrawState,
    config: &DrawConfig,
    element_id: &str,
    rect: &DrawRect,
    data: &Arc<dyn ElementData>,
    session_data: &ArrowCreationSessionData,
) -> ConnectorCreationFinishState {
    let data_ref = resolve_arrow_like_data(data, "ArrowCreationStrategy.finish.finalize");
    let world_points = ArrowGeometry::resolve_world_points(*rect, data_ref.points());
    if world_points.len() < 2 {
        return ConnectorCreationFinishState {
            rect: *rect,
            data: Arc::clone(data),
            ordered_element_ids: None,
        };
    }

    let preview_data = data_ref.to_arrow_data();
    let preview_element = DomainElementState::new(
        element_id.to_owned(),
        *rect,
        0.0,
        1.0,
        0,
        Arc::new(preview_data.clone()),
    );
    let preserve_dragged_inside_binding = data_ref
        .end_binding()
        .as_ref()
        .is_some_and(|binding| binding.mode == ArrowBindingMode::Inside);
    let preserve_opposite_inside_binding = session_data.preserve_start_inside_binding
        || data_ref
            .start_binding()
            .as_ref()
            .is_some_and(|binding| binding.mode == ArrowBindingMode::Inside);
    let opposite_orbit_focus_point = session_data.start_orbit_focus_point.or_else(|| {
        data_ref.start_binding().as_ref().and_then(|binding| {
            (binding.mode == ArrowBindingMode::Orbit).then_some(world_points[0])
        })
    });
    let ordered_ids = state
        .domain
        .document
        .elements
        .iter()
        .map(|element| element.id.clone())
        .chain(std::iter::once(element_id.to_owned()))
        .collect::<Vec<_>>();
    let preview_connector = ConnectorSourceData::Arrow(preview_data.clone());
    let finalized = finalize_connector_core_endpoint_drag_result(
        state,
        &preview_element,
        &preview_connector,
        &world_points,
        world_points.len() - 1,
        *world_points.last().unwrap_or(&world_points[0]),
        data_ref.start_binding().as_ref(),
        data_ref.end_binding().as_ref(),
        element_id,
        true,
        session_data.allow_binding_on_finalize,
        resolve_core_max_binding_distance(state.application.view.camera.zoom),
        build_core_engine_context(
            state.application.view.camera.zoom,
            config.snap.enable_arrow_binding,
            resolve_endpoint_drag_binding_enabled(config.snap.enable_arrow_binding),
            DEFAULT_MAX_COORDINATE,
        ),
        preview_data.fixed_segments.as_deref(),
        Some(ordered_ids.as_slice()),
        ArrowCoreEndpointBindingOptions {
            new_arrow: true,
            alt_key: preserve_dragged_inside_binding,
            preserve_opposite_inside_binding,
            opposite_orbit_focus_point,
            ..ArrowCoreEndpointBindingOptions::default()
        },
    );
    let Some(finalized) = finalized else {
        return ConnectorCreationFinishState {
            rect: *rect,
            data: Arc::clone(data),
            ordered_element_ids: None,
        };
    };

    match data_ref {
        ArrowLikeDataRef::DomainArrow(current) => {
            let next_rect = calculate_arrow_rect(&finalized.world_points, current.arrow_type);
            let next_points = ArrowGeometry::normalize_points(&finalized.world_points, next_rect);
            let next_data = Arc::new(current.copy_with(DomainArrowDataPatch {
                points: Some(next_points),
                start_binding: to_domain_arrow_nullable_binding(Some(finalized.start_binding)),
                end_binding: to_domain_arrow_nullable_binding(Some(finalized.end_binding)),
                fixed_segments: match finalized.fixed_segments.clone() {
                    Some(segments) => DomainArrowNullableField::Value(segments),
                    None => DomainArrowNullableField::Null,
                },
                start_is_special: match finalized.arrow.start_is_special {
                    Some(value) => DomainArrowNullableField::Value(value),
                    None => DomainArrowNullableField::Null,
                },
                end_is_special: match finalized.arrow.end_is_special {
                    Some(value) => DomainArrowNullableField::Value(value),
                    None => DomainArrowNullableField::Null,
                },
                ..DomainArrowDataPatch::default()
            }));
            ConnectorCreationFinishState {
                rect: next_rect,
                data: next_data,
                ordered_element_ids: finalized.ordered_element_ids,
            }
        }
        ArrowLikeDataRef::DomainLine(current) => {
            let next_rect = calculate_arrow_rect(&finalized.world_points, current.arrow_type);
            let next_points = ArrowGeometry::normalize_points(&finalized.world_points, next_rect);
            let next_data = Arc::new(current.copy_with(DomainLineDataPatch {
                points: Some(next_points),
                start_binding: to_domain_line_nullable_binding(Some(finalized.start_binding)),
                end_binding: to_domain_line_nullable_binding(Some(finalized.end_binding)),
                ..DomainLineDataPatch::default()
            }));
            ConnectorCreationFinishState {
                rect: next_rect,
                data: next_data,
                ordered_element_ids: finalized.ordered_element_ids,
            }
        }
    }
}

fn update_line(
    state: &DrawState,
    config: &DrawConfig,
    creating_state: &CreatingState,
    current_position: DrawPoint,
    snapping_mode: SnappingMode,
    snap_override_active: bool,
    maintain_aspect_ratio: bool,
    create_from_center: bool,
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
        snap_override_active,
        maintain_aspect_ratio,
        create_from_center,
        session_data,
    );
    let mut adjusted_current = endpoints.current_position;

    let binding_result = snap_binding_point(
        state,
        config,
        adjusted_current,
        snap_override_active,
        data_ref.arrow_type(),
        data_ref.end_arrowhead(),
        data_ref.end_binding(),
        Some(endpoints.segment_start),
        maintain_aspect_ratio,
        create_from_center,
        Some(&mut session_data.end_target_cache),
        ArrowBindingCachePolicy::default(),
    );
    session_data.allow_binding_on_finalize = binding_result.allow_binding_on_finalize;
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
            session_data: Some(Arc::new(session_data.clone())),
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
    snap_override_active: bool,
    angle_locked: bool,
    alt_key: bool,
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
        snap_override_active,
        arrow_type,
        start_arrowhead,
        preferred_start_binding,
        adjusted_current,
        angle_locked,
        alt_key,
        session_data,
        ArrowBindingCachePolicy::default(),
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

    let result = OBJECT_SNAP_SERVICE.snap_rect(
        DrawRect::new(position.x, position.y, position.x, position.y),
        &reference_elements,
        snap_distance,
        &OBJECT_POINT_ANCHORS,
        &OBJECT_POINT_ANCHORS,
        Some(&reference_aabbs),
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
    snap_override_active: bool,
    arrow_type: ArrowType,
    arrowhead_style: ArrowheadStyle,
    preferred_binding: Option<ArrowBinding>,
    reference_point: Option<DrawPoint>,
    _angle_locked: bool,
    _alt_key: bool,
    target_cache: Option<&mut ArrowBindingTargetCache<DomainElementState>>,
    cache_policy: ArrowBindingCachePolicy,
) -> BindingSnapResult {
    let snap_config = &config.snap;
    let should_lookup_bindings =
        ArrowBindingSnapper::should_attempt_binding(snap_config, snap_override_active);
    let binding_distance = if should_lookup_bindings {
        ArrowBindingSnapper::resolve_binding_distance(state, snap_config)
    } else {
        0.0
    };

    if !should_lookup_bindings || binding_distance <= 0.0 {
        if let Some(cache) = target_cache {
            cache.reset();
        }
        let mut result = BindingSnapResult::new(position, None);
        result.allow_binding_on_finalize = false;
        return result;
    }

    let candidate = ArrowBindingSnapper::resolve_endpoint_binding_candidate(
        state,
        position,
        arrow_type,
        arrowhead_style,
        should_lookup_bindings,
        binding_distance,
        true,
        has_bindable_targets(state),
        preferred_binding.as_ref(),
        reference_point,
        target_cache,
        None,
        cache_policy,
        &DOMAIN_CREATION_BINDING_RESOLVER,
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
    snap_override_active: bool,
    arrow_type: ArrowType,
    arrowhead_style: ArrowheadStyle,
    preferred_binding: Option<ArrowBinding>,
    reference_point: DrawPoint,
    angle_locked: bool,
    alt_key: bool,
    session_data: &mut ArrowCreationSessionData,
    cache_policy: ArrowBindingCachePolicy,
) -> BindingSnapResult {
    let snap_config = &config.snap;
    let binding_enabled =
        ArrowBindingSnapper::should_attempt_binding(snap_config, snap_override_active);
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
        angle_locked,
        alt_key,
    ) {
        if let Some(cached) = session_data.resolve_cached_start_binding(
            state,
            start_position,
            arrow_type,
            arrowhead_style,
            reference_point,
        ) {
            return cached;
        }
    }

    let resolved = snap_binding_point(
        state,
        config,
        start_position,
        snap_override_active,
        arrow_type,
        arrowhead_style,
        preferred_binding.clone(),
        Some(reference_point),
        angle_locked,
        alt_key,
        Some(&mut session_data.start_target_cache),
        cache_policy,
    );
    if preferred_binding.is_none() {
        match resolved.binding.as_ref().map(|binding| binding.mode) {
            Some(ArrowBindingMode::Inside) => {
                session_data.preserve_start_inside_binding = true;
                session_data.start_orbit_focus_point = None;
            }
            Some(ArrowBindingMode::Orbit) => {
                session_data.preserve_start_inside_binding = false;
                session_data.start_orbit_focus_point = Some(resolved.position);
            }
            _ => {
                session_data.preserve_start_inside_binding = false;
                session_data.start_orbit_focus_point = None;
            }
        }
    }
    session_data.cache_start_binding(
        start_position,
        preferred_binding,
        snapping_mode,
        elements_version,
        binding_enabled,
        binding_distance,
        angle_locked,
        alt_key,
        &resolved,
    );
    resolved
}

#[derive(Debug, Clone)]
struct ArrowCreationSessionData {
    start_target_cache: ArrowBindingTargetCache<DomainElementState>,
    end_target_cache: ArrowBindingTargetCache<DomainElementState>,
    cached_start_position: Option<DrawPoint>,
    cached_start_preferred_binding: Option<ArrowBinding>,
    cached_start_binding: Option<ArrowBinding>,
    cached_start_snapping_mode: Option<SnappingMode>,
    cached_start_binding_enabled: Option<bool>,
    cached_start_binding_distance: Option<f64>,
    cached_start_angle_locked: Option<bool>,
    cached_start_alt_key: Option<bool>,
    cached_start_elements_version: i64,
    preserve_start_inside_binding: bool,
    start_orbit_focus_point: Option<DrawPoint>,
    allow_binding_on_finalize: bool,
    reference_elements_version: i64,
    reference_elements: Vec<DomainElementState>,
    reference_aabbs_version: i64,
    reference_element_aabbs: Vec<DrawRect>,
    reference_aabbs_source: Vec<DomainElementState>,
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
            cached_start_angle_locked: None,
            cached_start_alt_key: None,
            cached_start_elements_version: -1,
            preserve_start_inside_binding: false,
            start_orbit_focus_point: None,
            allow_binding_on_finalize: true,
            reference_elements_version: -1,
            reference_elements: Vec::new(),
            reference_aabbs_version: -1,
            reference_element_aabbs: Vec::new(),
            reference_aabbs_source: Vec::new(),
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
        angle_locked: bool,
        alt_key: bool,
    ) -> bool {
        self.cached_start_position == Some(start_position)
            && self.cached_start_preferred_binding.as_ref() == preferred_binding
            && self.cached_start_snapping_mode == Some(snapping_mode)
            && self.cached_start_binding_enabled == Some(binding_enabled)
            && self.cached_start_binding_distance == Some(binding_distance)
            && self.cached_start_angle_locked == Some(angle_locked)
            && self.cached_start_alt_key == Some(alt_key)
            && self.cached_start_elements_version == elements_version
    }

    fn resolve_cached_start_binding(
        &self,
        state: &DrawState,
        start_position: DrawPoint,
        arrow_type: ArrowType,
        arrowhead_style: ArrowheadStyle,
        reference_point: DrawPoint,
    ) -> Option<BindingSnapResult> {
        let Some(cached_binding) = self.cached_start_binding.as_ref() else {
            return Some(BindingSnapResult::new(start_position, None));
        };
        let target = state
            .domain
            .document
            .get_element_by_id(cached_binding.element_id.as_str())?;
        if target.opacity <= 0.0 || !ArrowBindingUtils::is_bindable_target(target) {
            return None;
        }

        let bound_point = if arrow_type == ArrowType::Elbow {
            ArrowBindingUtils::resolve_elbow_bound_point(
                cached_binding,
                target,
                arrowhead_style != ArrowheadStyle::None,
            )?
        } else {
            ArrowBindingUtils::resolve_bound_point(cached_binding, target, Some(reference_point))?
        };

        Some(BindingSnapResult::new(
            bound_point,
            Some(cached_binding.clone()),
        ))
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
        angle_locked: bool,
        alt_key: bool,
        result: &BindingSnapResult,
    ) {
        self.cached_start_position = Some(start_position);
        self.cached_start_preferred_binding = preferred_binding;
        self.cached_start_binding = result.binding.clone();
        self.cached_start_snapping_mode = Some(snapping_mode);
        self.cached_start_binding_enabled = Some(binding_enabled);
        self.cached_start_binding_distance = Some(binding_distance);
        self.cached_start_angle_locked = Some(angle_locked);
        self.cached_start_alt_key = Some(alt_key);
        self.cached_start_elements_version = elements_version;
    }

    fn resolve_reference_elements(&mut self, state: &DrawState) -> Vec<DomainElementState> {
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
        reference_elements: &[DomainElementState],
    ) -> Vec<DrawRect> {
        let elements_version = resolve_elements_version(state);
        if self.reference_aabbs_version == elements_version
            && self.reference_aabbs_source.as_slice() == reference_elements
        {
            return self.reference_element_aabbs.clone();
        }
        self.reference_aabbs_version = elements_version;
        self.reference_aabbs_source = reference_elements.to_vec();
        self.reference_element_aabbs = ObjectSnapService::build_reference_aabbs(reference_elements);
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
    start_binding: Option<ArrowBinding>,
    end_binding: Option<ArrowBinding>,
    allow_binding_on_finalize: bool,
}

impl BindingSnapResult {
    fn new(position: DrawPoint, binding: Option<ArrowBinding>) -> Self {
        Self {
            position,
            binding,
            start_binding: None,
            end_binding: None,
            allow_binding_on_finalize: true,
        }
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
    DomainArrow(&'a DomainArrowData),
    DomainLine(&'a DomainLineData),
}

impl<'a> ArrowLikeDataRef<'a> {
    fn is_line(&self) -> bool {
        matches!(self, Self::DomainLine(_))
    }

    fn points(&self) -> &[DrawPoint] {
        match self {
            Self::DomainArrow(data) => &data.points,
            Self::DomainLine(data) => &data.points,
        }
    }

    fn arrow_type(&self) -> ArrowType {
        match self {
            Self::DomainArrow(data) => data.arrow_type,
            Self::DomainLine(data) => data.arrow_type,
        }
    }

    fn start_arrowhead(&self) -> ArrowheadStyle {
        match self {
            Self::DomainArrow(data) => data.start_arrowhead,
            Self::DomainLine(data) => data.start_arrowhead,
        }
    }

    fn end_arrowhead(&self) -> ArrowheadStyle {
        match self {
            Self::DomainArrow(data) => data.end_arrowhead,
            Self::DomainLine(data) => data.end_arrowhead,
        }
    }

    fn start_binding(&self) -> Option<ArrowBinding> {
        match self {
            Self::DomainArrow(data) => data
                .start_binding
                .as_ref()
                .map(domain_arrow_binding_to_local),
            Self::DomainLine(data) => data.start_binding.clone(),
        }
    }

    fn end_binding(&self) -> Option<ArrowBinding> {
        match self {
            Self::DomainArrow(data) => data.end_binding.as_ref().map(domain_arrow_binding_to_local),
            Self::DomainLine(data) => data.end_binding.clone(),
        }
    }

    fn copy_with(
        &self,
        points: Option<Vec<DrawPoint>>,
        start_binding: Option<Option<ArrowBinding>>,
        end_binding: Option<Option<ArrowBinding>>,
    ) -> Arc<dyn ElementData> {
        match self {
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

    fn to_arrow_data(&self) -> DomainArrowData {
        match self {
            Self::DomainArrow(data) => (*data).clone(),
            Self::DomainLine(data) => DomainArrowData {
                points: data.points.clone(),
                color: data.color,
                stroke_width: data.stroke_width,
                stroke_style: data.stroke_style,
                arrow_type: data.arrow_type,
                start_arrowhead: data.start_arrowhead,
                end_arrowhead: data.end_arrowhead,
                start_binding: data
                    .start_binding
                    .clone()
                    .map(|binding| local_binding_to_domain_arrow(&binding)),
                end_binding: data
                    .end_binding
                    .clone()
                    .map(|binding| local_binding_to_domain_arrow(&binding)),
                fixed_segments: data.fixed_segments.clone(),
                start_is_special: data.start_is_special,
                end_is_special: data.end_is_special,
            },
        }
    }
}

fn resolve_arrow_like_data<'a>(
    data: &'a Arc<dyn ElementData>,
    strategy_name: &str,
) -> ArrowLikeDataRef<'a> {
    if let Some(arrow_data) = data.as_ref().as_any().downcast_ref::<DomainArrowData>() {
        return ArrowLikeDataRef::DomainArrow(arrow_data);
    }
    if let Some(line_data) = data.as_ref().as_any().downcast_ref::<DomainLineData>() {
        return ArrowLikeDataRef::DomainLine(line_data);
    }
    panic!(
        "{strategy_name} expects {} or {} but received {}.",
        std::any::type_name::<DomainArrowData>(),
        std::any::type_name::<DomainLineData>(),
        data.as_ref().runtime_type_name()
    );
}

fn domain_arrow_binding_mode_to_local(
    mode: DomainArrowBindingMode,
) -> crate::draw::elements::types::arrow::arrow_binding::ArrowBindingMode {
    match mode {
        DomainArrowBindingMode::Inside => {
            crate::draw::elements::types::arrow::arrow_binding::ArrowBindingMode::Inside
        }
        DomainArrowBindingMode::Orbit => {
            crate::draw::elements::types::arrow::arrow_binding::ArrowBindingMode::Orbit
        }
        DomainArrowBindingMode::Skip => {
            crate::draw::elements::types::arrow::arrow_binding::ArrowBindingMode::Skip
        }
    }
}

fn local_binding_mode_to_domain_arrow(
    mode: crate::draw::elements::types::arrow::arrow_binding::ArrowBindingMode,
) -> DomainArrowBindingMode {
    match mode {
        crate::draw::elements::types::arrow::arrow_binding::ArrowBindingMode::Inside => {
            DomainArrowBindingMode::Inside
        }
        crate::draw::elements::types::arrow::arrow_binding::ArrowBindingMode::Orbit => {
            DomainArrowBindingMode::Orbit
        }
        crate::draw::elements::types::arrow::arrow_binding::ArrowBindingMode::Skip => {
            DomainArrowBindingMode::Skip
        }
    }
}

fn domain_arrow_binding_to_local(binding: &DomainArrowBinding) -> ArrowBinding {
    ArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        domain_arrow_binding_mode_to_local(binding.mode),
    )
}

fn local_binding_to_domain_arrow(binding: &ArrowBinding) -> DomainArrowBinding {
    DomainArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        local_binding_mode_to_domain_arrow(binding.mode),
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
) -> DomainArrowLikeNullableField<ArrowBinding> {
    match value {
        None => DomainArrowLikeNullableField::Unset,
        Some(None) => DomainArrowLikeNullableField::Null,
        Some(Some(binding)) => DomainArrowLikeNullableField::Value(binding),
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct DomainCreationBindingResolver;

const DOMAIN_CREATION_BINDING_RESOLVER: DomainCreationBindingResolver =
    DomainCreationBindingResolver;

impl BindingResolver<DomainElementState> for DomainCreationBindingResolver {
    fn is_bindable_target(&self, target: &DomainElementState) -> bool {
        ArrowBindingUtils::is_bindable_target(target)
    }

    fn resolve_binding_search_distance(&self, snap_distance: f64) -> f64 {
        ArrowBindingUtils::resolve_binding_search_distance(snap_distance)
    }

    fn resolve_binding_candidate_for_target(
        &self,
        world_point: DrawPoint,
        target: &DomainElementState,
        snap_distance: f64,
        reference_point: Option<DrawPoint>,
    ) -> Option<ArrowBindingResult> {
        ArrowBindingUtils::resolve_binding_candidate_for_target(
            world_point,
            target,
            snap_distance,
            reference_point,
        )
    }

    fn resolve_elbow_binding_candidate_for_target(
        &self,
        world_point: DrawPoint,
        target: &DomainElementState,
        snap_distance: f64,
        has_arrowhead: bool,
    ) -> Option<ArrowBindingResult> {
        ArrowBindingUtils::resolve_elbow_binding_candidate_for_target(
            world_point,
            target,
            snap_distance,
            has_arrowhead,
        )
    }

    fn resolve_binding_candidate(
        &self,
        world_point: DrawPoint,
        targets: &[DomainElementState],
        snap_distance: f64,
        preferred_binding: Option<&ArrowBinding>,
        allow_new_binding: bool,
        reference_point: Option<DrawPoint>,
    ) -> Option<ArrowBindingResult> {
        ArrowBindingUtils::resolve_binding_candidate(
            world_point,
            targets.iter(),
            snap_distance,
            preferred_binding,
            allow_new_binding,
            reference_point,
        )
    }

    fn resolve_elbow_binding_candidate(
        &self,
        world_point: DrawPoint,
        targets: &[DomainElementState],
        snap_distance: f64,
        preferred_binding: Option<&ArrowBinding>,
        allow_new_binding: bool,
        has_arrowhead: bool,
    ) -> Option<ArrowBindingResult> {
        ArrowBindingUtils::resolve_elbow_binding_candidate(
            world_point,
            targets.iter(),
            snap_distance,
            has_arrowhead,
            preferred_binding,
            allow_new_binding,
        )
    }
}

impl ArrowBindingElement for DomainElementState {
    fn id(&self) -> &str {
        self.id.as_str()
    }

    fn opacity(&self) -> f64 {
        self.opacity
    }
}

impl ArrowBindingState<DomainElementState> for DrawState {
    fn camera_zoom(&self) -> f64 {
        self.application.view.camera.zoom
    }

    fn elements_version(&self) -> i64 {
        self.domain.document.elements_version
    }

    fn get_element_by_id(&self, id: &str) -> Option<DomainElementState> {
        self.domain.document.get_element_by_id(id).cloned()
    }

    fn visit_arrow_bindable_elements_at_point(
        &self,
        position: DrawPoint,
        distance: f64,
        excluded_element_id: Option<&str>,
        visitor: &mut dyn FnMut(DomainElementState) -> bool,
    ) {
        for element in &self.domain.document.elements {
            if excluded_element_id.is_some_and(|excluded| excluded == element.id) {
                continue;
            }
            if !ArrowBindingUtils::is_bindable_target(element) {
                continue;
            }
            if !is_within_point_query_tolerance(element, position, distance) {
                continue;
            }
            if !visitor(element.clone()) {
                break;
            }
        }
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

fn is_within_point_query_tolerance(
    element: &DomainElementState,
    position: DrawPoint,
    distance: f64,
) -> bool {
    let rect = element.rect;
    position.x >= rect.min_x - distance
        && position.x <= rect.max_x + distance
        && position.y >= rect.min_y - distance
        && position.y <= rect.max_y + distance
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

fn resolve_elements_version(state: &DrawState) -> i64 {
    state.domain.document.elements_version
}

fn resolve_view_zoom(state: &DrawState) -> f64 {
    state.application.view.camera.zoom
}

fn has_bindable_targets(state: &DrawState) -> bool {
    state
        .domain
        .document
        .elements
        .iter()
        .any(ArrowBindingUtils::is_bindable_target)
}

fn resolve_reference_elements(state: &DrawState) -> Vec<DomainElementState> {
    resolve_visible_elements(state.domain.document.elements.iter().cloned(), None)
}

fn resolve_creation_session_data(creating_state: &CreatingState) -> ArrowCreationSessionData {
    let CreationMode::Point(point_mode) = &creating_state.creation_mode else {
        return ArrowCreationSessionData::default();
    };

    point_mode
        .session_data
        .as_ref()
        .and_then(|payload| {
            payload
                .as_ref()
                .downcast_ref::<ArrowCreationSessionData>()
                .cloned()
        })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::{ArrowCreationSessionData, BindingSnapResult};
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::utils::snapping_mode::SnappingMode;

    #[test]
    fn start_binding_cache_includes_modifier_flags() {
        let mut session = ArrowCreationSessionData::default();
        let result = BindingSnapResult::new(DrawPoint::ZERO, None);

        session.cache_start_binding(
            DrawPoint::ZERO,
            None,
            SnappingMode::Object,
            7,
            true,
            12.0,
            true,
            false,
            &result,
        );

        assert!(session.can_reuse_start_binding(
            DrawPoint::ZERO,
            None,
            SnappingMode::Object,
            7,
            true,
            12.0,
            true,
            false,
        ));
        assert!(!session.can_reuse_start_binding(
            DrawPoint::ZERO,
            None,
            SnappingMode::Object,
            7,
            true,
            12.0,
            false,
            false,
        ));
        assert!(!session.can_reuse_start_binding(
            DrawPoint::ZERO,
            None,
            SnappingMode::Object,
            7,
            true,
            12.0,
            true,
            true,
        ));
    }
}
