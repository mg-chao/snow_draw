#![allow(dead_code)]
#![allow(unused_imports)]
#![allow(unused_variables)]

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use crate::draw::config::draw_config::{ConfigDefaults, DrawConfig};
use crate::draw::elements::core::creation_strategy::{
    require_creating_element_data_type, require_creation_data_type, snap_creation_point,
    CreatingState, CreationFinishResult, CreationMode, CreationStrategy, CreationUpdateResult,
    DrawState, ElementData, PointCreationMode,
};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::elements::types::free_draw::free_draw_data::{
    FreeDrawData as DomainFreeDrawData, FreeDrawDataPatch as DomainFreeDrawDataPatch,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::{default_text_metrics_service, TextMetricsService};
use crate::draw::types::element_style::StrokeStyle;
use crate::draw::utils::snapping_mode::SnappingMode;

const BASE_MIN_DISTANCE: f64 = 1.5;
const SMOOTHING_ALPHA: f64 = 0.2;
const TAIL_REPLACE_MAX_TURN_SIN: f64 = 0.08;
const LENGTH_EPSILON: f64 = 1e-6;
const BAKE_ITERATIONS: usize = 3;

/// Creation strategy for freehand drawing.
///
/// During interaction, this strategy keeps world-space points in a lightweight
/// per-element session store and finalizes normalized points in `finish`.
#[derive(Debug, Default, Clone, Copy)]
pub struct FreeDrawCreationStrategy;

impl FreeDrawCreationStrategy {
    pub const fn new() -> Self {
        Self
    }
}

impl CreationStrategy for FreeDrawCreationStrategy {
    fn start(
        &self,
        data: Arc<dyn ElementData>,
        start_position: DrawPoint,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        let _ = text_metrics_service.unwrap_or_else(default_text_metrics_service);

        let free_draw_data = require_creation_data_type::<DomainFreeDrawData>(
            &data,
            "FreeDrawCreationStrategy.start",
        );
        let world_points = vec![start_position, start_position];
        let _preview_points =
            resolve_preview_points_if_needed(None, &world_points, free_draw_data.stroke_style);

        CreationUpdateResult::new(
            data,
            bounds_from_points(&world_points),
            creation_mode_from_world_points(&world_points),
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
        let _ = state;
        let _ = create_from_center;
        let _ = text_metrics_service.unwrap_or_else(default_text_metrics_service);

        let element_data = require_creating_element_data_type::<DomainFreeDrawData>(
            creating_state,
            "FreeDrawCreationStrategy.update",
        );
        let adjusted_position = snap_creation_point(current_position, config, snapping_mode);

        with_creation_session_data(&creating_state.element.id, |session| {
            session.initialize_if_needed(
                &creating_state.creation_mode,
                creating_state.current_rect,
                &element_data.points,
                element_data.stroke_style,
            );

            let mut preview_changed = false;
            let was_line_active = session.is_line_active;

            if maintain_aspect_ratio {
                if !was_line_active {
                    start_line_segment(&mut session.world_points, adjusted_position);
                    let anchor = if session.world_points.len() >= 2 {
                        session.world_points[session.world_points.len() - 2]
                    } else {
                        adjusted_position
                    };
                    session.line_anchor = Some(anchor);
                    session.line_current = session.world_points.last().copied();
                    preview_changed = true;
                } else {
                    let before = session.world_points.last().copied();
                    update_line_segment(&mut session.world_points, adjusted_position);
                    let after = session.world_points.last().copied();
                    session.line_current = after;
                    preview_changed = before != after;
                }
            } else {
                let completed_line_point = if was_line_active {
                    session
                        .line_current
                        .or_else(|| session.world_points.last().copied())
                } else {
                    None
                };
                if let (Some(point), Some(preview_points)) =
                    (completed_line_point, session.preview_points.as_mut())
                {
                    append_preview_point(preview_points, point);
                    preview_changed = true;
                }

                let mutation = append_smoothed_point(
                    &mut session.world_points,
                    adjusted_position,
                    element_data.stroke_width,
                    session.preview_points.is_none(),
                );
                if mutation.has_change {
                    if let (Some(preview_points), Some(appended_point)) =
                        (session.preview_points.as_mut(), mutation.appended_point)
                    {
                        append_preview_point(preview_points, appended_point);
                    }
                    preview_changed = true;
                }

                session.line_anchor = None;
                session.line_current = None;
            }

            session.preview_points = resolve_preview_points_if_needed(
                session.preview_points.take(),
                &session.world_points,
                element_data.stroke_style,
            );

            let rect = expand_bounds(creating_state.current_rect, &session.world_points);
            let line_state_changed = maintain_aspect_ratio != was_line_active;
            let rect_changed = rect != creating_state.current_rect;
            let has_change = preview_changed || line_state_changed || rect_changed;

            if !has_change {
                return CreationUpdateResult::new(
                    creating_state.element_data(),
                    creating_state.current_rect,
                    creating_state.creation_mode.clone(),
                    Vec::new(),
                );
            }

            session.is_line_active = maintain_aspect_ratio;
            session.revision = session.revision.saturating_add(1);

            CreationUpdateResult::new(
                creating_state.element_data(),
                rect,
                creation_mode_from_world_points(&session.world_points),
                Vec::new(),
            )
        })
    }

    fn update_batch(
        &self,
        state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        positions: &[DrawPoint],
        maintain_aspect_ratio: bool,
        create_from_center: bool,
        snapping_mode: SnappingMode,
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

        let resolved_text_metrics_service =
            text_metrics_service.unwrap_or_else(default_text_metrics_service);
        if positions.len() == 1 || maintain_aspect_ratio {
            return self.update(
                state,
                config,
                creating_state,
                positions[positions.len() - 1],
                maintain_aspect_ratio,
                create_from_center,
                snapping_mode,
                Some(resolved_text_metrics_service),
            );
        }

        let _ = state;
        let _ = create_from_center;
        let element_data = require_creating_element_data_type::<DomainFreeDrawData>(
            creating_state,
            "FreeDrawCreationStrategy.updateBatch",
        );

        with_creation_session_data(&creating_state.element.id, |session| {
            session.initialize_if_needed(
                &creating_state.creation_mode,
                creating_state.current_rect,
                &element_data.points,
                element_data.stroke_style,
            );

            let mut rect = creating_state.current_rect;
            let mut preview_changed = false;

            if session.is_line_active {
                let completed_line_point = session
                    .line_current
                    .or_else(|| session.world_points.last().copied());
                if let (Some(point), Some(preview_points)) =
                    (completed_line_point, session.preview_points.as_mut())
                {
                    append_preview_point(preview_points, point);
                    rect = expand_bounds_with_point(rect, point);
                    preview_changed = true;
                }
            }

            for raw_position in positions {
                let adjusted_position = snap_creation_point(*raw_position, config, snapping_mode);
                let mutation = append_smoothed_point(
                    &mut session.world_points,
                    adjusted_position,
                    element_data.stroke_width,
                    session.preview_points.is_none(),
                );
                if !mutation.has_change {
                    continue;
                }
                if let (Some(preview_points), Some(appended_point)) =
                    (session.preview_points.as_mut(), mutation.appended_point)
                {
                    append_preview_point(preview_points, appended_point);
                }
                if let Some(changed_point) = mutation.changed_point {
                    rect = expand_bounds_with_point(rect, changed_point);
                }
                preview_changed = true;
            }

            session.preview_points = resolve_preview_points_if_needed(
                session.preview_points.take(),
                &session.world_points,
                element_data.stroke_style,
            );

            let line_state_changed = session.is_line_active;
            if !preview_changed && !line_state_changed {
                return CreationUpdateResult::new(
                    creating_state.element_data(),
                    creating_state.current_rect,
                    creating_state.creation_mode.clone(),
                    Vec::new(),
                );
            }

            session.is_line_active = false;
            session.line_anchor = None;
            session.line_current = None;
            session.revision = session.revision.saturating_add(1);

            CreationUpdateResult::new(
                creating_state.element_data(),
                rect,
                creation_mode_from_world_points(&session.world_points),
                Vec::new(),
            )
        })
    }

    fn finish(
        &self,
        config: &DrawConfig,
        creating_state: &CreatingState,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationFinishResult {
        let _ = text_metrics_service.unwrap_or_else(default_text_metrics_service);
        let data = require_creating_element_data_type::<DomainFreeDrawData>(
            creating_state,
            "FreeDrawCreationStrategy.finish",
        );

        let world_points = take_creation_session_data(&creating_state.element.id)
            .map(|session| session.world_points)
            .unwrap_or_else(|| {
                resolve_creation_world_points(
                    &creating_state.creation_mode,
                    creating_state.current_rect,
                    &data.points,
                )
            });

        let mut points = remove_adjacent_duplicates(&world_points);
        if points.len() < 2 {
            return CreationFinishResult::new(
                creating_state.element_data(),
                creating_state.current_rect,
                false,
            );
        }

        points = close_if_needed(
            points,
            config.selection.interaction.handle_tolerance
                * ConfigDefaults::FREE_DRAW_CLOSE_TOLERANCE_MULTIPLIER,
        );

        let length = path_length(&points);
        if !length.is_finite() || length < config.element.min_create_size {
            return CreationFinishResult::new(
                creating_state.element_data(),
                creating_state.current_rect,
                false,
            );
        }

        let rect = bounds_from_points(&points);
        let normalized = ArrowGeometry::normalize_points(&points, rect);
        let finalized_points = build_baked_normalized_points(&points, rect).unwrap_or(normalized);
        let finalized_data = Arc::new(data.copy_with(DomainFreeDrawDataPatch {
            points: Some(finalized_points),
            ..DomainFreeDrawDataPatch::default()
        }));

        CreationFinishResult::new(finalized_data, rect, true)
    }
}

#[derive(Clone, Debug, Default)]
struct FreeDrawCreationSessionData {
    initialized: bool,
    is_line_active: bool,
    world_points: Vec<DrawPoint>,
    preview_points: Option<Vec<DrawPoint>>,
    line_anchor: Option<DrawPoint>,
    line_current: Option<DrawPoint>,
    revision: u64,
}

impl FreeDrawCreationSessionData {
    fn initialize_if_needed(
        &mut self,
        creation_mode: &CreationMode,
        rect: DrawRect,
        normalized_points: &[DrawPoint],
        stroke_style: StrokeStyle,
    ) {
        if !self.initialized {
            self.world_points =
                resolve_creation_world_points(creation_mode, rect, normalized_points);
            self.initialized = true;
        }
        self.preview_points = resolve_preview_points_if_needed(
            self.preview_points.take(),
            &self.world_points,
            stroke_style,
        );
    }
}

fn resolve_creation_world_points(
    mode: &CreationMode,
    rect: DrawRect,
    normalized_points: &[DrawPoint],
) -> Vec<DrawPoint> {
    if let CreationMode::Point(point_mode) = mode {
        if !point_mode.fixed_points.is_empty() {
            return point_mode.fixed_points.clone();
        }
    }
    ArrowGeometry::resolve_world_points(rect, normalized_points)
}

fn resolve_preview_points_if_needed(
    existing_points: Option<Vec<DrawPoint>>,
    world_points: &[DrawPoint],
    stroke_style: StrokeStyle,
) -> Option<Vec<DrawPoint>> {
    if stroke_style == StrokeStyle::Solid {
        None
    } else {
        Some(existing_points.unwrap_or_else(|| world_points.to_vec()))
    }
}

fn append_preview_point(preview_points: &mut Vec<DrawPoint>, point: DrawPoint) {
    preview_points.push(point);
}

fn bounds_from_points(points: &[DrawPoint]) -> DrawRect {
    DrawRect::from_point_cloud(points.iter().copied())
}

fn expand_bounds(current: DrawRect, points: &[DrawPoint]) -> DrawRect {
    if points.is_empty() {
        return current;
    }

    let start = points.len().saturating_sub(2);
    current.expand_to_include_all(points.iter().skip(start).copied())
}

fn expand_bounds_with_point(current: DrawRect, point: DrawPoint) -> DrawRect {
    current.expand_to_include(point)
}

fn remove_adjacent_duplicates(points: &[DrawPoint]) -> Vec<DrawPoint> {
    if points.len() <= 1 {
        return points.to_vec();
    }

    let mut filtered = Vec::with_capacity(points.len());
    filtered.push(points[0]);
    for &point in points.iter().skip(1) {
        if !same_location(point, *filtered.last().unwrap_or(&point)) {
            filtered.push(point);
        }
    }
    filtered
}

fn close_if_needed(points: Vec<DrawPoint>, close_tolerance: f64) -> Vec<DrawPoint> {
    if points.len() < 3 {
        return points;
    }

    let first = points[0];
    let last = points[points.len() - 1];
    if same_location(first, last) {
        return points;
    }

    if first.distance_squared(last) <= close_tolerance * close_tolerance {
        let mut closed = points;
        let replacement = first.copy_with(None, None, Some(last.pressure), None);
        if let Some(last_point) = closed.last_mut() {
            *last_point = replacement;
        }
        return closed;
    }

    points
}

fn path_length(points: &[DrawPoint]) -> f64 {
    if points.len() < 2 {
        return 0.0;
    }
    points
        .windows(2)
        .map(|segment| segment[0].distance(segment[1]))
        .sum()
}

fn build_baked_normalized_points(
    world_points: &[DrawPoint],
    rect: DrawRect,
) -> Option<Vec<DrawPoint>> {
    if world_points.len() < 3 {
        return None;
    }

    let closed = same_location(world_points[0], world_points[world_points.len() - 1]);
    let source = if closed && world_points.len() > 3 {
        world_points[..world_points.len() - 1].to_vec()
    } else {
        world_points.to_vec()
    };
    if source.len() < 3 {
        return None;
    }

    let smoothed = smooth_stroke_points_for_bake(&source, closed);
    if smoothed.len() < 3 {
        return None;
    }

    let baked_world_points = if closed && !same_location(smoothed[0], smoothed[smoothed.len() - 1])
    {
        let mut closed_points = smoothed.clone();
        closed_points.push(smoothed[0]);
        closed_points
    } else {
        smoothed
    };
    if baked_world_points.len() < 3 {
        return None;
    }

    Some(ArrowGeometry::normalize_points(&baked_world_points, rect))
}

fn smooth_stroke_points_for_bake(points: &[DrawPoint], closed: bool) -> Vec<DrawPoint> {
    if points.len() < 3 {
        return points.to_vec();
    }

    let count = points.len();
    let last_index = count - 1;
    let mut src = points.to_vec();
    let mut dst = vec![DrawPoint::ZERO; count];

    for _ in 0..BAKE_ITERATIONS {
        if closed {
            for index in 0..=last_index {
                let prev = src[(index + count - 1) % count];
                let current = src[index];
                let next = src[(index + 1) % count];
                dst[index] = DrawPoint::with_pressure_and_timestamp(
                    (prev.x + current.x * 2.0 + next.x) * 0.25,
                    (prev.y + current.y * 2.0 + next.y) * 0.25,
                    current.pressure,
                    current.timestamp,
                );
            }
        } else {
            dst[0] = src[0];
            dst[last_index] = src[last_index];
            for index in 1..last_index {
                let prev = src[index - 1];
                let current = src[index];
                let next = src[index + 1];
                dst[index] = DrawPoint::with_pressure_and_timestamp(
                    (prev.x + current.x * 2.0 + next.x) * 0.25,
                    (prev.y + current.y * 2.0 + next.y) * 0.25,
                    current.pressure,
                    current.timestamp,
                );
            }
        }
        std::mem::swap(&mut src, &mut dst);
    }

    src
}

fn same_location(a: DrawPoint, b: DrawPoint) -> bool {
    a.x == b.x && a.y == b.y
}

fn append_smoothed_point(
    world_points: &mut Vec<DrawPoint>,
    current_position: DrawPoint,
    stroke_width: f64,
    allow_tail_replace: bool,
) -> FreeDrawPointMutation {
    if world_points.len() < 2 {
        world_points.push(current_position);
        return FreeDrawPointMutation::appended(current_position);
    }

    let last = world_points[world_points.len() - 1];
    let min_distance = BASE_MIN_DISTANCE.max(stroke_width * 0.75);
    if last.distance_squared(current_position) < min_distance * min_distance {
        return FreeDrawPointMutation::none();
    }

    let smoothed = DrawPoint::with_pressure_and_timestamp(
        last.x * SMOOTHING_ALPHA + current_position.x * (1.0 - SMOOTHING_ALPHA),
        last.y * SMOOTHING_ALPHA + current_position.y * (1.0 - SMOOTHING_ALPHA),
        current_position.pressure,
        current_position.timestamp,
    );

    if allow_tail_replace && should_replace_tail_point(world_points, smoothed, stroke_width) {
        if let Some(last_point) = world_points.last_mut() {
            *last_point = smoothed;
        }
        return FreeDrawPointMutation::replaced(smoothed);
    }

    world_points.push(smoothed);
    FreeDrawPointMutation::appended(smoothed)
}

fn should_replace_tail_point(
    world_points: &[DrawPoint],
    candidate: DrawPoint,
    stroke_width: f64,
) -> bool {
    if world_points.len() < 3 {
        return false;
    }

    let previous = world_points[world_points.len() - 1];
    let previous_previous = world_points[world_points.len() - 2];
    let seg_x = previous.x - previous_previous.x;
    let seg_y = previous.y - previous_previous.y;
    let next_x = candidate.x - previous.x;
    let next_y = candidate.y - previous.y;

    let seg_length_sq = seg_x * seg_x + seg_y * seg_y;
    let next_length_sq = next_x * next_x + next_y * next_y;
    if seg_length_sq <= LENGTH_EPSILON || next_length_sq <= LENGTH_EPSILON {
        return false;
    }

    let dot = seg_x * next_x + seg_y * next_y;
    if dot <= 0.0 {
        return false;
    }

    let seg_length = seg_length_sq.sqrt();
    let next_length = next_length_sq.sqrt();
    let sin_turn = (seg_x * next_y - seg_y * next_x).abs() / (seg_length * next_length);
    if sin_turn > TAIL_REPLACE_MAX_TURN_SIN {
        return false;
    }

    let line_distance = (seg_x * next_y - seg_y * next_x).abs() / seg_length;
    let line_distance_tolerance = 0.5_f64.max(stroke_width * 0.35);
    line_distance <= line_distance_tolerance
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct FreeDrawPointMutation {
    has_change: bool,
    changed_point: Option<DrawPoint>,
    appended_point: Option<DrawPoint>,
}

impl FreeDrawPointMutation {
    fn none() -> Self {
        Self {
            has_change: false,
            changed_point: None,
            appended_point: None,
        }
    }

    fn appended(point: DrawPoint) -> Self {
        Self {
            has_change: true,
            changed_point: Some(point),
            appended_point: Some(point),
        }
    }

    fn replaced(point: DrawPoint) -> Self {
        Self {
            has_change: true,
            changed_point: Some(point),
            appended_point: None,
        }
    }
}

fn start_line_segment(world_points: &mut Vec<DrawPoint>, current_position: DrawPoint) {
    if world_points.is_empty() {
        world_points.push(current_position);
    }
    world_points.push(current_position);
}

fn update_line_segment(world_points: &mut Vec<DrawPoint>, current_position: DrawPoint) {
    if world_points.len() < 2 {
        start_line_segment(world_points, current_position);
        return;
    }
    if let Some(last_point) = world_points.last_mut() {
        *last_point = current_position;
    }
}

fn creation_mode_from_world_points(world_points: &[DrawPoint]) -> CreationMode {
    CreationMode::Point(PointCreationMode {
        fixed_points: world_points.to_vec(),
        current_point: world_points.last().copied(),
    })
}

fn session_store() -> &'static Mutex<HashMap<String, FreeDrawCreationSessionData>> {
    static STORE: OnceLock<Mutex<HashMap<String, FreeDrawCreationSessionData>>> = OnceLock::new();
    STORE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn with_creation_session_data<R>(
    element_id: &str,
    f: impl FnOnce(&mut FreeDrawCreationSessionData) -> R,
) -> R {
    let mut store = session_store()
        .lock()
        .expect("free draw creation session mutex poisoned");
    let session = store.entry(element_id.to_owned()).or_default();
    f(session)
}

fn take_creation_session_data(element_id: &str) -> Option<FreeDrawCreationSessionData> {
    let mut store = session_store()
        .lock()
        .expect("free draw creation session mutex poisoned");
    store.remove(element_id)
}
