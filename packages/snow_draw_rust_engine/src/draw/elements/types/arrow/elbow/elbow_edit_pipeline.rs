#![allow(dead_code)]

use std::collections::{HashMap, HashSet};

use crate::draw::elements::types::arrow::arrow_data::{ArrowBinding, ArrowData, ElbowFixedSegment};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::ArrowheadStyle;
use crate::draw::utils::combined_element_lookup::CombinedElementLookup;

const AXIS_EPSILON: f64 = 1e-6;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct PointKey {
    x: u64,
    y: u64,
    pressure: u64,
}

impl From<DrawPoint> for PointKey {
    fn from(value: DrawPoint) -> Self {
        Self {
            x: value.x.to_bits(),
            y: value.y.to_bits(),
            pressure: value.pressure.to_bits(),
        }
    }
}

/// Normalized fixed-segment path plus the resolved fixed-segment metadata.
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

/// Result of a perpendicular endpoint adjustment.
#[derive(Clone, Debug, PartialEq)]
pub struct PerpendicularAdjustment {
    pub points: Vec<DrawPoint>,
    pub moved: bool,
    pub inserted: bool,
}

fn unchanged_adjustment(points: Vec<DrawPoint>) -> PerpendicularAdjustment {
    PerpendicularAdjustment {
        points,
        moved: false,
        inserted: false,
    }
}

/// Axis heading used by elbow routes.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ElbowHeading {
    Left,
    Right,
    Up,
    Down,
}

impl ElbowHeading {
    pub const fn opposite(self) -> Self {
        match self {
            Self::Left => Self::Right,
            Self::Right => Self::Left,
            Self::Up => Self::Down,
            Self::Down => Self::Up,
        }
    }
}

/// Minimal element shape required by elbow edit pipeline.
pub trait ElbowPipelineElement: Clone {
    fn rect(&self) -> DrawRect;

    fn previous_arrow_data(&self) -> Option<&ArrowData> {
        None
    }
}

impl ElbowPipelineElement for crate::draw::models::element_state::ElementState {
    fn rect(&self) -> DrawRect {
        self.rect
    }
}

/// Lightweight rect-backed element for direct pipeline usage.
#[derive(Clone, Debug, PartialEq)]
pub struct RectBackedElbowElement {
    pub rect: DrawRect,
    pub previous_data: Option<ArrowData>,
}

impl ElbowPipelineElement for RectBackedElbowElement {
    fn rect(&self) -> DrawRect {
        self.rect
    }

    fn previous_arrow_data(&self) -> Option<&ArrowData> {
        self.previous_data.as_ref()
    }
}

/// Three-state override for nullable bindings.
#[derive(Clone, Debug, Default, PartialEq)]
pub enum BindingOverride {
    #[default]
    Unset,
    Null,
    Value(ArrowBinding),
}

/// Context assembled for one elbow edit pass.
#[derive(Clone, Debug)]
pub struct ElbowEditContext<E>
where
    E: ElbowPipelineElement + Clone,
{
    pub element: E,
    pub data: ArrowData,
    pub elements_by_id: HashMap<String, E>,
    pub base_points: Vec<DrawPoint>,
    pub incoming_points: Vec<DrawPoint>,
    pub previous_fixed_segments: Vec<ElbowFixedSegment>,
    pub fixed_segments: Vec<ElbowFixedSegment>,
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
    pub previous_start_binding: Option<ArrowBinding>,
    pub previous_end_binding: Option<ArrowBinding>,
    pub release_requested: bool,
}

impl<E> ElbowEditContext<E>
where
    E: ElbowPipelineElement + Clone,
{
    pub fn binding_changed(&self) -> bool {
        self.previous_start_binding != self.start_binding
            || self.previous_end_binding != self.end_binding
    }

    pub fn start_binding_removed(&self) -> bool {
        self.previous_start_binding.is_some() && self.start_binding.is_none()
    }

    pub fn end_binding_removed(&self) -> bool {
        self.previous_end_binding.is_some() && self.end_binding.is_none()
    }

    pub fn points_changed(&self) -> bool {
        !point_lists_equal(&self.base_points, &self.incoming_points)
    }

    pub fn fixed_segments_changed(&self) -> bool {
        !fixed_segments_equal(&self.previous_fixed_segments, &self.fixed_segments)
    }

    pub fn start_active(&self) -> bool {
        is_endpoint_active(
            &self.base_points,
            &self.incoming_points,
            true,
            self.previous_start_binding.as_ref(),
            self.start_binding.as_ref(),
        )
    }

    pub fn end_active(&self) -> bool {
        is_endpoint_active(
            &self.base_points,
            &self.incoming_points,
            false,
            self.previous_end_binding.as_ref(),
            self.end_binding.as_ref(),
        )
    }

    pub fn start_was_bound(&self) -> bool {
        self.previous_start_binding.is_some()
    }

    pub fn end_was_bound(&self) -> bool {
        self.previous_end_binding.is_some()
    }

    pub fn start_arrowhead(&self) -> ArrowheadStyle {
        self.data.start_arrowhead
    }

    pub fn end_arrowhead(&self) -> ArrowheadStyle {
        self.data.end_arrowhead
    }

    pub fn has_bindings(&self) -> bool {
        self.start_binding.is_some() || self.end_binding.is_some()
    }

    pub fn has_bound_start(&self) -> bool {
        self.start_binding
            .as_ref()
            .is_some_and(|binding| self.elements_by_id.contains_key(&binding.element_id))
    }

    pub fn has_bound_end(&self) -> bool {
        self.end_binding
            .as_ref()
            .is_some_and(|binding| self.elements_by_id.contains_key(&binding.element_id))
    }

    pub fn is_fully_unbound(&self) -> bool {
        self.start_binding.is_none() && self.end_binding.is_none()
    }

    /// Resolves required heading for a bound endpoint.
    ///
    /// For end points the heading is inverted to describe the final segment.
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

        let heading = resolve_bound_heading(binding, &self.elements_by_id, point)?;
        if is_start {
            Some(heading)
        } else {
            Some(heading.opposite())
        }
    }
}

/// Result emitted by the edit pipeline.
#[derive(Clone, Debug, PartialEq)]
pub struct ElbowEditResult {
    pub local_points: Vec<DrawPoint>,
    pub fixed_segments: Option<Vec<ElbowFixedSegment>>,
    pub start_is_special: Option<bool>,
    pub end_is_special: Option<bool>,
}

#[derive(Clone, Debug, PartialEq)]
struct RoutedElbowArrow {
    local_points: Vec<DrawPoint>,
}

/// Pipeline that mirrors Dart `_ElbowEditPipeline` behavior.
#[derive(Clone, Debug)]
pub struct ElbowEditPipeline<E>
where
    E: ElbowPipelineElement + Clone,
{
    pub element: E,
    pub data: ArrowData,
    pub elements_by_id: HashMap<String, E>,
    pub local_points_override: Option<Vec<DrawPoint>>,
    pub fixed_segments_override: Option<Vec<ElbowFixedSegment>>,
    pub start_binding_override: BindingOverride,
    pub end_binding_override: BindingOverride,
}

impl<E> ElbowEditPipeline<E>
where
    E: ElbowPipelineElement + Clone,
{
    pub fn new(element: E, data: ArrowData, elements_by_id: HashMap<String, E>) -> Self {
        Self {
            element,
            data,
            elements_by_id,
            local_points_override: None,
            fixed_segments_override: None,
            start_binding_override: BindingOverride::Unset,
            end_binding_override: BindingOverride::Unset,
        }
    }

    pub fn from_lookup(element: E, data: ArrowData, lookup: &CombinedElementLookup<'_, E>) -> Self {
        Self::new(element, data, lookup.to_map())
    }

    pub fn with_local_points_override(mut self, points: Option<Vec<DrawPoint>>) -> Self {
        self.local_points_override = points;
        self
    }

    pub fn with_fixed_segments_override(
        mut self,
        segments: Option<Vec<ElbowFixedSegment>>,
    ) -> Self {
        self.fixed_segments_override = segments;
        self
    }

    pub fn with_start_binding_override(mut self, override_value: BindingOverride) -> Self {
        self.start_binding_override = override_value;
        self
    }

    pub fn with_end_binding_override(mut self, override_value: BindingOverride) -> Self {
        self.end_binding_override = override_value;
        self
    }

    pub fn run(&self) -> ElbowEditResult {
        let context = self.build_context();
        if context.incoming_points.len() < 2 {
            return finalize_path(&context.data, context.incoming_points, None);
        }

        if context.fixed_segments.is_empty() {
            return self.route_without_fixed_segments(&context);
        }
        if context.release_requested {
            return self.handle_fixed_segment_release_flow(&context);
        }
        if context.binding_changed()
            || (context.points_changed() && !context.fixed_segments_changed())
        {
            return self.handle_endpoint_drag_flow(&context);
        }

        self.apply_fixed_segments_flow(&context)
    }

    fn build_context(&self) -> ElbowEditContext<E> {
        let base_points = resolve_local_points(&self.element, &self.data);
        let incoming_points = self
            .local_points_override
            .clone()
            .unwrap_or_else(|| base_points.clone());

        let previous_fixed_segments =
            sanitize_fixed_segments(self.data.fixed_segments.as_deref(), base_points.len());
        let requested_fixed = self
            .fixed_segments_override
            .as_deref()
            .or(self.data.fixed_segments.as_deref());
        let fixed_segments = sanitize_fixed_segments(requested_fixed, incoming_points.len());

        let start_binding = resolve_binding_override(
            &self.start_binding_override,
            self.data.start_binding.as_ref(),
        );
        let end_binding =
            resolve_binding_override(&self.end_binding_override, self.data.end_binding.as_ref());

        let previous_data = self
            .element
            .previous_arrow_data()
            .cloned()
            .unwrap_or_else(|| self.data.clone());

        ElbowEditContext {
            element: self.element.clone(),
            data: self.data.clone(),
            elements_by_id: self.elements_by_id.clone(),
            base_points,
            incoming_points,
            previous_fixed_segments: previous_fixed_segments.clone(),
            fixed_segments: fixed_segments.clone(),
            start_binding,
            end_binding,
            previous_start_binding: previous_data.start_binding,
            previous_end_binding: previous_data.end_binding,
            release_requested: self.fixed_segments_override.is_some()
                && fixed_segments.len() < previous_fixed_segments.len(),
        }
    }

    fn route_without_fixed_segments(&self, context: &ElbowEditContext<E>) -> ElbowEditResult {
        let mut routed_data = context.data.clone();
        routed_data.start_binding = context.start_binding.clone();
        routed_data.end_binding = context.end_binding.clone();

        let routed = route_elbow_arrow_for_element(
            &context.element,
            &routed_data,
            &context.elements_by_id,
            context.incoming_points[0],
            context.incoming_points[context.incoming_points.len() - 1],
        );

        finalize_path(&context.data, routed.local_points, None)
    }

    fn handle_fixed_segment_release_flow(&self, context: &ElbowEditContext<E>) -> ElbowEditResult {
        let result = self.release_fixed_segments(
            context,
            &context.incoming_points,
            &context.previous_fixed_segments,
            &context.fixed_segments,
            false,
        );
        finalize_path(&context.data, result.points, Some(result.fixed_segments))
    }

    fn handle_endpoint_drag_flow(&self, context: &ElbowEditContext<E>) -> ElbowEditResult {
        let updated = apply_endpoint_drag_with_fixed_segments(context);
        let mut points = updated.points;
        let mut fixed = updated.fixed_segments;

        if fixed.len() < context.fixed_segments.len() {
            let recovered = self.release_fixed_segments(
                context,
                &points,
                &context.fixed_segments,
                &fixed,
                true,
            );
            points = recovered.points;
            fixed = recovered.fixed_segments;
        }

        finalize_path(&context.data, points, Some(fixed))
    }

    fn release_fixed_segments(
        &self,
        context: &ElbowEditContext<E>,
        current_points: &[DrawPoint],
        previous_fixed: &[ElbowFixedSegment],
        remaining_fixed: &[ElbowFixedSegment],
        preserve_corners: bool,
    ) -> FixedSegmentPathResult {
        let released =
            handle_fixed_segment_release(context, current_points, previous_fixed, remaining_fixed);
        let mapped = map_fixed_segments_to_baseline(&released.points, &released.fixed_segments)
            .unwrap_or_else(|| released.clone());
        let reconciled = if mapped.fixed_segments.len() == released.fixed_segments.len() {
            mapped
        } else {
            released
        };

        let extra_pinned = if preserve_corners {
            interior_corner_points(&reconciled.points)
        } else {
            HashSet::new()
        };

        normalize_fixed_segment_path(
            reconciled.points,
            reconciled.fixed_segments,
            &extra_pinned,
            true,
        )
    }

    fn apply_fixed_segments_flow(&self, context: &ElbowEditContext<E>) -> ElbowEditResult {
        let simplified = normalize_fixed_segment_path(
            context.incoming_points.clone(),
            context.fixed_segments.clone(),
            &HashSet::new(),
            true,
        );
        finalize_path(
            &context.data,
            simplified.points,
            Some(simplified.fixed_segments),
        )
    }
}

/// Shared finalization: merge same-heading runs, reindex fixed segments,
/// and build the final edit result.
pub fn finalize_path(
    data: &ArrowData,
    points: Vec<DrawPoint>,
    fixed_segments: Option<Vec<ElbowFixedSegment>>,
) -> ElbowEditResult {
    let effective_fixed_segments = fixed_segments.unwrap_or_default();
    let has_fixed = !effective_fixed_segments.is_empty();
    let pinned = collect_pinned_points(&points, &effective_fixed_segments);
    let merged = merge_consecutive_same_heading(&points, &pinned);
    let resolved_fixed = if has_fixed {
        reindex_fixed_segments(&merged, &effective_fixed_segments)
    } else {
        None
    };

    ElbowEditResult {
        local_points: merged,
        fixed_segments: resolved_fixed,
        start_is_special: data.start_is_special,
        end_is_special: data.end_is_special,
    }
}

fn resolve_binding_override(
    override_value: &BindingOverride,
    fallback: Option<&ArrowBinding>,
) -> Option<ArrowBinding> {
    match override_value {
        BindingOverride::Unset => fallback.cloned(),
        BindingOverride::Null => None,
        BindingOverride::Value(binding) => Some(binding.clone()),
    }
}

fn is_endpoint_active(
    base_points: &[DrawPoint],
    incoming_points: &[DrawPoint],
    is_start: bool,
    previous_binding: Option<&ArrowBinding>,
    next_binding: Option<&ArrowBinding>,
) -> bool {
    did_endpoint_move(base_points, incoming_points, is_start) || previous_binding != next_binding
}

fn did_endpoint_move(
    base_points: &[DrawPoint],
    incoming_points: &[DrawPoint],
    is_start: bool,
) -> bool {
    if base_points.is_empty() || incoming_points.is_empty() {
        return false;
    }

    if is_start {
        base_points[0] != incoming_points[0]
    } else {
        base_points[base_points.len() - 1] != incoming_points[incoming_points.len() - 1]
    }
}

fn resolve_local_points<E>(element: &E, data: &ArrowData) -> Vec<DrawPoint>
where
    E: ElbowPipelineElement + Clone,
{
    ArrowGeometry::resolve_world_points(element.rect(), &data.points)
}

fn route_elbow_arrow_for_element<E>(
    _element: &E,
    data: &ArrowData,
    elements_by_id: &HashMap<String, E>,
    start_override: DrawPoint,
    end_override: DrawPoint,
) -> RoutedElbowArrow
where
    E: ElbowPipelineElement + Clone,
{
    let start = data
        .start_binding
        .as_ref()
        .and_then(|binding| resolve_bound_world_point(binding, elements_by_id))
        .unwrap_or(start_override);
    let end = data
        .end_binding
        .as_ref()
        .and_then(|binding| resolve_bound_world_point(binding, elements_by_id))
        .unwrap_or(end_override);

    let mut points = Vec::new();
    points.push(start);

    if !axis_aligned(start, end) {
        let dx = (end.x - start.x).abs();
        let dy = (end.y - start.y).abs();
        let bend = if dx >= dy {
            DrawPoint::new(end.x, start.y)
        } else {
            DrawPoint::new(start.x, end.y)
        };
        if bend != start && bend != end {
            points.push(bend);
        }
    }

    points.push(end);
    RoutedElbowArrow {
        local_points: dedupe_consecutive_points(points),
    }
}

fn apply_endpoint_drag_with_fixed_segments<E>(
    context: &ElbowEditContext<E>,
) -> FixedSegmentPathResult
where
    E: ElbowPipelineElement + Clone,
{
    let mut points = context.incoming_points.clone();
    if points.len() < 2 {
        return FixedSegmentPathResult::new(points, Vec::new());
    }

    if context.start_active() {
        let heading = context.resolve_required_heading(true, points[0]);
        let adjustment = apply_perpendicular_adjustment(points, true, heading);
        points = adjustment.points;
    }
    if context.end_active() {
        let end = points[points.len() - 1];
        let heading = context.resolve_required_heading(false, end);
        let adjustment = apply_perpendicular_adjustment(points, false, heading);
        points = adjustment.points;
    }

    let mut fixed = sanitize_fixed_segments(Some(&context.fixed_segments), points.len());
    if context.start_binding_removed() {
        fixed.retain(|segment| segment.index > 0);
    }
    if context.end_binding_removed() {
        let max_index = points.len().saturating_sub(2);
        fixed.retain(|segment| segment.index < max_index);
    }

    normalize_fixed_segment_path(points, fixed, &HashSet::new(), true)
}

fn apply_perpendicular_adjustment(
    mut points: Vec<DrawPoint>,
    is_start: bool,
    required_heading: Option<ElbowHeading>,
) -> PerpendicularAdjustment {
    if points.len() < 2 {
        return unchanged_adjustment(points);
    }

    if is_start {
        let anchor = points[0];
        let mutable = points[1];
        if axis_aligned(anchor, mutable) {
            return unchanged_adjustment(points);
        }
        let adjusted = align_neighbor_to_heading(anchor, mutable, required_heading);
        if adjusted == mutable {
            return unchanged_adjustment(points);
        }
        points[1] = adjusted;
        return PerpendicularAdjustment {
            points,
            moved: true,
            inserted: false,
        };
    }

    let last = points.len() - 1;
    let anchor = points[last];
    let mutable = points[last - 1];
    if axis_aligned(anchor, mutable) {
        return unchanged_adjustment(points);
    }
    let adjusted = align_neighbor_to_heading(anchor, mutable, required_heading);
    if adjusted == mutable {
        return unchanged_adjustment(points);
    }
    points[last - 1] = adjusted;
    PerpendicularAdjustment {
        points,
        moved: true,
        inserted: false,
    }
}

fn align_neighbor_to_heading(
    anchor: DrawPoint,
    neighbor: DrawPoint,
    required_heading: Option<ElbowHeading>,
) -> DrawPoint {
    match required_heading {
        Some(ElbowHeading::Left) | Some(ElbowHeading::Right) => {
            neighbor.copy_with(None, Some(anchor.y), None, None)
        }
        Some(ElbowHeading::Up) | Some(ElbowHeading::Down) => {
            neighbor.copy_with(Some(anchor.x), None, None, None)
        }
        None => {
            let dx = (neighbor.x - anchor.x).abs();
            let dy = (neighbor.y - anchor.y).abs();
            if dx >= dy {
                neighbor.copy_with(None, Some(anchor.y), None, None)
            } else {
                neighbor.copy_with(Some(anchor.x), None, None, None)
            }
        }
    }
}

fn handle_fixed_segment_release<E>(
    _context: &ElbowEditContext<E>,
    current_points: &[DrawPoint],
    previous_fixed: &[ElbowFixedSegment],
    remaining_fixed: &[ElbowFixedSegment],
) -> FixedSegmentPathResult
where
    E: ElbowPipelineElement + Clone,
{
    let mut points = current_points.to_vec();
    if points.len() < 2 {
        if let (Some(first), Some(last)) = (previous_fixed.first(), previous_fixed.last()) {
            points = vec![first.start, last.end];
        } else if let (Some(first), Some(last)) = (remaining_fixed.first(), remaining_fixed.last())
        {
            points = vec![first.start, last.end];
        } else {
            points = vec![DrawPoint::ZERO, DrawPoint::new(1.0, 1.0)];
        }
    }

    let missing_count = previous_fixed.len().saturating_sub(remaining_fixed.len());
    if missing_count > 0 && points.len() >= 3 {
        points = dedupe_consecutive_points(points);
    }

    FixedSegmentPathResult::new(
        points.clone(),
        sanitize_fixed_segments(Some(remaining_fixed), points.len()),
    )
}

fn map_fixed_segments_to_baseline(
    baseline: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> Option<FixedSegmentPathResult> {
    if fixed_segments.is_empty() {
        return Some(FixedSegmentPathResult::new(baseline.to_vec(), Vec::new()));
    }
    if baseline.len() < 2 {
        return None;
    }

    let mut mapped = Vec::with_capacity(fixed_segments.len());
    for segment in fixed_segments {
        if segment.index >= baseline.len() - 1 {
            return None;
        }
        mapped.push(ElbowFixedSegment {
            index: segment.index,
            start: baseline[segment.index],
            end: baseline[segment.index + 1],
        });
    }

    Some(FixedSegmentPathResult::new(
        baseline.to_vec(),
        sanitize_fixed_segments(Some(&mapped), baseline.len()),
    ))
}

fn interior_corner_points(points: &[DrawPoint]) -> HashSet<PointKey> {
    if points.len() < 3 {
        return HashSet::new();
    }

    let mut set = HashSet::new();
    for i in 1..(points.len() - 1) {
        let previous = points[i - 1];
        let current = points[i];
        let next = points[i + 1];
        let heading_in = heading_between(previous, current);
        let heading_out = heading_between(current, next);
        if heading_in.is_some() && heading_out.is_some() && heading_in != heading_out {
            set.insert(PointKey::from(current));
        }
    }
    set
}

fn normalize_fixed_segment_path(
    points: Vec<DrawPoint>,
    fixed_segments: Vec<ElbowFixedSegment>,
    extra_pinned: &HashSet<PointKey>,
    enforce_axes: bool,
) -> FixedSegmentPathResult {
    let mut normalized = if points.is_empty() {
        vec![DrawPoint::ZERO, DrawPoint::new(1.0, 1.0)]
    } else if points.len() == 1 {
        vec![points[0], points[0]]
    } else {
        points
    };

    if enforce_axes {
        for index in 1..normalized.len() {
            let previous = normalized[index - 1];
            let current = normalized[index];
            if axis_aligned(previous, current) {
                continue;
            }

            if extra_pinned.contains(&PointKey::from(current)) {
                continue;
            }

            let adjusted = if index < normalized.len() - 1 {
                let next = normalized[index + 1];
                let horizontal_cost = (current.y - previous.y).abs() + (next.x - current.x).abs();
                let vertical_cost = (current.x - previous.x).abs() + (next.y - current.y).abs();
                if vertical_cost < horizontal_cost {
                    current.copy_with(Some(previous.x), None, None, None)
                } else {
                    current.copy_with(None, Some(previous.y), None, None)
                }
            } else {
                let dx = (current.x - previous.x).abs();
                let dy = (current.y - previous.y).abs();
                if dx >= dy {
                    current.copy_with(None, Some(previous.y), None, None)
                } else {
                    current.copy_with(Some(previous.x), None, None, None)
                }
            };

            normalized[index] = adjusted;
        }
    }

    normalized = dedupe_consecutive_points(normalized);
    let sanitized_fixed = sanitize_fixed_segments(Some(&fixed_segments), normalized.len());
    let mut pinned = collect_pinned_points(&normalized, &sanitized_fixed);
    pinned.extend(extra_pinned.iter().copied());
    let merged = merge_consecutive_same_heading(&normalized, &pinned);
    let reindexed = reindex_fixed_segments(&merged, &sanitized_fixed).unwrap_or_default();

    FixedSegmentPathResult::new(merged, reindexed)
}

fn collect_pinned_points(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> HashSet<PointKey> {
    let mut pinned = HashSet::new();

    if let Some(first) = points.first().copied() {
        pinned.insert(PointKey::from(first));
    }
    if let Some(last) = points.last().copied() {
        pinned.insert(PointKey::from(last));
    }

    for segment in fixed_segments {
        pinned.insert(PointKey::from(segment.start));
        pinned.insert(PointKey::from(segment.end));
    }

    pinned
}

fn merge_consecutive_same_heading(
    points: &[DrawPoint],
    pinned: &HashSet<PointKey>,
) -> Vec<DrawPoint> {
    if points.len() < 3 {
        return points.to_vec();
    }

    let mut merged = Vec::with_capacity(points.len());
    merged.push(points[0]);

    for i in 1..(points.len() - 1) {
        let current = points[i];
        if pinned.contains(&PointKey::from(current)) {
            merged.push(current);
            continue;
        }

        let previous = merged[merged.len() - 1];
        let next = points[i + 1];
        let heading_a = heading_between(previous, current);
        let heading_b = heading_between(current, next);

        if heading_a.is_some() && heading_a == heading_b {
            continue;
        }

        merged.push(current);
    }

    merged.push(points[points.len() - 1]);
    dedupe_consecutive_points(merged)
}

fn reindex_fixed_segments(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> Option<Vec<ElbowFixedSegment>> {
    if points.len() < 2 || fixed_segments.is_empty() {
        return None;
    }

    let mut reindexed = Vec::with_capacity(fixed_segments.len());
    for segment in fixed_segments {
        let Some(index) = resolve_segment_index(points, segment) else {
            continue;
        };

        reindexed.push(ElbowFixedSegment {
            index,
            start: points[index],
            end: points[index + 1],
        });
    }

    reindexed.sort_by_key(|segment| segment.index);
    reindexed.dedup_by_key(|segment| segment.index);

    if reindexed.is_empty() {
        None
    } else {
        Some(reindexed)
    }
}

fn resolve_segment_index(points: &[DrawPoint], segment: &ElbowFixedSegment) -> Option<usize> {
    if points.len() < 2 {
        return None;
    }

    for index in 0..(points.len() - 1) {
        let a = points[index];
        let b = points[index + 1];
        if (a == segment.start && b == segment.end) || (a == segment.end && b == segment.start) {
            return Some(index);
        }
    }

    let segment_midpoint = midpoint(segment.start, segment.end);
    let mut best: Option<usize> = None;
    let mut best_distance = f64::INFINITY;

    for index in 0..(points.len() - 1) {
        let mid = midpoint(points[index], points[index + 1]);
        let distance = mid.distance_squared(segment_midpoint);
        if distance < best_distance {
            best_distance = distance;
            best = Some(index);
        }
    }

    best
}

fn midpoint(a: DrawPoint, b: DrawPoint) -> DrawPoint {
    DrawPoint::new((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
}

fn resolve_bound_heading<E>(
    binding: &ArrowBinding,
    elements_by_id: &HashMap<String, E>,
    point: DrawPoint,
) -> Option<ElbowHeading>
where
    E: ElbowPipelineElement + Clone,
{
    let bound = resolve_bound_world_point(binding, elements_by_id)?;
    let dx = point.x - bound.x;
    let dy = point.y - bound.y;

    if dx.abs() >= dy.abs() {
        if dx >= 0.0 {
            Some(ElbowHeading::Right)
        } else {
            Some(ElbowHeading::Left)
        }
    } else if dy >= 0.0 {
        Some(ElbowHeading::Down)
    } else {
        Some(ElbowHeading::Up)
    }
}

fn resolve_bound_world_point<E>(
    binding: &ArrowBinding,
    elements_by_id: &HashMap<String, E>,
) -> Option<DrawPoint>
where
    E: ElbowPipelineElement + Clone,
{
    let target = elements_by_id.get(&binding.element_id)?;
    let rect = target.rect();

    Some(DrawPoint::new(
        rect.min_x + rect.width() * binding.anchor.x,
        rect.min_y + rect.height() * binding.anchor.y,
    ))
}

fn sanitize_fixed_segments(
    fixed_segments: Option<&[ElbowFixedSegment]>,
    point_count: usize,
) -> Vec<ElbowFixedSegment> {
    let Some(segments) = fixed_segments else {
        return Vec::new();
    };
    if point_count < 2 {
        return Vec::new();
    }

    let max_index = point_count - 2;
    let mut sanitized: Vec<ElbowFixedSegment> = segments
        .iter()
        .filter(|segment| segment.index <= max_index)
        .cloned()
        .collect();

    sanitized.sort_by_key(|segment| segment.index);
    sanitized.dedup_by_key(|segment| segment.index);
    sanitized.retain(|segment| segment.start != segment.end);
    sanitized
}

fn fixed_segments_equal(a: &[ElbowFixedSegment], b: &[ElbowFixedSegment]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).all(|(left, right)| left == right)
}

fn point_lists_equal(a: &[DrawPoint], b: &[DrawPoint]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).all(|(left, right)| left == right)
}

fn dedupe_consecutive_points(points: Vec<DrawPoint>) -> Vec<DrawPoint> {
    if points.is_empty() {
        return points;
    }

    let mut deduped = Vec::with_capacity(points.len());
    deduped.push(points[0]);

    for point in points.into_iter().skip(1) {
        if point != deduped[deduped.len() - 1] {
            deduped.push(point);
        }
    }

    if deduped.len() == 1 {
        deduped.push(deduped[0]);
    }

    deduped
}

fn heading_between(a: DrawPoint, b: DrawPoint) -> Option<ElbowHeading> {
    if approx_eq(a.x, b.x) {
        if approx_eq(a.y, b.y) {
            return None;
        }
        if b.y >= a.y {
            return Some(ElbowHeading::Down);
        }
        return Some(ElbowHeading::Up);
    }

    if approx_eq(a.y, b.y) {
        if b.x >= a.x {
            return Some(ElbowHeading::Right);
        }
        return Some(ElbowHeading::Left);
    }

    None
}

fn axis_aligned(a: DrawPoint, b: DrawPoint) -> bool {
    approx_eq(a.x, b.x) || approx_eq(a.y, b.y)
}

fn approx_eq(a: f64, b: f64) -> bool {
    (a - b).abs() <= AXIS_EPSILON
}
