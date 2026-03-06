#![allow(dead_code)]
#![allow(unused_imports)]
#![allow(unused_variables)]

use std::collections::{HashMap, HashSet};

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding as PerpendicularArrowBinding,
    ArrowBindingMode as PerpendicularArrowBindingMode,
};
use crate::draw::elements::types::arrow::arrow_data::{ArrowBinding, ElbowFixedSegment};
use crate::draw::elements::types::arrow::elbow::elbow_constants::ElbowConstants;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::ArrowheadStyle;
use crate::draw::utils::selection_calculator::{ElementState, SelectionCalculator};

use super::elbow_edit_perpendicular as translated_perpendicular;
use super::elbow_router;

/// Cardinal direction used by elbow endpoint editing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ElbowHeading {
    Right,
    Down,
    Left,
    Up,
}

impl ElbowHeading {
    pub const fn dx(self) -> i32 {
        match self {
            Self::Right => 1,
            Self::Down => 0,
            Self::Left => -1,
            Self::Up => 0,
        }
    }

    pub const fn dy(self) -> i32 {
        match self {
            Self::Right => 0,
            Self::Down => 1,
            Self::Left => 0,
            Self::Up => -1,
        }
    }

    pub const fn is_horizontal(self) -> bool {
        matches!(self, Self::Right | Self::Left)
    }

    pub const fn opposite(self) -> Self {
        match self {
            Self::Right => Self::Left,
            Self::Left => Self::Right,
            Self::Up => Self::Down,
            Self::Down => Self::Up,
        }
    }
}

/// Mutable state used while recomputing fixed-segment endpoint drags.
#[derive(Clone, Debug, PartialEq)]
pub struct FixedSegmentPathResult {
    pub points: Vec<DrawPoint>,
    pub fixed_segments: Vec<ElbowFixedSegment>,
}

impl FixedSegmentPathResult {
    pub fn new(points: Vec<DrawPoint>, fixed_segments: Vec<ElbowFixedSegment>) -> Self {
        Self {
            points,
            fixed_segments,
        }
    }

    pub fn copy_with(
        &self,
        points: Option<Vec<DrawPoint>>,
        fixed_segments: Option<Vec<ElbowFixedSegment>>,
    ) -> Self {
        Self {
            points: points.unwrap_or_else(|| self.points.clone()),
            fixed_segments: fixed_segments.unwrap_or_else(|| self.fixed_segments.clone()),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
struct RerouteResult {
    state: FixedSegmentPathResult,
    // Some(true): start span rerouted.
    // Some(false): end span rerouted.
    // None: unchanged.
    rerouted_side: Option<bool>,
}

#[derive(Clone, Debug, PartialEq)]
struct SlidePointsResult {
    points: Vec<DrawPoint>,
    moved: bool,
}

#[derive(Clone, Debug, PartialEq)]
struct WalkRunResult {
    indices: Vec<usize>,
    min_var: f64,
    max_var: f64,
}

/// Input context used by endpoint drag reconciliation.
#[derive(Clone, Debug)]
pub struct ElbowEditContext {
    pub element: ElementState,
    pub elements_by_id: HashMap<String, ElementState>,

    pub base_points: Vec<DrawPoint>,
    pub incoming_points: Vec<DrawPoint>,
    pub fixed_segments: Vec<ElbowFixedSegment>,

    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
    pub start_arrowhead: ArrowheadStyle,
    pub end_arrowhead: ArrowheadStyle,

    pub start_active: bool,
    pub end_active: bool,

    pub start_was_bound: bool,
    pub end_was_bound: bool,

    pub start_binding_removed: bool,
    pub end_binding_removed: bool,
}

impl ElbowEditContext {
    pub fn has_bindings(&self) -> bool {
        self.start_binding.is_some() || self.end_binding.is_some()
    }

    pub fn has_bound_start(&self) -> bool {
        self.start_binding.as_ref().is_some_and(|binding| {
            self.elements_by_id
                .contains_key(binding.element_id.as_str())
        })
    }

    pub fn has_bound_end(&self) -> bool {
        self.end_binding.as_ref().is_some_and(|binding| {
            self.elements_by_id
                .contains_key(binding.element_id.as_str())
        })
    }

    pub fn is_fully_unbound(&self) -> bool {
        self.start_binding.is_none() && self.end_binding.is_none()
    }

    /// Resolves the heading required by a bound endpoint.
    pub fn resolve_required_heading(
        &self,
        is_start: bool,
        point: DrawPoint,
    ) -> Option<ElbowHeading> {
        let binding = if is_start {
            self.start_binding.as_ref()
        } else {
            self.end_binding.as_ref()
        }?;
        let heading = ElbowGeometry::resolve_bound_heading(binding, &self.elements_by_id, point)?;
        Some(if is_start {
            heading
        } else {
            heading.opposite()
        })
    }
}

/// Applies endpoint drag updates while preserving fixed segments as much as possible.
pub fn apply_endpoint_drag_with_fixed_segments(
    context: &ElbowEditContext,
) -> FixedSegmentPathResult {
    if context.base_points.len() < 2 {
        return FixedSegmentPathResult::new(
            context.incoming_points.clone(),
            context.fixed_segments.clone(),
        );
    }

    // Step 1: apply endpoint overrides to a stable reference path.
    let reference_points = if context.incoming_points.len() == 2
        && context.base_points.len() > context.incoming_points.len()
    {
        context.base_points.clone()
    } else if ElbowGeometry::point_lists_equal_except_endpoints(
        &context.base_points,
        &context.incoming_points,
    ) {
        context.base_points.clone()
    } else {
        context.incoming_points.clone()
    };

    let mut updated = reference_points;
    updated[0] = *context
        .incoming_points
        .first()
        .unwrap_or_else(|| context.base_points.first().expect("base start exists"));
    let last_index = updated.len() - 1;
    updated[last_index] = *context
        .incoming_points
        .last()
        .unwrap_or_else(|| context.base_points.last().expect("base end exists"));

    let mut state = FixedSegmentPathResult::new(updated, context.fixed_segments.clone());

    // Step 2: reroute the active span or adopt a baseline route.
    let local = reroute_active_span_if_needed(context, &state);
    state = local.state;
    if local.rerouted_side.is_none() {
        state = adopt_baseline_route_if_needed(context, &state);
    }

    // Step 3: reroute spans freed by binding removal.
    state = reroute_released_binding_span(
        context,
        &state,
        local.rerouted_side == Some(true),
        local.rerouted_side == Some(false),
    );

    // Step 4: enforce orthogonality.
    state = enforce_orthogonality(context, &state);

    // Step 5: sync fixed segments and collapse released-binding stubs.
    if (context.start_binding_removed || context.end_binding_removed)
        && !state.fixed_segments.is_empty()
    {
        let merged = merge_fixed_segments_with_collinear_neighbors(
            state.points.clone(),
            sync_fixed_segments_to_points(&state.points, &state.fixed_segments),
            true,
        );
        if merged.fixed_segments.len() == state.fixed_segments.len() {
            state = merged;
        }
    }

    let synced = sync_fixed_segments_to_points(&state.points, &state.fixed_segments);
    if context.is_fully_unbound() {
        return FixedSegmentPathResult::new(state.points, synced);
    }

    // Step 6: keep bound endpoint neighborhood perpendicular in world space.
    let perpendicular = ensure_perpendicular_bindings(context, state.points, synced);
    align_fixed_segments_to_bound_lanes(context, perpendicular.points, perpendicular.fixed_segments)
}

fn build_fallback_points_for_active_fixed(
    start: DrawPoint,
    end: DrawPoint,
    fixed_segment: &ElbowFixedSegment,
    required_heading: ElbowHeading,
    start_bound: bool,
) -> Option<Vec<DrawPoint>> {
    if start_bound {
        let mut reversed = build_fallback_points_for_active_fixed(
            end,
            start,
            fixed_segment,
            required_heading.opposite(),
            false,
        )?;
        reversed.reverse();
        return Some(reversed);
    }

    let horizontal = fixed_segment_is_horizontal(fixed_segment);
    let axis = fixed_segment_axis_value(fixed_segment);
    let padding = ElbowConstants::DIRECTION_FIX_PADDING;

    let travel = |point: DrawPoint| if horizontal { point.x } else { point.y };
    let perp = |point: DrawPoint| if horizontal { point.y } else { point.x };

    let mut mid = (travel(start) + travel(end)) / 2.0;
    let pos = if horizontal {
        ElbowHeading::Right
    } else {
        ElbowHeading::Down
    };
    let neg = if horizontal {
        ElbowHeading::Left
    } else {
        ElbowHeading::Up
    };

    if required_heading == pos && mid >= travel(end) {
        mid = travel(end) - padding;
    } else if required_heading == neg && mid <= travel(end) {
        mid = travel(end) + padding;
    }

    let pt = |t: f64, p: f64| {
        if horizontal {
            DrawPoint::new(t, p)
        } else {
            DrawPoint::new(p, t)
        }
    };

    let points = vec![
        start,
        pt(travel(start), axis),
        pt(mid, axis),
        pt(mid, perp(end)),
        end,
    ];

    let simplified = ElbowGeometry::simplify_path(&points);
    if simplified.len() >= 2 {
        Some(simplified)
    } else {
        None
    }
}

fn build_fallback_path_for_active_span(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
    active_segment: &ElbowFixedSegment,
    required_heading: ElbowHeading,
    start_bound: bool,
) -> Option<FixedSegmentPathResult> {
    if points.len() < 2 || fixed_segments.is_empty() {
        return None;
    }

    let anchor_index = if start_bound {
        active_segment.index
    } else {
        active_segment.index.saturating_sub(1)
    };

    if anchor_index == 0 || anchor_index >= points.len() {
        return None;
    }

    let sub_path = build_fallback_points_for_active_fixed(
        if start_bound {
            points[0]
        } else {
            points[anchor_index]
        },
        if start_bound {
            points[anchor_index]
        } else {
            points[points.len() - 1]
        },
        active_segment,
        required_heading,
        start_bound,
    )?;

    let stitched = stitch_sub_path(
        points,
        if start_bound { 0 } else { anchor_index },
        if start_bound {
            anchor_index
        } else {
            points.len() - 1
        },
        &sub_path,
        fixed_segments,
    );

    if stitched.fixed_segments.len() != fixed_segments.len() {
        return None;
    }

    let simplified = normalize_fixed_segment_path(
        stitched.points.clone(),
        stitched.fixed_segments.clone(),
        true,
        false,
    );

    Some(if simplified.fixed_segments.len() == fixed_segments.len() {
        simplified
    } else {
        stitched
    })
}

fn fixed_segment_axes_stable(
    original: &[ElbowFixedSegment],
    updated: &[ElbowFixedSegment],
) -> bool {
    if original.len() != updated.len() {
        return false;
    }

    for (left, right) in original.iter().zip(updated.iter()) {
        if fixed_segment_is_horizontal(left) != fixed_segment_is_horizontal(right) {
            return false;
        }
        if (fixed_segment_axis_value(left) - fixed_segment_axis_value(right)).abs()
            > ElbowConstants::DEDUP_THRESHOLD
        {
            return false;
        }
    }

    true
}

fn try_active_span_fallback(
    state: &FixedSegmentPathResult,
    active_fixed: &ElbowFixedSegment,
    required_heading: ElbowHeading,
    active_is_start: bool,
) -> Option<RerouteResult> {
    let fallback = build_fallback_path_for_active_span(
        &state.points,
        &state.fixed_segments,
        active_fixed,
        required_heading,
        active_is_start,
    )?;

    if !fixed_segment_axes_stable(&state.fixed_segments, &fallback.fixed_segments) {
        return None;
    }

    Some(RerouteResult {
        state: state.copy_with(
            Some(fallback.points.clone()),
            Some(fallback.fixed_segments.clone()),
        ),
        rerouted_side: Some(active_is_start),
    })
}

fn reroute_active_span_if_needed(
    context: &ElbowEditContext,
    state: &FixedSegmentPathResult,
) -> RerouteResult {
    let no_change = RerouteResult {
        state: state.clone(),
        rerouted_side: None,
    };

    if context.start_active == context.end_active {
        return no_change;
    }

    let active_is_start = context.start_active;
    if state.fixed_segments.is_empty() {
        return no_change;
    }

    let active_fixed = if active_is_start {
        state.fixed_segments.first().cloned()
    } else {
        state.fixed_segments.last().cloned()
    };
    let Some(active_fixed) = active_fixed else {
        return no_change;
    };

    let anchor_index = if active_is_start {
        active_fixed.index
    } else {
        active_fixed.index.saturating_sub(1)
    };

    if anchor_index == 0 || anchor_index >= state.points.len() {
        return no_change;
    }

    let active_point = if active_is_start {
        state.points[0]
    } else {
        state.points[state.points.len() - 1]
    };
    let required_heading = context.resolve_required_heading(active_is_start, active_point);

    let start_local = if active_is_start {
        state.points[0]
    } else {
        state.points[anchor_index]
    };
    let end_local = if active_is_start {
        state.points[anchor_index]
    } else {
        state.points[state.points.len() - 1]
    };

    let routed = route_local_path(
        &context.element,
        &context.elements_by_id,
        start_local,
        end_local,
        if active_is_start {
            context.start_arrowhead
        } else {
            ArrowheadStyle::None
        },
        if active_is_start {
            ArrowheadStyle::None
        } else {
            context.end_arrowhead
        },
        if active_is_start {
            context.start_binding.as_ref()
        } else {
            None
        },
        if active_is_start {
            None
        } else {
            context.end_binding.as_ref()
        },
        if active_is_start {
            None
        } else {
            Some(&active_fixed)
        },
        if active_is_start {
            Some(&active_fixed)
        } else {
            None
        },
    );

    if routed.len() < 2 {
        return no_change;
    }

    let stitch_result = stitch_sub_path(
        &state.points,
        if active_is_start { 0 } else { anchor_index },
        if active_is_start {
            anchor_index
        } else {
            state.points.len() - 1
        },
        &routed,
        &state.fixed_segments,
    );
    let stitched = stitch_result.points.clone();

    if ElbowGeometry::point_lists_equal(&stitched, &state.points) {
        return no_change;
    }

    let changed_structure = stitched.len() != state.points.len()
        || !ElbowGeometry::point_lists_equal_except_endpoints(&stitched, &state.points);

    let updated_fixed = if changed_structure {
        stitch_result.fixed_segments
    } else {
        sync_fixed_segments_to_points(&stitched, &state.fixed_segments)
    };

    // When reindexing lost a segment, axes drifted, or heading flipped, use fallback.
    let axes_stable = updated_fixed.len() == state.fixed_segments.len()
        && fixed_segment_axes_stable(&state.fixed_segments, &updated_fixed);

    let heading_flipped = axes_stable
        && required_heading.is_some_and(|heading| {
            let active_updated_segment = if active_is_start {
                updated_fixed.first()
            } else {
                updated_fixed.last()
            };
            active_updated_segment.is_some_and(|segment| {
                heading.is_horizontal() == fixed_segment_is_horizontal(segment)
                    && !direction_matches(segment.start, segment.end, heading)
            })
        });

    if !axes_stable || heading_flipped {
        let Some(required_heading) = required_heading else {
            return no_change;
        };
        return try_active_span_fallback(state, &active_fixed, required_heading, active_is_start)
            .unwrap_or(no_change);
    }

    RerouteResult {
        state: state.copy_with(Some(stitched), Some(updated_fixed)),
        rerouted_side: Some(active_is_start),
    }
}

fn adopt_baseline_route_if_needed(
    context: &ElbowEditContext,
    state: &FixedSegmentPathResult,
) -> FixedSegmentPathResult {
    let no_change = state.clone();

    if !context.has_bindings() || (!context.has_bound_start() && !context.has_bound_end()) {
        return no_change;
    }

    let start_active_bound = context.has_bound_start()
        && context.start_active
        && context.start_was_bound
        && !context.start_binding_removed;

    let end_active_bound = context.has_bound_end()
        && context.end_active
        && context.end_was_bound
        && !context.end_binding_removed;

    let force_baseline = start_active_bound || end_active_bound;
    let single_active_bound = start_active_bound != end_active_bound;
    let active_start = start_active_bound;

    let active_segment =
        if force_baseline && !state.fixed_segments.is_empty() && single_active_bound {
            if active_start {
                state.fixed_segments.first().cloned()
            } else {
                state.fixed_segments.last().cloned()
            }
        } else {
            None
        };

    let required_heading = active_segment.as_ref().and_then(|_| {
        let point = if active_start {
            state.points[0]
        } else {
            state.points[state.points.len() - 1]
        };
        context.resolve_required_heading(active_start, point)
    });

    if !context.fixed_segments.is_empty()
        && (context.has_bound_start() != context.has_bound_end())
        && !force_baseline
    {
        return no_change;
    }

    // Strategy 1: single-fixed-segment fallback.
    if force_baseline
        && state.fixed_segments.len() == 1
        && active_segment.is_some()
        && required_heading.is_some()
    {
        let segment = active_segment.as_ref().expect("checked above");
        let heading = required_heading.expect("checked above");
        if let Some(points) = build_fallback_points_for_active_fixed(
            state.points[0],
            state.points[state.points.len() - 1],
            segment,
            heading,
            active_start,
        ) {
            let reindexed = reindex_fixed_segments(&points, std::slice::from_ref(segment));
            if !reindexed.is_empty() {
                return state.copy_with(Some(points), Some(reindexed));
            }
        }
    }

    // Strategy 2: map fixed segments onto a fresh baseline route.
    let baseline = route_local_path(
        &context.element,
        &context.elements_by_id,
        state.points[0],
        state.points[state.points.len() - 1],
        context.start_arrowhead,
        context.end_arrowhead,
        context.start_binding.as_ref(),
        context.end_binding.as_ref(),
        None,
        None,
    );

    if let Some(mapped) = map_fixed_segments_to_baseline(
        &baseline,
        &state.fixed_segments,
        active_segment.as_ref(),
        true,
        true,
    ) {
        let adopted = if force_baseline {
            normalize_fixed_segment_path(mapped.points, mapped.fixed_segments, true, false)
        } else {
            mapped
        };
        return state.copy_with(Some(adopted.points), Some(adopted.fixed_segments));
    }

    // Strategy 3: active-span fallback via the fixed segment.
    if force_baseline && active_segment.is_some() && required_heading.is_some() {
        if let Some(fallback) = build_fallback_path_for_active_span(
            &state.points,
            &state.fixed_segments,
            active_segment.as_ref().expect("checked above"),
            required_heading.expect("checked above"),
            active_start,
        ) {
            return state.copy_with(Some(fallback.points), Some(fallback.fixed_segments));
        }
    }

    no_change
}

fn reroute_released_binding_span(
    context: &ElbowEditContext,
    state: &FixedSegmentPathResult,
    skip_start: bool,
    skip_end: bool,
) -> FixedSegmentPathResult {
    if !context.start_binding_removed && !context.end_binding_removed {
        return state.clone();
    }
    if state.points.len() < 2 {
        return state.clone();
    }

    let mut points = state.points.clone();
    let mut fixed = state.fixed_segments.clone();

    for is_start in [true, false] {
        if !(if is_start {
            context.start_binding_removed
        } else {
            context.end_binding_removed
        }) {
            continue;
        }
        if (is_start && skip_start) || (!is_start && skip_end) {
            continue;
        }

        let boundary_fixed = if fixed.is_empty() {
            None
        } else if is_start {
            fixed.first().cloned()
        } else {
            fixed.last().cloned()
        };

        let start_index = if is_start {
            0
        } else {
            boundary_fixed.as_ref().map_or(0, |segment| segment.index)
        };

        let end_index = if is_start {
            boundary_fixed
                .as_ref()
                .map_or(points.len() - 1, |segment| segment.index.saturating_sub(1))
        } else {
            points.len() - 1
        };

        if start_index >= points.len() || end_index >= points.len() || start_index >= end_index {
            continue;
        }

        let routed = route_local_path(
            &context.element,
            &context.elements_by_id,
            points[start_index],
            points[end_index],
            if start_index == 0 {
                context.start_arrowhead
            } else {
                ArrowheadStyle::None
            },
            if end_index + 1 == points.len() {
                context.end_arrowhead
            } else {
                ArrowheadStyle::None
            },
            if start_index == 0 {
                context.start_binding.as_ref()
            } else {
                None
            },
            if end_index + 1 == points.len() {
                context.end_binding.as_ref()
            } else {
                None
            },
            if is_start {
                None
            } else {
                boundary_fixed.as_ref()
            },
            if is_start {
                boundary_fixed.as_ref()
            } else {
                None
            },
        );

        let result = stitch_sub_path(&points, start_index, end_index, &routed, &fixed);
        points = result.points;
        fixed = result.fixed_segments;
    }

    state.copy_with(Some(points), Some(fixed))
}

fn enforce_orthogonality(
    context: &ElbowEditContext,
    state: &FixedSegmentPathResult,
) -> FixedSegmentPathResult {
    let mut points = apply_fixed_segments_to_points(&state.points, &state.fixed_segments);
    let mut fixed_segments = state.fixed_segments.clone();

    // Re-route diagonal drift for fully unbound arrows.
    if context.is_fully_unbound() && ElbowGeometry::has_diagonal_segments(&points) {
        let baseline = route_local_path(
            &context.element,
            &context.elements_by_id,
            points[0],
            points[points.len() - 1],
            context.start_arrowhead,
            context.end_arrowhead,
            None,
            None,
            None,
            None,
        );

        if let Some(mapped) =
            map_fixed_segments_to_baseline(&baseline, &fixed_segments, None, false, false)
        {
            if mapped.fixed_segments.len() == fixed_segments.len() {
                points = mapped.points;
                fixed_segments = mapped.fixed_segments;
            }
        }
    }

    // Snap unbound endpoint neighbors to nearest axis.
    if points.len() > 1 {
        let mut updated = points.clone();
        for is_start in [true, false] {
            if (is_start && context.has_bound_start()) || (!is_start && context.has_bound_end()) {
                continue;
            }
            let last_index = updated.len() - 1;
            let endpoint_index = if is_start { 0 } else { last_index };
            let neighbor_index = if is_start { 1 } else { last_index - 1 };

            let endpoint = updated[endpoint_index];
            let neighbor = updated[neighbor_index];

            let adjacent_fixed = fixed_segment_is_horizontal_at_index(
                &fixed_segments,
                if is_start { 2 } else { neighbor_index },
            );

            let snap_x = adjacent_fixed.unwrap_or_else(|| {
                (neighbor.x - endpoint.x).abs() <= (neighbor.y - endpoint.y).abs()
            });

            updated[neighbor_index] = if snap_x {
                with_x(neighbor, endpoint.x)
            } else {
                with_y(neighbor, endpoint.y)
            };
        }
        points = updated;
    }

    points = apply_fixed_segments_to_points(&points, &fixed_segments);

    if context.is_fully_unbound() {
        let merged = merge_fixed_segments_with_collinear_neighbors(
            points.clone(),
            fixed_segments.clone(),
            false,
        );
        if merged.fixed_segments.len() == fixed_segments.len() {
            return merged;
        }
    }

    state.copy_with(Some(points), Some(fixed_segments))
}

fn align_fixed_segments_to_bound_lanes(
    context: &ElbowEditContext,
    points: Vec<DrawPoint>,
    fixed_segments: Vec<ElbowFixedSegment>,
) -> FixedSegmentPathResult {
    let start_binding = context.start_binding.as_ref();
    let end_binding = context.end_binding.as_ref();

    if points.len() < 2
        || fixed_segments.is_empty()
        || (start_binding.is_none() && end_binding.is_none())
    {
        return FixedSegmentPathResult::new(points, fixed_segments);
    }

    let space = ElementSpace::new(context.element.rotation, context.element.rect.center());
    let mut world_points: Vec<DrawPoint> = points
        .iter()
        .copied()
        .map(|point| space.to_world(point))
        .collect();
    let mut changed = false;

    for (binding, is_start) in [(start_binding, true), (end_binding, false)] {
        let Some(binding) = binding else {
            continue;
        };

        let result = slide_fixed_span_for_bound_endpoint(
            &world_points,
            &fixed_segments,
            binding,
            &context.elements_by_id,
            is_start,
        );

        if result.moved {
            world_points = result.points;
            changed = true;
        }
    }

    if !changed {
        return FixedSegmentPathResult::new(points, fixed_segments);
    }

    let mut local_points: Vec<DrawPoint> = world_points
        .iter()
        .copied()
        .map(|point| space.from_world(point))
        .collect();

    while local_points.len() > 1 {
        let last = local_points[local_points.len() - 1];
        let prev = local_points[local_points.len() - 2];
        if ElbowGeometry::manhattan_distance(last, prev) > ElbowConstants::DEDUP_THRESHOLD {
            break;
        }
        local_points.pop();
    }

    merge_fixed_segments_with_collinear_neighbors(
        local_points.clone(),
        sync_fixed_segments_to_points(&local_points, &fixed_segments),
        true,
    )
}

fn slide_fixed_span_for_bound_endpoint(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
    binding: &ArrowBinding,
    elements_by_id: &HashMap<String, ElementState>,
    is_start: bool,
) -> SlidePointsResult {
    let no_move = SlidePointsResult {
        points: points.to_vec(),
        moved: false,
    };

    let endpoint = if is_start {
        points[0]
    } else {
        points[points.len() - 1]
    };

    let Some(heading) = ElbowGeometry::resolve_bound_heading(binding, elements_by_id, endpoint)
    else {
        return no_move;
    };

    let target_fixed_horizontal = !heading.is_horizontal();
    let nearest = if is_start {
        fixed_segments.first()
    } else {
        fixed_segments.last()
    };
    let Some(nearest) = nearest else {
        return no_move;
    };

    if fixed_segment_is_horizontal(nearest) != target_fixed_horizontal {
        return no_move;
    }

    let anchor_index = if is_start {
        nearest.index.saturating_sub(1)
    } else {
        nearest.index
    };

    if anchor_index == 0 || anchor_index >= points.len() - 1 {
        return no_move;
    }

    let adj_a = if is_start {
        anchor_index - 1
    } else {
        anchor_index
    };
    let adj_b = if is_start {
        anchor_index
    } else {
        anchor_index + 1
    };

    let adjacent_horizontal =
        (points[adj_a].y - points[adj_b].y).abs() <= ElbowConstants::DEDUP_THRESHOLD;
    if heading.is_horizontal() != adjacent_horizontal {
        return no_move;
    }

    let Some(target) = elements_by_id.get(binding.element_id.as_str()) else {
        return no_move;
    };

    let bounds = SelectionCalculator::compute_element_world_aabb(target);
    let lane = if heading.is_horizontal() {
        resolve_horizontal_lane(
            points,
            endpoint,
            points[anchor_index],
            anchor_index,
            bounds,
            is_start,
        )
    } else if is_start {
        points[0].x
    } else {
        points[points.len() - 1].x
    };

    slide_run(
        points,
        anchor_index,
        heading.is_horizontal(),
        lane,
        if is_start { -1 } else { 1 },
    )
}

fn resolve_horizontal_lane(
    points: &[DrawPoint],
    endpoint: DrawPoint,
    reference: DrawPoint,
    anchor_index: usize,
    bounds: DrawRect,
    is_start: bool,
) -> f64 {
    let in_bounds = reference.y >= bounds.min_y - ElbowConstants::INTERSECTION_EPSILON
        && reference.y <= bounds.max_y + ElbowConstants::INTERSECTION_EPSILON;

    if in_bounds
        && !run_intersects_bounds(
            points,
            anchor_index,
            if is_start { -1 } else { 1 },
            true,
            bounds,
        )
    {
        return if (endpoint.y - reference.y).abs() > ElbowConstants::DEDUP_THRESHOLD {
            endpoint.y
        } else {
            reference.y
        };
    }

    let lo = bounds.min_y - ElbowConstants::BASE_PADDING;
    let hi = bounds.max_y + ElbowConstants::BASE_PADDING;

    if reference.y <= bounds.min_y {
        return lo;
    }
    if reference.y >= bounds.max_y {
        return hi;
    }

    if (reference.y - lo).abs() <= (reference.y - hi).abs() {
        lo
    } else {
        hi
    }
}

// Walks a contiguous orthogonal run from start_index in direction.
fn walk_run(
    points: &[DrawPoint],
    start_index: usize,
    direction: i32,
    horizontal: bool,
) -> WalkRunResult {
    let mut indices = vec![start_index];
    let mut cursor = start_index as isize;

    loop {
        let next = cursor + direction as isize;
        if next < 0 || next >= points.len() as isize {
            break;
        }

        let current_index = cursor as usize;
        let next_index = next as usize;
        let is_horizontal = (points[current_index].y - points[next_index].y).abs()
            <= ElbowConstants::DEDUP_THRESHOLD;

        if is_horizontal != horizontal {
            break;
        }

        indices.push(next_index);
        cursor = next;
    }

    let mut min_var = if horizontal {
        points[start_index].x
    } else {
        points[start_index].y
    };
    let mut max_var = min_var;

    for &index in &indices {
        let value = if horizontal {
            points[index].x
        } else {
            points[index].y
        };
        if value < min_var {
            min_var = value;
        }
        if value > max_var {
            max_var = value;
        }
    }

    WalkRunResult {
        indices,
        min_var,
        max_var,
    }
}

fn run_intersects_bounds(
    points: &[DrawPoint],
    start_index: usize,
    direction: i32,
    horizontal: bool,
    bounds: DrawRect,
) -> bool {
    if points.len() < 2 || start_index >= points.len() {
        return false;
    }

    let epsilon = ElbowConstants::INTERSECTION_EPSILON;
    let constant = if horizontal {
        points[start_index].y
    } else {
        points[start_index].x
    };

    let c_min = if horizontal {
        bounds.min_y
    } else {
        bounds.min_x
    };
    let c_max = if horizontal {
        bounds.max_y
    } else {
        bounds.max_x
    };
    if constant < c_min - epsilon || constant > c_max + epsilon {
        return false;
    }

    let run = walk_run(points, start_index, direction, horizontal);
    let v_min = if horizontal {
        bounds.min_x
    } else {
        bounds.min_y
    };
    let v_max = if horizontal {
        bounds.max_x
    } else {
        bounds.max_y
    };

    run.max_var >= v_min - epsilon && run.min_var <= v_max + epsilon
}

fn slide_run(
    points: &[DrawPoint],
    start_index: usize,
    horizontal: bool,
    target: f64,
    direction: i32,
) -> SlidePointsResult {
    if start_index >= points.len() || (direction != 1 && direction != -1) {
        return SlidePointsResult {
            points: points.to_vec(),
            moved: false,
        };
    }

    let current = if horizontal {
        points[start_index].y
    } else {
        points[start_index].x
    };
    if (current - target).abs() <= ElbowConstants::DEDUP_THRESHOLD {
        return SlidePointsResult {
            points: points.to_vec(),
            moved: false,
        };
    }

    let run = walk_run(points, start_index, direction, horizontal);
    let mut updated = points.to_vec();
    for index in run.indices {
        updated[index] = if horizontal {
            with_y(updated[index], target)
        } else {
            with_x(updated[index], target)
        };
    }

    SlidePointsResult {
        points: updated,
        moved: true,
    }
}

fn route_local_path(
    element: &ElementState,
    elements_by_id: &HashMap<String, ElementState>,
    start_local: DrawPoint,
    end_local: DrawPoint,
    start_arrowhead: ArrowheadStyle,
    end_arrowhead: ArrowheadStyle,
    start_binding: Option<&ArrowBinding>,
    end_binding: Option<&ArrowBinding>,
    previous_fixed: Option<&ElbowFixedSegment>,
    next_fixed: Option<&ElbowFixedSegment>,
) -> Vec<DrawPoint> {
    // If no binding constrains this span, continue neighboring fixed-axis preference.
    if start_binding.is_none()
        && end_binding.is_none()
        && (previous_fixed.is_some() || next_fixed.is_some())
    {
        let prefer_horizontal = if previous_fixed.is_some() && next_fixed.is_none() {
            previous_fixed.map(fixed_segment_is_horizontal)
        } else if next_fixed.is_some() && previous_fixed.is_none() {
            next_fixed.map(|segment| !fixed_segment_is_horizontal(segment))
        } else {
            None
        };

        if let Some(prefer_horizontal) = prefer_horizontal {
            return ElbowGeometry::direct_elbow_path(start_local, end_local, prefer_horizontal);
        }
    }

    elbow_router::route_elbow_arrow_for_element_points(
        element,
        start_local,
        end_local,
        elements_by_id,
        start_binding,
        end_binding,
        start_arrowhead,
        end_arrowhead,
    )
    .local_points
}

fn stitch_sub_path(
    points: &[DrawPoint],
    start_index: usize,
    end_index: usize,
    sub_path: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> FixedSegmentPathResult {
    let prefix = points[..start_index.min(points.len())].to_vec();
    let suffix = if end_index + 1 < points.len() {
        points[end_index + 1..].to_vec()
    } else {
        Vec::new()
    };

    let mut stitched = Vec::with_capacity(prefix.len() + sub_path.len() + suffix.len());
    stitched.extend(prefix);
    stitched.extend_from_slice(sub_path);
    stitched.extend(suffix);

    let reindexed = reindex_fixed_segments(&stitched, fixed_segments);
    FixedSegmentPathResult::new(stitched, reindexed)
}

fn reindex_fixed_segments(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> Vec<ElbowFixedSegment> {
    if fixed_segments.is_empty() || points.len() < 4 {
        return Vec::new();
    }

    let mut result = Vec::new();
    for segment in fixed_segments {
        let index = select_segment_index(
            points,
            fixed_segment_is_horizontal(segment),
            segment.index,
            fixed_segment_axis_value(segment),
            f64::INFINITY,
            &HashSet::new(),
        );

        let Some(index) = index else {
            continue;
        };
        if !is_interior_segment_index(index, points.len()) {
            continue;
        }

        let start = points[index - 1];
        let end = points[index];
        if is_degenerate_segment(start, end) {
            continue;
        }

        result.push(ElbowFixedSegment { index, start, end });
    }

    result
}

fn select_segment_index(
    points: &[DrawPoint],
    is_horizontal: bool,
    preferred_index: usize,
    axis_value: f64,
    axis_tolerance: f64,
    used_indices: &HashSet<usize>,
) -> Option<usize> {
    if points.len() < 2 {
        return None;
    }

    let mut best_index = None;
    let mut best_axis_delta = f64::INFINITY;
    let mut best_index_delta = f64::INFINITY;

    for index in 2..points.len() - 1 {
        if used_indices.contains(&index) {
            continue;
        }
        if ElbowGeometry::segment_is_horizontal(points[index - 1], points[index]) != is_horizontal {
            continue;
        }

        let candidate_axis = if is_horizontal {
            (points[index - 1].y + points[index].y) / 2.0
        } else {
            (points[index - 1].x + points[index].x) / 2.0
        };

        let axis_delta = (candidate_axis - axis_value).abs();
        if axis_delta > axis_tolerance {
            continue;
        }

        let index_delta = (index as i64 - preferred_index as i64).unsigned_abs() as f64;
        let axis_closer = axis_delta < best_axis_delta - ElbowConstants::DEDUP_THRESHOLD;
        let axis_tie = (axis_delta - best_axis_delta).abs() <= ElbowConstants::DEDUP_THRESHOLD;

        if axis_closer || (axis_tie && index_delta < best_index_delta) {
            best_axis_delta = axis_delta;
            best_index_delta = index_delta;
            best_index = Some(index);
        }
    }

    best_index
}

fn fixed_segment_is_horizontal_at_index(
    fixed_segments: &[ElbowFixedSegment],
    index: usize,
) -> Option<bool> {
    fixed_segments
        .iter()
        .find(|segment| segment.index == index)
        .map(fixed_segment_is_horizontal)
}

fn apply_fixed_segments_to_points(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> Vec<DrawPoint> {
    if points.len() < 2 || fixed_segments.is_empty() {
        return points.to_vec();
    }

    let mut updated = points.to_vec();
    for segment in fixed_segments {
        let index = segment.index;
        if index == 0 || index >= updated.len() {
            continue;
        }

        let start = updated[index - 1];
        let end = updated[index];
        let axis = fixed_segment_axis_value(segment);

        let start_axis = if fixed_segment_is_horizontal(segment) {
            start.y
        } else {
            start.x
        };
        let end_axis = if fixed_segment_is_horizontal(segment) {
            end.y
        } else {
            end.x
        };

        let already_aligned = (start_axis - axis).abs() <= ElbowConstants::DEDUP_THRESHOLD
            && (end_axis - axis).abs() <= ElbowConstants::DEDUP_THRESHOLD;
        if already_aligned {
            continue;
        }

        if fixed_segment_is_horizontal(segment) {
            updated[index - 1] = with_y(start, axis);
            updated[index] = with_y(end, axis);
        } else {
            updated[index - 1] = with_x(start, axis);
            updated[index] = with_x(end, axis);
        }
    }

    updated
}

fn map_fixed_segments_to_baseline(
    baseline: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
    active_segment: Option<&ElbowFixedSegment>,
    enforce_axis_on_points: bool,
    require_all: bool,
) -> Option<FixedSegmentPathResult> {
    if baseline.len() < 2 {
        return if require_all {
            None
        } else {
            Some(FixedSegmentPathResult::new(
                baseline.to_vec(),
                fixed_segments.to_vec(),
            ))
        };
    }

    if fixed_segments.is_empty() {
        return Some(FixedSegmentPathResult::new(baseline.to_vec(), Vec::new()));
    }

    let mut updated = baseline.to_vec();
    let mut used_indices = HashSet::new();
    let mut mapped_segments = Vec::new();

    for segment in fixed_segments {
        let is_active = active_segment
            .as_ref()
            .is_some_and(|active| active.index == segment.index);

        let index = select_segment_index(
            &updated,
            fixed_segment_is_horizontal(segment),
            segment.index,
            fixed_segment_axis_value(segment),
            if is_active {
                f64::INFINITY
            } else {
                ElbowConstants::DEDUP_THRESHOLD
            },
            &used_indices,
        );

        let Some(index) = index else {
            if require_all {
                return None;
            }
            continue;
        };

        if !is_interior_segment_index(index, updated.len()) {
            if require_all {
                return None;
            }
            continue;
        }

        used_indices.insert(index);

        let mut start = updated[index - 1];
        let mut end = updated[index];

        if !is_active {
            let axis = fixed_segment_axis_value(segment);
            let aligned_start = if fixed_segment_is_horizontal(segment) {
                with_y(start, axis)
            } else {
                with_x(start, axis)
            };
            let aligned_end = if fixed_segment_is_horizontal(segment) {
                with_y(end, axis)
            } else {
                with_x(end, axis)
            };

            if enforce_axis_on_points {
                updated[index - 1] = aligned_start;
                updated[index] = aligned_end;
            }

            start = aligned_start;
            end = aligned_end;
        }

        mapped_segments.push(ElbowFixedSegment { index, start, end });
    }

    Some(FixedSegmentPathResult::new(updated, mapped_segments))
}

fn sync_fixed_segments_to_points(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> Vec<ElbowFixedSegment> {
    if fixed_segments.is_empty() || points.len() < 4 {
        return Vec::new();
    }

    let mut result = Vec::new();
    for segment in fixed_segments {
        let index = segment.index;
        if !is_interior_segment_index(index, points.len()) {
            continue;
        }

        let start = points[index - 1];
        let end = points[index];
        if is_degenerate_segment(start, end) {
            continue;
        }

        result.push(ElbowFixedSegment { index, start, end });
    }

    result
}

fn deduplicate_adjacent_points(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> FixedSegmentPathResult {
    if points.len() < 2 {
        return FixedSegmentPathResult::new(points.to_vec(), fixed_segments.to_vec());
    }

    let mut cleaned = vec![points[0]];
    for point in points.iter().copied().skip(1) {
        let previous = *cleaned.last().expect("cleaned not empty");
        if ElbowGeometry::points_close(previous, point) {
            continue;
        }
        if ElbowGeometry::manhattan_distance(previous, point) <= ElbowConstants::DEDUP_THRESHOLD {
            continue;
        }
        cleaned.push(point);
    }

    if cleaned.len() == points.len() {
        return FixedSegmentPathResult::new(points.to_vec(), fixed_segments.to_vec());
    }

    let reindexed = reindex_fixed_segments(&cleaned, fixed_segments);
    if reindexed.len() != fixed_segments.len() {
        return FixedSegmentPathResult::new(points.to_vec(), fixed_segments.to_vec());
    }

    FixedSegmentPathResult::new(cleaned, reindexed)
}

fn merge_fixed_segments_with_collinear_neighbors(
    points: Vec<DrawPoint>,
    fixed_segments: Vec<ElbowFixedSegment>,
    allow_direction_flip: bool,
) -> FixedSegmentPathResult {
    if points.len() < 3 || fixed_segments.is_empty() {
        return FixedSegmentPathResult::new(points, fixed_segments);
    }

    let deduped = deduplicate_adjacent_points(&points, &fixed_segments);
    let simplified = ElbowGeometry::simplify_path(&deduped.points);

    let reindexed = reindex_fixed_segments(&simplified, &deduped.fixed_segments);
    if reindexed.len() == deduped.fixed_segments.len() {
        FixedSegmentPathResult::new(simplified, reindexed)
    } else {
        // Keep prior fixed metadata when simplification would lose locks.
        FixedSegmentPathResult::new(deduped.points, deduped.fixed_segments)
    }
}

fn normalize_fixed_segment_path(
    points: Vec<DrawPoint>,
    fixed_segments: Vec<ElbowFixedSegment>,
    enforce_axes: bool,
    allow_direction_flip: bool,
) -> FixedSegmentPathResult {
    if points.len() < 2 || fixed_segments.is_empty() {
        return FixedSegmentPathResult::new(points, fixed_segments);
    }

    let enforced = if enforce_axes {
        apply_fixed_segments_to_points(&points, &fixed_segments)
    } else {
        points
    };

    let simplified = ElbowGeometry::simplify_path(&enforced);
    let reindexed = reindex_fixed_segments(&simplified, &fixed_segments);
    let active_fixed = if reindexed.len() == fixed_segments.len() {
        reindexed
    } else {
        fixed_segments
    };

    merge_fixed_segments_with_collinear_neighbors(simplified, active_fixed, allow_direction_flip)
}

fn ensure_perpendicular_bindings(
    context: &ElbowEditContext,
    points: Vec<DrawPoint>,
    fixed_segments: Vec<ElbowFixedSegment>,
) -> FixedSegmentPathResult {
    let translated = translated_perpendicular::ensure_perpendicular_bindings(
        &translated_perpendicular::ElbowEditContext {
            element: context.element.clone(),
            elements_by_id: context.elements_by_id.clone(),
            start_binding: context.start_binding.as_ref().map(to_translated_binding),
            end_binding: context.end_binding.as_ref().map(to_translated_binding),
            start_arrowhead: context.start_arrowhead,
            end_arrowhead: context.end_arrowhead,
        },
        points,
        fixed_segments,
    );
    FixedSegmentPathResult::new(translated.points, translated.fixed_segments)
}

fn to_translated_binding(binding: &ArrowBinding) -> PerpendicularArrowBinding {
    PerpendicularArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        match binding.mode {
            crate::draw::elements::types::arrow::arrow_data::ArrowBindingMode::Inside => {
                PerpendicularArrowBindingMode::Inside
            }
            crate::draw::elements::types::arrow::arrow_data::ArrowBindingMode::Orbit => {
                PerpendicularArrowBindingMode::Orbit
            }
            crate::draw::elements::types::arrow::arrow_data::ArrowBindingMode::Skip => {
                PerpendicularArrowBindingMode::Skip
            }
        },
    )
}

fn direction_matches(from: DrawPoint, to: DrawPoint, heading: ElbowHeading) -> bool {
    match heading {
        ElbowHeading::Right => to.x - from.x > ElbowConstants::DEDUP_THRESHOLD,
        ElbowHeading::Left => from.x - to.x > ElbowConstants::DEDUP_THRESHOLD,
        ElbowHeading::Down => to.y - from.y > ElbowConstants::DEDUP_THRESHOLD,
        ElbowHeading::Up => from.y - to.y > ElbowConstants::DEDUP_THRESHOLD,
    }
}

fn is_interior_segment_index(index: usize, point_count: usize) -> bool {
    index > 1 && index + 1 < point_count
}

fn is_degenerate_segment(start: DrawPoint, end: DrawPoint) -> bool {
    ElbowGeometry::manhattan_distance(start, end) <= ElbowConstants::DEDUP_THRESHOLD
}

fn fixed_segment_is_horizontal(segment: &ElbowFixedSegment) -> bool {
    ElbowGeometry::segment_is_horizontal(segment.start, segment.end)
}

fn fixed_segment_axis_value(segment: &ElbowFixedSegment) -> f64 {
    if fixed_segment_is_horizontal(segment) {
        (segment.start.y + segment.end.y) / 2.0
    } else {
        (segment.start.x + segment.end.x) / 2.0
    }
}

fn with_x(point: DrawPoint, x: f64) -> DrawPoint {
    point.copy_with(Some(x), None, None, None)
}

fn with_y(point: DrawPoint, y: f64) -> DrawPoint {
    point.copy_with(None, Some(y), None, None)
}

fn resolve_elbow_anchor_point(binding: &ArrowBinding, target: &ElementState) -> Option<DrawPoint> {
    let rect = target.rect;
    if rect.width().abs() <= ElbowConstants::INTERSECTION_EPSILON
        || rect.height().abs() <= ElbowConstants::INTERSECTION_EPSILON
    {
        return None;
    }

    let local_anchor = DrawPoint::new(
        rect.min_x + rect.width() * binding.anchor.x,
        rect.min_y + rect.height() * binding.anchor.y,
    );

    let space = ElementSpace::new(target.rotation, rect.center());
    Some(space.to_world(local_anchor))
}

struct ElbowGeometry;

impl ElbowGeometry {
    fn heading_for_vector(dx: f64, dy: f64) -> ElbowHeading {
        if dx.abs() >= dy.abs() {
            if dx >= 0.0 {
                ElbowHeading::Right
            } else {
                ElbowHeading::Left
            }
        } else if dy >= 0.0 {
            ElbowHeading::Down
        } else {
            ElbowHeading::Up
        }
    }

    fn heading_for_point_on_bounds(bounds: DrawRect, point: DrawPoint) -> ElbowHeading {
        let left = (point.x - bounds.min_x).abs();
        let right = (bounds.max_x - point.x).abs();
        let top = (point.y - bounds.min_y).abs();
        let bottom = (bounds.max_y - point.y).abs();

        let min = left.min(right).min(top.min(bottom));
        if (min - left).abs() <= ElbowConstants::INTERSECTION_EPSILON {
            ElbowHeading::Left
        } else if (min - right).abs() <= ElbowConstants::INTERSECTION_EPSILON {
            ElbowHeading::Right
        } else if (min - top).abs() <= ElbowConstants::INTERSECTION_EPSILON {
            ElbowHeading::Up
        } else {
            ElbowHeading::Down
        }
    }

    fn resolve_bound_heading(
        binding: &ArrowBinding,
        elements_by_id: &HashMap<String, ElementState>,
        point: DrawPoint,
    ) -> Option<ElbowHeading> {
        let element = elements_by_id.get(binding.element_id.as_str())?;
        let bounds = SelectionCalculator::compute_element_world_aabb(element);
        let anchor = resolve_elbow_anchor_point(binding, element).unwrap_or(point);
        Some(Self::heading_for_point_on_bounds(bounds, anchor))
    }

    fn direct_elbow_path(
        start: DrawPoint,
        end: DrawPoint,
        prefer_horizontal: bool,
    ) -> Vec<DrawPoint> {
        if (start.x - end.x).abs() <= ElbowConstants::INTERSECTION_EPSILON
            || (start.y - end.y).abs() <= ElbowConstants::INTERSECTION_EPSILON
        {
            return vec![start, end];
        }

        let mid = if prefer_horizontal {
            DrawPoint::new(end.x, start.y)
        } else {
            DrawPoint::new(start.x, end.y)
        };

        vec![start, mid, end]
    }

    fn simplify_path(points: &[DrawPoint]) -> Vec<DrawPoint> {
        if points.len() < 3 {
            return points.to_vec();
        }

        let mut deduped = Vec::with_capacity(points.len());
        deduped.push(points[0]);
        for point in points.iter().copied().skip(1) {
            let previous = *deduped.last().expect("deduped not empty");
            if Self::points_close(previous, point) {
                continue;
            }
            deduped.push(point);
        }

        if deduped.len() < 3 {
            return deduped;
        }

        let mut reduced = Vec::with_capacity(deduped.len());
        reduced.push(deduped[0]);

        for index in 1..deduped.len() - 1 {
            let a = *reduced.last().expect("reduced not empty");
            let b = deduped[index];
            let c = deduped[index + 1];
            if !Self::segments_collinear(a, b, c) {
                reduced.push(b);
            }
        }

        reduced.push(*deduped.last().expect("deduped not empty"));
        reduced
    }

    fn has_diagonal_segments(points: &[DrawPoint]) -> bool {
        points.windows(2).any(|segment| {
            let a = segment[0];
            let b = segment[1];
            (a.x - b.x).abs() > ElbowConstants::DEDUP_THRESHOLD
                && (a.y - b.y).abs() > ElbowConstants::DEDUP_THRESHOLD
        })
    }

    fn point_lists_equal(left: &[DrawPoint], right: &[DrawPoint]) -> bool {
        left.len() == right.len()
            && left
                .iter()
                .zip(right.iter())
                .all(|(a, b)| a.x == b.x && a.y == b.y)
    }

    fn point_lists_equal_except_endpoints(left: &[DrawPoint], right: &[DrawPoint]) -> bool {
        if left.len() != right.len() || left.len() < 2 {
            return false;
        }

        left.iter()
            .zip(right.iter())
            .enumerate()
            .skip(1)
            .take(left.len().saturating_sub(2))
            .all(|(_, (a, b))| a.x == b.x && a.y == b.y)
    }

    fn manhattan_distance(a: DrawPoint, b: DrawPoint) -> f64 {
        (a.x - b.x).abs() + (a.y - b.y).abs()
    }

    fn points_close(a: DrawPoint, b: DrawPoint) -> bool {
        (a.x - b.x).abs() <= ElbowConstants::DEDUP_THRESHOLD
            && (a.y - b.y).abs() <= ElbowConstants::DEDUP_THRESHOLD
    }

    fn segment_is_horizontal(a: DrawPoint, b: DrawPoint) -> bool {
        (a.y - b.y).abs() <= (a.x - b.x).abs()
    }

    fn segments_collinear(a: DrawPoint, b: DrawPoint, c: DrawPoint) -> bool {
        let ab_h = Self::segment_is_horizontal(a, b);
        let bc_h = Self::segment_is_horizontal(b, c);
        if ab_h != bc_h {
            return false;
        }

        if ab_h {
            (a.y - b.y).abs() <= ElbowConstants::DEDUP_THRESHOLD
                && (b.y - c.y).abs() <= ElbowConstants::DEDUP_THRESHOLD
        } else {
            (a.x - b.x).abs() <= ElbowConstants::DEDUP_THRESHOLD
                && (b.x - c.x).abs() <= ElbowConstants::DEDUP_THRESHOLD
        }
    }
}
