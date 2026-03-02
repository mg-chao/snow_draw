#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_data::{ArrowBinding, ElbowFixedSegment};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};
use crate::draw::utils::arrow_point_metrics::resolve_arrow_point_loop_threshold;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ArrowPointKind {
    Turning,
    Addable,
    LoopStart,
    LoopEnd,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ArrowEndpoint {
    Start,
    End,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowPointEditContext {
    pub element_id: String,
    pub element_rect: DrawRect,
    pub rotation: f64,
    pub start_position: DrawPoint,
    pub initial_points: Vec<DrawPoint>,
    pub initial_fixed_segments: Vec<ElbowFixedSegment>,
    pub arrow_type: ArrowType,
    pub point_kind: ArrowPointKind,
    pub point_index: usize,
    pub drag_offset: DrawPoint,
    pub release_fixed_segment: bool,
    pub delete_point_on_start: bool,
    pub start_arrowhead: ArrowheadStyle,
    pub end_arrowhead: ArrowheadStyle,
    pub initial_start_binding: Option<ArrowBinding>,
    pub initial_end_binding: Option<ArrowBinding>,
    pub has_bindable_targets: bool,
}

impl ArrowPointEditContext {
    #[allow(clippy::too_many_arguments)]
    pub fn from_start_position(
        element_id: impl Into<String>,
        element_rect: DrawRect,
        rotation: f64,
        start_position: DrawPoint,
        initial_points: Vec<DrawPoint>,
        initial_fixed_segments: Vec<ElbowFixedSegment>,
        arrow_type: ArrowType,
        point_kind: ArrowPointKind,
        point_index: usize,
        release_fixed_segment: bool,
        delete_point_on_start: bool,
        start_arrowhead: ArrowheadStyle,
        end_arrowhead: ArrowheadStyle,
        initial_start_binding: Option<ArrowBinding>,
        initial_end_binding: Option<ArrowBinding>,
        has_bindable_targets: bool,
    ) -> Self {
        let point_position =
            resolve_point_position(&initial_points, point_kind, point_index, arrow_type);
        Self {
            element_id: element_id.into(),
            element_rect,
            rotation,
            start_position,
            initial_points,
            initial_fixed_segments,
            arrow_type,
            point_kind,
            point_index,
            drag_offset: point_position - start_position,
            release_fixed_segment,
            delete_point_on_start,
            start_arrowhead,
            end_arrowhead,
            initial_start_binding,
            initial_end_binding,
            has_bindable_targets,
        }
    }

    pub fn to_local(&self, position: DrawPoint) -> DrawPoint {
        position
    }

    pub fn to_world(&self, position: DrawPoint) -> DrawPoint {
        position
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowPointTransform {
    pub current_position: DrawPoint,
    pub points: Vec<DrawPoint>,
    pub fixed_segments: Option<Vec<ElbowFixedSegment>>,
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
    pub active_index: Option<usize>,
    pub did_insert: bool,
    pub should_delete: bool,
    pub has_changes: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowBindingCandidate {
    pub binding: ArrowBinding,
    pub snap_point: DrawPoint,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowPointBindingRequest {
    pub element_id: String,
    pub endpoint: ArrowEndpoint,
    pub world_target: DrawPoint,
    pub existing_binding: Option<ArrowBinding>,
    pub arrow_type: ArrowType,
    pub has_arrowhead: bool,
    pub should_lookup_bindings: bool,
    pub snap_distance: f64,
    pub allow_new_binding: bool,
    pub has_bindable_targets: bool,
    pub reference_point: Option<DrawPoint>,
}

pub trait ArrowPointBindingLookup {
    fn resolve_endpoint_binding_candidate(
        &mut self,
        request: &ArrowPointBindingRequest,
    ) -> Option<ArrowBindingCandidate>;
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct NoopArrowPointBindingLookup;

impl ArrowPointBindingLookup for NoopArrowPointBindingLookup {
    fn resolve_endpoint_binding_candidate(
        &mut self,
        _request: &ArrowPointBindingRequest,
    ) -> Option<ArrowBindingCandidate> {
        None
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ArrowPointUpdateOptions {
    pub handle_tolerance: f64,
    pub snap_to_grid: bool,
    pub grid_size: f64,
    pub should_lookup_bindings: bool,
    pub binding_distance: f64,
    pub allow_new_binding: bool,
}

impl Default for ArrowPointUpdateOptions {
    fn default() -> Self {
        Self {
            handle_tolerance: 6.0,
            snap_to_grid: false,
            grid_size: 0.0,
            should_lookup_bindings: true,
            binding_distance: 0.0,
            allow_new_binding: true,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct ArrowPointOperation;

impl ArrowPointOperation {
    pub const fn new() -> Self {
        Self
    }

    pub fn initial_transform(
        &self,
        context: &ArrowPointEditContext,
        start_position: DrawPoint,
    ) -> ArrowPointTransform {
        let mut fixed_segments = normalize_segments(context.initial_fixed_segments.clone());
        let mut has_changes = false;
        if context.delete_point_on_start {
            return ArrowPointTransform {
                current_position: start_position,
                points: context.initial_points.clone(),
                fixed_segments,
                start_binding: context.initial_start_binding.clone(),
                end_binding: context.initial_end_binding.clone(),
                active_index: Some(context.point_index),
                did_insert: false,
                should_delete: true,
                has_changes: true,
            };
        }
        if context.release_fixed_segment && context.arrow_type == ArrowType::Elbow {
            if let Some(previous) = fixed_segments.take() {
                let kept: Vec<_> = previous
                    .into_iter()
                    .filter(|s| s.index != context.point_index + 1)
                    .collect();
                fixed_segments = normalize_segments(kept);
                has_changes = true;
            }
        }
        ArrowPointTransform {
            current_position: start_position,
            points: context.initial_points.clone(),
            fixed_segments,
            start_binding: context.initial_start_binding.clone(),
            end_binding: context.initial_end_binding.clone(),
            active_index: None,
            did_insert: false,
            should_delete: false,
            has_changes,
        }
    }

    pub fn update(
        &self,
        context: &ArrowPointEditContext,
        transform: &ArrowPointTransform,
        current_position: DrawPoint,
        options: ArrowPointUpdateOptions,
        binding_lookup: &mut dyn ArrowPointBindingLookup,
    ) -> ArrowPointTransform {
        if context.release_fixed_segment || context.delete_point_on_start {
            return transform.clone();
        }
        let mut local_position = context.to_local(current_position);
        if options.snap_to_grid && options.grid_size > 0.0 {
            let target = local_position + context.drag_offset;
            let snapped = snap_target_to_grid(target, context, options.grid_size);
            local_position = snapped - context.drag_offset;
        }
        let start_binding = transform
            .start_binding
            .clone()
            .or_else(|| context.initial_start_binding.clone());
        let end_binding = transform
            .end_binding
            .clone()
            .or_else(|| context.initial_end_binding.clone());
        let should_lookup_bindings = options.should_lookup_bindings
            && requires_binding_lookup(context)
            && (context.has_bindable_targets || start_binding.is_some() || end_binding.is_some());
        let result = compute(
            context,
            local_position,
            transform.did_insert,
            start_binding,
            end_binding,
            options.handle_tolerance,
            should_lookup_bindings,
            options.binding_distance,
            options.allow_new_binding,
            binding_lookup,
        );
        if is_no_op(transform, &result) {
            return transform.clone();
        }
        ArrowPointTransform {
            current_position: local_position,
            points: result.points,
            fixed_segments: result.fixed_segments,
            start_binding: result.start_binding,
            end_binding: result.end_binding,
            active_index: result.active_index,
            did_insert: result.did_insert,
            should_delete: result.should_delete,
            has_changes: result.has_changes,
        }
    }

    pub fn compute_points_for_result(
        &self,
        transform: &ArrowPointTransform,
        apply_deletion: bool,
    ) -> Vec<DrawPoint> {
        if apply_deletion {
            apply_point_deletion(transform)
        } else {
            transform.points.clone()
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
struct Computation {
    points: Vec<DrawPoint>,
    did_insert: bool,
    should_delete: bool,
    active_index: Option<usize>,
    has_changes: bool,
    start_binding: Option<ArrowBinding>,
    end_binding: Option<ArrowBinding>,
    fixed_segments: Option<Vec<ElbowFixedSegment>>,
}

fn compute(
    context: &ArrowPointEditContext,
    current_position: DrawPoint,
    did_insert: bool,
    start_binding: Option<ArrowBinding>,
    end_binding: Option<ArrowBinding>,
    handle_tolerance: f64,
    should_lookup_bindings: bool,
    binding_distance: f64,
    allow_new_binding: bool,
    binding_lookup: &mut dyn ArrowPointBindingLookup,
) -> Computation {
    let mut target = current_position + context.drag_offset;
    let mut points = context.initial_points.clone();
    let mut next_did_insert = did_insert;
    let mut next_start_binding = start_binding.clone();
    let mut next_end_binding = end_binding.clone();
    let threshold_sq = handle_tolerance * handle_tolerance;
    let active_index: usize;

    if context.point_kind == ArrowPointKind::Addable {
        if !is_valid_addable(context.point_index, points.len()) {
            return no_op(
                points,
                false,
                next_start_binding,
                next_end_binding,
                normalize_segments(context.initial_fixed_segments.clone()),
            );
        }
        if context.arrow_type == ArrowType::Elbow {
            return compute_elbow_addable(context, target, next_start_binding, next_end_binding);
        }
        if !next_did_insert {
            if current_position.distance_squared(context.start_position) < threshold_sq {
                return no_op(
                    points,
                    false,
                    next_start_binding,
                    next_end_binding,
                    normalize_segments(context.initial_fixed_segments.clone()),
                );
            }
            next_did_insert = true;
        }
        active_index = context.point_index + 1;
        points.insert(active_index, target);
    } else {
        let Some(index) =
            resolve_dragged_index(context.point_kind, context.point_index, points.len())
        else {
            return no_op(
                points,
                next_did_insert,
                next_start_binding,
                next_end_binding,
                normalize_segments(context.initial_fixed_segments.clone()),
            );
        };
        let endpoint = if index == 0 {
            Some(ArrowEndpoint::Start)
        } else if index + 1 == points.len() {
            Some(ArrowEndpoint::End)
        } else {
            None
        };
        if let Some(endpoint) = endpoint {
            let existing = if endpoint == ArrowEndpoint::Start {
                next_start_binding.clone()
            } else {
                next_end_binding.clone()
            };
            let reference = if points.len() > 1 {
                Some(context.to_world(
                    points[if endpoint == ArrowEndpoint::Start {
                        1
                    } else {
                        points.len() - 2
                    }],
                ))
            } else {
                None
            };
            let candidate =
                binding_lookup.resolve_endpoint_binding_candidate(&ArrowPointBindingRequest {
                    element_id: context.element_id.clone(),
                    endpoint,
                    world_target: context.to_world(target),
                    existing_binding: existing,
                    arrow_type: context.arrow_type,
                    has_arrowhead: if endpoint == ArrowEndpoint::Start {
                        context.start_arrowhead != ArrowheadStyle::None
                    } else {
                        context.end_arrowhead != ArrowheadStyle::None
                    },
                    should_lookup_bindings,
                    snap_distance: binding_distance,
                    allow_new_binding,
                    has_bindable_targets: context.has_bindable_targets,
                    reference_point: reference,
                });
            if let Some(candidate) = candidate {
                target = context.to_local(candidate.snap_point);
                if endpoint == ArrowEndpoint::Start {
                    next_start_binding = Some(candidate.binding);
                } else {
                    next_end_binding = Some(candidate.binding);
                }
            } else if endpoint == ArrowEndpoint::Start {
                next_start_binding = None;
            } else {
                next_end_binding = None;
            }
        }
        points[index] = target;
        active_index = index;
    }

    if context.point_kind != ArrowPointKind::Addable
        && (active_index == 0 || active_index + 1 == points.len())
    {
        let loop_threshold = resolve_arrow_point_loop_threshold(handle_tolerance);
        let start = points[0];
        let end = points[points.len() - 1];
        if start.distance_squared(end) <= loop_threshold * loop_threshold {
            if active_index == 0 {
                points[0] = end;
            } else {
                let last = points.len() - 1;
                points[last] = start;
            }
        }
    }

    let should_delete = active_index > 0
        && active_index + 1 < points.len()
        && (points[active_index].distance_squared(points[active_index - 1]) <= threshold_sq
            || points[active_index].distance_squared(points[active_index + 1]) <= threshold_sq);
    let has_changes = points != context.initial_points
        || next_did_insert
        || next_start_binding != start_binding
        || next_end_binding != end_binding;

    Computation {
        points,
        did_insert: next_did_insert,
        should_delete,
        active_index: Some(active_index),
        has_changes,
        start_binding: next_start_binding,
        end_binding: next_end_binding,
        fixed_segments: normalize_segments(context.initial_fixed_segments.clone()),
    }
}

fn compute_elbow_addable(
    context: &ArrowPointEditContext,
    target: DrawPoint,
    start_binding: Option<ArrowBinding>,
    end_binding: Option<ArrowBinding>,
) -> Computation {
    let segment_index = context.point_index + 1;
    let mut points = context.initial_points.clone();
    let start = points[segment_index - 1];
    let end = points[segment_index];
    let horizontal = (start.y - end.y).abs() <= (start.x - end.x).abs();
    let update = |p: DrawPoint| {
        if horizontal {
            DrawPoint::new(p.x, target.y)
        } else {
            DrawPoint::new(target.x, p.y)
        }
    };
    let is_boundary = segment_index == 1 || segment_index + 1 == points.len();
    let mut fixed = context.initial_fixed_segments.clone();
    if is_boundary {
        if segment_index == 1 {
            let first = points[0];
            let moved = update(points[1]);
            let stub = update(first);
            points = vec![first, stub, moved];
            if context.initial_points.len() > 2 {
                points.extend_from_slice(&context.initial_points[2..]);
            }
        } else {
            let last = points[points.len() - 1];
            let moved = update(points[points.len() - 2]);
            let stub = update(last);
            let mut head = points[..points.len() - 2].to_vec();
            head.push(moved);
            head.push(stub);
            head.push(last);
            points = head;
        }
        fixed = vec![];
    } else {
        let next_start = update(start);
        let next_end = update(end);
        points[segment_index - 1] = next_start;
        points[segment_index] = next_end;
        let replacement = ElbowFixedSegment {
            index: segment_index,
            start: next_start,
            end: next_end,
        };
        if let Some(pos) = fixed.iter().position(|s| s.index == segment_index) {
            fixed[pos] = replacement;
        } else {
            fixed.push(replacement);
        }
    }
    let fixed_segments = normalize_segments(fixed);
    Computation {
        points: points.clone(),
        did_insert: false,
        should_delete: false,
        active_index: Some(if segment_index == 1 {
            context.point_index + 1
        } else {
            context.point_index
        }),
        has_changes: points != context.initial_points
            || fixed_segments.as_deref()
                != normalize_segments(context.initial_fixed_segments.clone()).as_deref(),
        start_binding,
        end_binding,
        fixed_segments,
    }
}

fn no_op(
    points: Vec<DrawPoint>,
    did_insert: bool,
    start_binding: Option<ArrowBinding>,
    end_binding: Option<ArrowBinding>,
    fixed_segments: Option<Vec<ElbowFixedSegment>>,
) -> Computation {
    Computation {
        points,
        did_insert,
        should_delete: false,
        active_index: None,
        has_changes: false,
        start_binding,
        end_binding,
        fixed_segments,
    }
}

fn is_no_op(previous: &ArrowPointTransform, next: &Computation) -> bool {
    previous.points == next.points
        && previous.fixed_segments == next.fixed_segments
        && previous.start_binding == next.start_binding
        && previous.end_binding == next.end_binding
        && previous.active_index == next.active_index
        && previous.did_insert == next.did_insert
        && previous.should_delete == next.should_delete
        && previous.has_changes == next.has_changes
}

fn requires_binding_lookup(context: &ArrowPointEditContext) -> bool {
    match context.point_kind {
        ArrowPointKind::LoopStart | ArrowPointKind::LoopEnd => true,
        ArrowPointKind::Turning => {
            context.point_index == 0 || context.point_index + 1 == context.initial_points.len()
        }
        ArrowPointKind::Addable => false,
    }
}

fn resolve_dragged_index(
    kind: ArrowPointKind,
    point_index: usize,
    point_count: usize,
) -> Option<usize> {
    let index = match kind {
        ArrowPointKind::LoopStart => 0,
        ArrowPointKind::LoopEnd => point_count.checked_sub(1)?,
        ArrowPointKind::Turning | ArrowPointKind::Addable => point_index,
    };
    (index < point_count).then_some(index)
}

fn is_valid_addable(index: usize, point_count: usize) -> bool {
    point_count >= 2 && index < point_count - 1
}

pub fn resolve_point_position(
    points: &[DrawPoint],
    kind: ArrowPointKind,
    index: usize,
    arrow_type: ArrowType,
) -> DrawPoint {
    if points.is_empty() {
        return DrawPoint::ZERO;
    }
    if kind == ArrowPointKind::Addable {
        if !is_valid_addable(index, points.len()) {
            return points[0];
        }
        if arrow_type == ArrowType::Curved && points.len() >= 3 {
            if let Some(point) = ArrowGeometry::calculate_curve_draw_point(points, index, 0.5) {
                return point;
            }
        }
        let start = points[index];
        let end = points[index + 1];
        return DrawPoint::new((start.x + end.x) / 2.0, (start.y + end.y) / 2.0);
    }
    let resolved = match kind {
        ArrowPointKind::LoopStart => 0,
        ArrowPointKind::LoopEnd => points.len() - 1,
        ArrowPointKind::Turning | ArrowPointKind::Addable => index.min(points.len() - 1),
    };
    points[resolved]
}

pub fn apply_point_deletion(transform: &ArrowPointTransform) -> Vec<DrawPoint> {
    let Some(index) = transform.active_index else {
        return transform.points.clone();
    };
    if !transform.should_delete || index == 0 || index + 1 >= transform.points.len() {
        return transform.points.clone();
    }
    let mut points = transform.points.clone();
    points.remove(index);
    points
}

fn snap_target_to_grid(
    target: DrawPoint,
    context: &ArrowPointEditContext,
    grid_size: f64,
) -> DrawPoint {
    if grid_size <= 0.0 {
        return target;
    }
    let world = context.to_world(target);
    let snapped = DrawPoint::new(
        (world.x / grid_size).round() * grid_size,
        (world.y / grid_size).round() * grid_size,
    );
    context.to_local(snapped)
}

fn normalize_segments(segments: Vec<ElbowFixedSegment>) -> Option<Vec<ElbowFixedSegment>> {
    if segments.is_empty() {
        None
    } else {
        Some(segments)
    }
}
