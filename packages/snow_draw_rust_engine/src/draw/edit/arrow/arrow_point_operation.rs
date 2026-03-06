#![allow(dead_code)]

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::types::arrow::arrow_data::{ArrowBinding, ElbowFixedSegment};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};
use crate::draw::utils::arrow_point_metrics::resolve_arrow_point_loop_threshold;
use crate::draw::utils::camera_zoom::resolve_zoom_adjusted_distance;
use crate::draw::utils::list_equality::{
    fixed_segment_structure_equals, fixed_segment_structure_equals_with_tolerance,
    point_list_equals,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ArrowPointKind {
    Turning,
    Addable,
    LoopStart,
    LoopEnd,
    FocusStart,
    FocusEnd,
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
    pub released_points: Option<Vec<DrawPoint>>,
    pub released_fixed_segments: Option<Vec<ElbowFixedSegment>>,
    focus_start_handle_position: Option<DrawPoint>,
    focus_end_handle_position: Option<DrawPoint>,
    element_space: Option<ElementSpace>,
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
        let element_space = if rotation == 0.0 {
            None
        } else {
            Some(ElementSpace::new(rotation, element_rect.center()))
        };
        let local_start_position =
            element_space.map_or(start_position, |space| space.from_world(start_position));
        let point_position =
            resolve_point_position(&initial_points, point_kind, point_index, arrow_type);

        Self {
            element_id: element_id.into(),
            element_rect,
            rotation,
            start_position: local_start_position,
            initial_points,
            initial_fixed_segments,
            arrow_type,
            point_kind,
            point_index,
            drag_offset: point_position - local_start_position,
            release_fixed_segment,
            delete_point_on_start,
            start_arrowhead,
            end_arrowhead,
            initial_start_binding,
            initial_end_binding,
            has_bindable_targets,
            released_points: None,
            released_fixed_segments: None,
            focus_start_handle_position: None,
            focus_end_handle_position: None,
            element_space,
        }
    }

    pub fn with_released_state(
        mut self,
        points: Option<Vec<DrawPoint>>,
        fixed_segments: Option<Vec<ElbowFixedSegment>>,
    ) -> Self {
        self.released_points = points;
        self.released_fixed_segments = fixed_segments;
        self
    }

    pub fn with_focus_handle_positions(
        mut self,
        focus_start_handle_position: Option<DrawPoint>,
        focus_end_handle_position: Option<DrawPoint>,
    ) -> Self {
        self.focus_start_handle_position = focus_start_handle_position;
        self.focus_end_handle_position = focus_end_handle_position;
        if let Some(endpoint) = resolve_focus_endpoint(self.point_kind) {
            if let Some(point_position) = resolve_focus_handle_position(&self, endpoint) {
                self.drag_offset = point_position - self.start_position;
            }
        }
        self
    }

    pub fn to_local(&self, position: DrawPoint) -> DrawPoint {
        self.element_space
            .map_or(position, |space| space.from_world(position))
    }

    pub fn to_world(&self, position: DrawPoint) -> DrawPoint {
        self.element_space
            .map_or(position, |space| space.to_world(position))
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
    pub view_zoom: f64,
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
            view_zoom: 1.0,
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
        let initial_fixed_segments = normalize_segments(context.initial_fixed_segments.clone());
        if context.delete_point_on_start {
            return ArrowPointTransform {
                current_position: start_position,
                points: context.initial_points.clone(),
                fixed_segments: initial_fixed_segments,
                start_binding: context.initial_start_binding.clone(),
                end_binding: context.initial_end_binding.clone(),
                active_index: Some(context.point_index),
                did_insert: false,
                should_delete: true,
                has_changes: true,
            };
        }

        let mut points = context.initial_points.clone();
        let mut fixed_segments = initial_fixed_segments.clone();
        let mut has_changes = false;
        if context.release_fixed_segment && context.arrow_type == ArrowType::Elbow {
            if let Some(released_points) = context.released_points.clone() {
                points = released_points;
            }
            if let Some(released_fixed_segments) = context.released_fixed_segments.clone() {
                fixed_segments = normalize_segments(released_fixed_segments);
            } else if let Some(previous) = fixed_segments.take() {
                let kept: Vec<_> = previous
                    .into_iter()
                    .filter(|segment| segment.index != context.point_index + 1)
                    .collect();
                fixed_segments = normalize_segments(kept);
            }

            has_changes = !point_list_equals(&context.initial_points, &points)
                || !fixed_segment_structure_equals_with_tolerance(
                    initial_fixed_segments.as_deref(),
                    fixed_segments.as_deref(),
                    1.0,
                );
            has_changes = has_changes || context.released_points.is_some();
        }

        ArrowPointTransform {
            current_position: start_position,
            points,
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
            let drag_offset = resolve_effective_drag_offset(context);
            let target = local_position + drag_offset;
            let snapped = snap_target_to_grid(target, context, options.grid_size);
            local_position = snapped - drag_offset;
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
        let handle_tolerance =
            resolve_zoom_adjusted_distance(options.handle_tolerance, options.view_zoom);

        let result = compute(
            context,
            local_position,
            transform.did_insert,
            start_binding,
            end_binding,
            handle_tolerance,
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

#[derive(Clone, Debug, PartialEq)]
struct BoundarySegmentDragResult {
    points: Vec<DrawPoint>,
    fixed_segments: Vec<ElbowFixedSegment>,
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
    let base_points = context.initial_points.clone();
    let base_fixed_segments = context.initial_fixed_segments.clone();
    let base_fixed_segments_result = normalize_segments(base_fixed_segments.clone());

    let mut target = current_position + resolve_effective_drag_offset(context);
    let mut updated_points = base_points.clone();
    let mut next_did_insert = did_insert;
    let mut next_start_binding = start_binding.clone();
    let mut next_end_binding = end_binding.clone();
    let threshold_sq = handle_tolerance * handle_tolerance;
    let active_index: usize;

    if let Some(endpoint) = resolve_focus_endpoint(context.point_kind) {
        return compute_focus(
            context,
            base_points,
            base_fixed_segments_result,
            target,
            start_binding,
            end_binding,
            endpoint,
        );
    }

    if context.point_kind == ArrowPointKind::Addable {
        if !is_valid_addable(context.point_index, base_points.len()) {
            return no_op(
                base_points,
                false,
                next_start_binding,
                next_end_binding,
                base_fixed_segments_result,
            );
        }

        if context.arrow_type == ArrowType::Elbow {
            return compute_elbow_addable(
                context,
                target,
                base_points,
                base_fixed_segments,
                next_start_binding,
                next_end_binding,
            );
        }

        if !next_did_insert {
            if current_position.distance_squared(context.start_position) < threshold_sq {
                return no_op(
                    base_points,
                    false,
                    next_start_binding,
                    next_end_binding,
                    base_fixed_segments_result,
                );
            }
            next_did_insert = true;
        }
        active_index = context.point_index + 1;
        updated_points.insert(active_index, target);
    } else {
        let Some(index) =
            resolve_dragged_index(context.point_kind, context.point_index, base_points.len())
        else {
            return no_op(
                base_points,
                next_did_insert,
                next_start_binding,
                next_end_binding,
                base_fixed_segments_result,
            );
        };

        let endpoint = if index == 0 {
            Some(ArrowEndpoint::Start)
        } else if index + 1 == base_points.len() {
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
            let reference = if base_points.len() > 1 {
                Some(context.to_world(
                    base_points[if endpoint == ArrowEndpoint::Start {
                        1
                    } else {
                        base_points.len() - 2
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
            if context.arrow_type == ArrowType::Elbow {
                return compute_elbow_endpoint_drag(
                    base_points,
                    base_fixed_segments_result,
                    target,
                    endpoint,
                    start_binding,
                    end_binding,
                    next_start_binding,
                    next_end_binding,
                );
            }
        }

        updated_points[index] = target;
        active_index = index;
    }

    if context.point_kind != ArrowPointKind::Addable
        && (active_index == 0 || active_index + 1 == updated_points.len())
    {
        let loop_threshold = resolve_arrow_point_loop_threshold(handle_tolerance);
        let start = updated_points[0];
        let end = updated_points[updated_points.len() - 1];
        if start.distance_squared(end) <= loop_threshold * loop_threshold {
            if active_index == 0 {
                updated_points[0] = end;
            } else {
                let last = updated_points.len() - 1;
                updated_points[last] = start;
            }
        }
    }

    let should_delete = active_index > 0
        && active_index + 1 < updated_points.len()
        && (updated_points[active_index].distance_squared(updated_points[active_index - 1])
            <= threshold_sq
            || updated_points[active_index].distance_squared(updated_points[active_index + 1])
                <= threshold_sq);
    let has_changes = !point_list_equals(&base_points, &updated_points) || next_did_insert;
    let binding_changed = next_start_binding != start_binding || next_end_binding != end_binding;

    Computation {
        points: updated_points,
        did_insert: next_did_insert,
        should_delete,
        active_index: Some(active_index),
        has_changes: has_changes || binding_changed,
        start_binding: next_start_binding,
        end_binding: next_end_binding,
        fixed_segments: base_fixed_segments_result,
    }
}

fn compute_focus(
    context: &ArrowPointEditContext,
    base_points: Vec<DrawPoint>,
    base_fixed_segments: Option<Vec<ElbowFixedSegment>>,
    target: DrawPoint,
    start_binding: Option<ArrowBinding>,
    end_binding: Option<ArrowBinding>,
    endpoint: ArrowEndpoint,
) -> Computation {
    if context.arrow_type == ArrowType::Elbow || base_points.is_empty() {
        return no_op(
            base_points,
            false,
            start_binding,
            end_binding,
            base_fixed_segments,
        );
    }

    let mut updated_points = base_points.clone();
    let active_index = match endpoint {
        ArrowEndpoint::Start => 0,
        ArrowEndpoint::End => updated_points.len() - 1,
    };
    updated_points[active_index] = target;

    Computation {
        has_changes: !point_list_equals(&base_points, &updated_points),
        points: updated_points,
        did_insert: false,
        should_delete: false,
        active_index: Some(active_index),
        start_binding,
        end_binding,
        fixed_segments: base_fixed_segments,
    }
}

fn compute_elbow_endpoint_drag(
    base_points: Vec<DrawPoint>,
    base_fixed_segments: Option<Vec<ElbowFixedSegment>>,
    target: DrawPoint,
    endpoint: ArrowEndpoint,
    start_binding: Option<ArrowBinding>,
    end_binding: Option<ArrowBinding>,
    next_start_binding: Option<ArrowBinding>,
    next_end_binding: Option<ArrowBinding>,
) -> Computation {
    if base_points.len() < 2 {
        return no_op(
            base_points,
            false,
            next_start_binding,
            next_end_binding,
            base_fixed_segments,
        );
    }

    let updated_points = match endpoint {
        ArrowEndpoint::Start => vec![target, base_points[base_points.len() - 1]],
        ArrowEndpoint::End => vec![base_points[0], target],
    };
    let bindings_changed = next_start_binding != start_binding || next_end_binding != end_binding;
    let segments_cleared = base_fixed_segments.is_some();

    Computation {
        has_changes: !point_list_equals(&base_points, &updated_points)
            || bindings_changed
            || segments_cleared,
        points: updated_points,
        did_insert: false,
        should_delete: false,
        active_index: Some(match endpoint {
            ArrowEndpoint::Start => 0,
            ArrowEndpoint::End => 1,
        }),
        start_binding: next_start_binding,
        end_binding: next_end_binding,
        fixed_segments: None,
    }
}

fn compute_elbow_addable(
    context: &ArrowPointEditContext,
    target: DrawPoint,
    base_points: Vec<DrawPoint>,
    base_fixed_segments: Vec<ElbowFixedSegment>,
    start_binding: Option<ArrowBinding>,
    end_binding: Option<ArrowBinding>,
) -> Computation {
    let segment_index = context.point_index + 1;
    let start = base_points[segment_index - 1];
    let end = base_points[segment_index];
    let is_horizontal = (start.y - end.y).abs() <= (start.x - end.x).abs();

    let is_boundary_segment = segment_index == 1 || segment_index == base_points.len() - 1;
    if is_boundary_segment {
        let boundary = apply_boundary_segment_drag(
            &base_points,
            &base_fixed_segments,
            segment_index,
            target,
            is_horizontal,
        );
        let fixed_segments_result = normalize_segments(boundary.fixed_segments.clone());
        let points_changed = !point_list_equals(&base_points, &boundary.points);
        let segments_changed = !fixed_segment_structure_equals_with_tolerance(
            Some(base_fixed_segments.as_slice()),
            fixed_segments_result.as_deref(),
            1.0,
        );

        return Computation {
            points: boundary.points,
            did_insert: false,
            should_delete: false,
            active_index: Some(if segment_index == 1 {
                context.point_index + 1
            } else {
                context.point_index
            }),
            has_changes: points_changed || segments_changed,
            start_binding,
            end_binding,
            fixed_segments: fixed_segments_result,
        };
    }

    let mut updated_points = base_points.clone();
    let next_start = if is_horizontal {
        DrawPoint::new(start.x, target.y)
    } else {
        DrawPoint::new(target.x, start.y)
    };
    let next_end = if is_horizontal {
        DrawPoint::new(end.x, target.y)
    } else {
        DrawPoint::new(target.x, end.y)
    };
    updated_points[segment_index - 1] = next_start;
    updated_points[segment_index] = next_end;

    let mut next_fixed_segments = base_fixed_segments.clone();
    if let Some(existing_index) = next_fixed_segments
        .iter()
        .position(|segment| segment.index == segment_index)
    {
        next_fixed_segments[existing_index] = ElbowFixedSegment {
            index: next_fixed_segments[existing_index].index,
            start: next_start,
            end: next_end,
        };
    } else {
        next_fixed_segments.push(ElbowFixedSegment {
            index: segment_index,
            start: next_start,
            end: next_end,
        });
    }
    if let Some(previous_index) = next_fixed_segments
        .iter()
        .position(|segment| segment.index == segment_index - 1)
    {
        let previous = next_fixed_segments[previous_index].clone();
        next_fixed_segments[previous_index] = ElbowFixedSegment {
            index: previous.index,
            start: previous.start,
            end: next_start,
        };
    }
    if let Some(next_index) = next_fixed_segments
        .iter()
        .position(|segment| segment.index == segment_index + 1)
    {
        let next_segment = next_fixed_segments[next_index].clone();
        next_fixed_segments[next_index] = ElbowFixedSegment {
            index: next_segment.index,
            start: next_end,
            end: next_segment.end,
        };
    }

    let fixed_segments_result = normalize_segments(next_fixed_segments);
    let points_changed = !point_list_equals(&base_points, &updated_points);
    let segments_changed = !fixed_segment_structure_equals_with_tolerance(
        Some(base_fixed_segments.as_slice()),
        fixed_segments_result.as_deref(),
        1.0,
    );

    Computation {
        points: updated_points,
        did_insert: false,
        should_delete: false,
        active_index: Some(context.point_index),
        has_changes: points_changed || segments_changed,
        start_binding,
        end_binding,
        fixed_segments: fixed_segments_result,
    }
}

fn apply_boundary_segment_drag(
    base_points: &[DrawPoint],
    base_fixed_segments: &[ElbowFixedSegment],
    segment_index: usize,
    target: DrawPoint,
    is_horizontal: bool,
) -> BoundarySegmentDragResult {
    let is_start = segment_index == 1;
    let is_end = segment_index == base_points.len() - 1;
    let axis = if is_horizontal { target.y } else { target.x };

    let updated_points: Vec<DrawPoint>;
    let moved_segment_index: usize;
    let mut inserted_at_start = false;
    let mut inserted_at_end = false;

    if is_start && is_end {
        inserted_at_start = true;
        inserted_at_end = true;
        let start_point = base_points[0];
        let end_point = base_points[base_points.len() - 1];
        let start_stub = if is_horizontal {
            DrawPoint::new(start_point.x, axis)
        } else {
            DrawPoint::new(axis, start_point.y)
        };
        let end_stub = if is_horizontal {
            DrawPoint::new(end_point.x, axis)
        } else {
            DrawPoint::new(axis, end_point.y)
        };
        updated_points = vec![start_point, start_stub, end_stub, end_point];
        moved_segment_index = 2;
    } else if is_start {
        inserted_at_start = true;
        let start_point = base_points[0];
        let next_point = base_points[1];
        let stub = if is_horizontal {
            DrawPoint::new(start_point.x, axis)
        } else {
            DrawPoint::new(axis, start_point.y)
        };
        let moved = if is_horizontal {
            DrawPoint::new(next_point.x, axis)
        } else {
            DrawPoint::new(axis, next_point.y)
        };
        updated_points = std::iter::once(start_point)
            .chain(std::iter::once(stub))
            .chain(std::iter::once(moved))
            .chain(base_points.iter().copied().skip(2))
            .collect();
        moved_segment_index = 2;
    } else {
        inserted_at_end = true;
        let end_point = base_points[base_points.len() - 1];
        let prev_point = base_points[base_points.len() - 2];
        let moved = if is_horizontal {
            DrawPoint::new(prev_point.x, axis)
        } else {
            DrawPoint::new(axis, prev_point.y)
        };
        let stub = if is_horizontal {
            DrawPoint::new(end_point.x, axis)
        } else {
            DrawPoint::new(axis, end_point.y)
        };
        updated_points = base_points[..base_points.len() - 2]
            .iter()
            .copied()
            .chain(std::iter::once(moved))
            .chain(std::iter::once(stub))
            .chain(std::iter::once(end_point))
            .collect();
        moved_segment_index = segment_index;
    }

    let updated_fixed_segments = build_boundary_fixed_segments(
        base_fixed_segments,
        &updated_points,
        base_points.len(),
        moved_segment_index,
        inserted_at_start,
        inserted_at_end,
    );

    BoundarySegmentDragResult {
        points: updated_points,
        fixed_segments: updated_fixed_segments,
    }
}

fn build_boundary_fixed_segments(
    base_fixed_segments: &[ElbowFixedSegment],
    updated_points: &[DrawPoint],
    original_point_count: usize,
    moved_segment_index: usize,
    inserted_at_start: bool,
    inserted_at_end: bool,
) -> Vec<ElbowFixedSegment> {
    let mut updated = Vec::<ElbowFixedSegment>::new();
    if !(inserted_at_start && inserted_at_end) {
        for segment in base_fixed_segments {
            let Some(mapped_index) = map_boundary_fixed_index(
                segment.index,
                original_point_count,
                inserted_at_start,
                inserted_at_end,
            ) else {
                continue;
            };
            if let Some(rebuilt) = fixed_segment_for_index(updated_points, mapped_index) {
                updated.push(rebuilt);
            }
        }
    }

    if let Some(moved) = fixed_segment_for_index(updated_points, moved_segment_index) {
        updated.retain(|segment| segment.index != moved.index);
        updated.push(moved);
    }

    updated.sort_by_key(|segment| segment.index);
    updated
}

fn map_boundary_fixed_index(
    original_index: usize,
    original_point_count: usize,
    inserted_at_start: bool,
    inserted_at_end: bool,
) -> Option<usize> {
    if inserted_at_start && inserted_at_end {
        return None;
    }
    if inserted_at_start {
        if original_index <= 1 {
            return None;
        }
        return Some(original_index + 1);
    }
    if inserted_at_end {
        let boundary_index = original_point_count.saturating_sub(1);
        if original_index == boundary_index {
            return None;
        }
        return Some(original_index);
    }
    Some(original_index)
}

fn fixed_segment_for_index(points: &[DrawPoint], index: usize) -> Option<ElbowFixedSegment> {
    if index <= 1 || index >= points.len().saturating_sub(1) {
        return None;
    }

    let start = points[index - 1];
    let end = points[index];
    let length = (start.x - end.x).abs() + (start.y - end.y).abs();
    if length <= 1.0 {
        return None;
    }

    Some(ElbowFixedSegment { index, start, end })
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
    previous.did_insert == next.did_insert
        && previous.should_delete == next.should_delete
        && previous.has_changes == next.has_changes
        && previous.active_index == next.active_index
        && previous.start_binding == next.start_binding
        && previous.end_binding == next.end_binding
        && point_list_equals(&previous.points, &next.points)
        && fixed_segment_structure_equals(
            previous.fixed_segments.as_deref(),
            next.fixed_segments.as_deref(),
        )
}

fn requires_binding_lookup(context: &ArrowPointEditContext) -> bool {
    match context.point_kind {
        ArrowPointKind::LoopStart | ArrowPointKind::LoopEnd => true,
        ArrowPointKind::FocusStart | ArrowPointKind::FocusEnd => false,
        ArrowPointKind::Turning => {
            context.point_index == 0 || context.point_index + 1 == context.initial_points.len()
        }
        ArrowPointKind::Addable => false,
    }
}

fn resolve_focus_endpoint(kind: ArrowPointKind) -> Option<ArrowEndpoint> {
    match kind {
        ArrowPointKind::FocusStart => Some(ArrowEndpoint::Start),
        ArrowPointKind::FocusEnd => Some(ArrowEndpoint::End),
        ArrowPointKind::Turning
        | ArrowPointKind::Addable
        | ArrowPointKind::LoopStart
        | ArrowPointKind::LoopEnd => None,
    }
}

fn resolve_focus_handle_position(
    context: &ArrowPointEditContext,
    endpoint: ArrowEndpoint,
) -> Option<DrawPoint> {
    match endpoint {
        ArrowEndpoint::Start => context.focus_start_handle_position,
        ArrowEndpoint::End => context.focus_end_handle_position,
    }
}

fn resolve_effective_drag_offset(context: &ArrowPointEditContext) -> DrawPoint {
    resolve_focus_endpoint(context.point_kind)
        .and_then(|endpoint| resolve_focus_handle_position(context, endpoint))
        .map(|handle_position| handle_position - context.start_position)
        .unwrap_or_else(|| {
            if matches!(
                context.point_kind,
                ArrowPointKind::FocusStart | ArrowPointKind::FocusEnd
            ) {
                DrawPoint::ZERO
            } else {
                context.drag_offset
            }
        })
}

fn resolve_dragged_index(
    kind: ArrowPointKind,
    point_index: usize,
    point_count: usize,
) -> Option<usize> {
    let index = match kind {
        ArrowPointKind::LoopStart => 0,
        ArrowPointKind::LoopEnd => point_count.checked_sub(1)?,
        ArrowPointKind::FocusStart => 0,
        ArrowPointKind::FocusEnd => point_count.checked_sub(1)?,
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
        ArrowPointKind::FocusStart => 0,
        ArrowPointKind::FocusEnd => points.len() - 1,
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

#[cfg(test)]
mod tests {
    use super::*;

    fn test_context(
        point_kind: ArrowPointKind,
        point_index: usize,
        start_position: DrawPoint,
        initial_points: Vec<DrawPoint>,
        initial_fixed_segments: Vec<ElbowFixedSegment>,
        arrow_type: ArrowType,
    ) -> ArrowPointEditContext {
        ArrowPointEditContext::from_start_position(
            "arrow",
            DrawRect::from_ltwh(0.0, 0.0, 200.0, 200.0),
            0.0,
            start_position,
            initial_points,
            initial_fixed_segments,
            arrow_type,
            point_kind,
            point_index,
            false,
            false,
            ArrowheadStyle::None,
            ArrowheadStyle::None,
            None,
            None,
            false,
        )
    }

    #[test]
    fn focus_drag_uses_pointer_delta_without_endpoint_offset() {
        let operation = ArrowPointOperation::new();
        let context = test_context(
            ArrowPointKind::FocusStart,
            0,
            DrawPoint::new(20.0, 10.0),
            vec![DrawPoint::new(0.0, 0.0), DrawPoint::new(100.0, 0.0)],
            vec![],
            ArrowType::Straight,
        );
        let transform = operation.initial_transform(&context, DrawPoint::new(20.0, 10.0));
        let mut binding_lookup = NoopArrowPointBindingLookup;

        let next = operation.update(
            &context,
            &transform,
            DrawPoint::new(30.0, 20.0),
            ArrowPointUpdateOptions::default(),
            &mut binding_lookup,
        );

        assert_eq!(
            next.points,
            vec![DrawPoint::new(30.0, 20.0), DrawPoint::new(100.0, 0.0)]
        );
        assert_eq!(next.active_index, Some(0));
        assert!(next.has_changes);
    }

    #[test]
    fn focus_drag_respects_focus_handle_override() {
        let operation = ArrowPointOperation::new();
        let context = test_context(
            ArrowPointKind::FocusStart,
            0,
            DrawPoint::new(22.0, 12.0),
            vec![DrawPoint::new(0.0, 0.0), DrawPoint::new(100.0, 0.0)],
            vec![],
            ArrowType::Straight,
        )
        .with_focus_handle_positions(Some(DrawPoint::new(20.0, 10.0)), None);
        let transform = operation.initial_transform(&context, DrawPoint::new(22.0, 12.0));
        let mut binding_lookup = NoopArrowPointBindingLookup;

        let next = operation.update(
            &context,
            &transform,
            DrawPoint::new(32.0, 22.0),
            ArrowPointUpdateOptions::default(),
            &mut binding_lookup,
        );

        assert_eq!(context.drag_offset, DrawPoint::new(-2.0, -2.0));
        assert_eq!(
            next.points,
            vec![DrawPoint::new(30.0, 20.0), DrawPoint::new(100.0, 0.0)]
        );
        assert_eq!(next.active_index, Some(0));
    }

    #[test]
    fn elbow_endpoint_drag_clears_fixed_segments_and_uses_endpoints_only() {
        let operation = ArrowPointOperation::new();
        let context = test_context(
            ArrowPointKind::Turning,
            0,
            DrawPoint::new(0.0, 0.0),
            vec![
                DrawPoint::new(0.0, 0.0),
                DrawPoint::new(0.0, 60.0),
                DrawPoint::new(120.0, 60.0),
                DrawPoint::new(120.0, 0.0),
            ],
            vec![ElbowFixedSegment {
                index: 2,
                start: DrawPoint::new(0.0, 60.0),
                end: DrawPoint::new(120.0, 60.0),
            }],
            ArrowType::Elbow,
        );
        let transform = operation.initial_transform(&context, DrawPoint::new(0.0, 0.0));
        let mut binding_lookup = NoopArrowPointBindingLookup;

        let next = operation.update(
            &context,
            &transform,
            DrawPoint::new(10.0, 20.0),
            ArrowPointUpdateOptions::default(),
            &mut binding_lookup,
        );

        assert_eq!(
            next.points,
            vec![DrawPoint::new(10.0, 20.0), DrawPoint::new(120.0, 0.0)]
        );
        assert_eq!(next.fixed_segments, None);
        assert_eq!(next.active_index, Some(0));
        assert!(next.has_changes);
    }
}
