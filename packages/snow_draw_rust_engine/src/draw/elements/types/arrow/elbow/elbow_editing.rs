#![allow(dead_code)]

use std::collections::HashSet;

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::types::arrow::arrow_data::{ArrowBinding, ArrowData, ElbowFixedSegment};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::utils::combined_element_lookup::CombinedElementLookup;

use super::elbow_constants::ElbowConstants;
use super::elbow_edit_pipeline::{
    BindingOverride as PipelineBindingOverride, ElbowEditPipeline, ElbowPipelineElement,
};
use super::elbow_geometry::{ElbowGeometry, ElbowHeading};

/// Output of elbow edit computation (point list + fixed segment updates).
#[derive(Clone, Debug, PartialEq)]
pub struct ElbowEditResult {
    pub local_points: Vec<DrawPoint>,
    pub fixed_segments: Option<Vec<ElbowFixedSegment>>,
    pub start_is_special: Option<bool>,
    pub end_is_special: Option<bool>,
}

/// Tri-state binding override used by elbow edit entry points.
///
/// Mirrors the Dart API behavior:
/// - [`BindingOverride::Unset`] keeps the binding from [`ArrowData`].
/// - [`BindingOverride::Clear`] clears the binding.
/// - [`BindingOverride::Value`] applies a new binding.
#[derive(Clone, Debug, PartialEq)]
pub enum BindingOverride<T> {
    Unset,
    Clear,
    Value(T),
}

impl<T> Default for BindingOverride<T> {
    fn default() -> Self {
        Self::Unset
    }
}

impl<T> BindingOverride<T> {
    pub fn resolve(self, fallback: Option<T>) -> Option<T> {
        match self {
            Self::Unset => fallback,
            Self::Clear => None,
            Self::Value(value) => Some(value),
        }
    }
}

/// Computes elbow edit using a combined lookup for efficient element access.
pub fn compute_elbow_edit<E>(
    element: &E,
    data: &ArrowData,
    lookup: &CombinedElementLookup<'_, E>,
    local_points_override: Option<Vec<DrawPoint>>,
    fixed_segments_override: Option<Vec<ElbowFixedSegment>>,
    start_binding_override: BindingOverride<ArrowBinding>,
    end_binding_override: BindingOverride<ArrowBinding>,
    finalize: bool,
) -> ElbowEditResult
where
    E: ElbowPipelineElement + Clone,
{
    let result = run_elbow_edit_pipeline(
        element,
        data,
        lookup,
        local_points_override,
        fixed_segments_override,
        start_binding_override.clone(),
        end_binding_override.clone(),
    );

    if finalize {
        finalize_elbow_edit_result(
            element,
            data,
            lookup,
            result,
            start_binding_override,
            end_binding_override,
        )
    } else {
        result
    }
}

fn run_elbow_edit_pipeline<E>(
    element: &E,
    data: &ArrowData,
    lookup: &CombinedElementLookup<'_, E>,
    local_points_override: Option<Vec<DrawPoint>>,
    fixed_segments_override: Option<Vec<ElbowFixedSegment>>,
    start_binding_override: BindingOverride<ArrowBinding>,
    end_binding_override: BindingOverride<ArrowBinding>,
) -> ElbowEditResult
where
    E: ElbowPipelineElement + Clone,
{
    let pipeline = ElbowEditPipeline::from_lookup(element.clone(), data.clone(), lookup)
        .with_local_points_override(local_points_override)
        .with_fixed_segments_override(fixed_segments_override)
        .with_start_binding_override(to_pipeline_binding_override(&start_binding_override))
        .with_end_binding_override(to_pipeline_binding_override(&end_binding_override));
    from_pipeline_result(pipeline.run())
}

fn finalize_elbow_edit_result<E>(
    element: &E,
    data: &ArrowData,
    lookup: &CombinedElementLookup<'_, E>,
    result: ElbowEditResult,
    start_binding_override: BindingOverride<ArrowBinding>,
    end_binding_override: BindingOverride<ArrowBinding>,
) -> ElbowEditResult
where
    E: ElbowPipelineElement + Clone,
{
    let Some(fixed_segments) = result.fixed_segments.as_ref() else {
        return result;
    };
    if fixed_segments.is_empty() {
        return result;
    }

    let to_drop = fixed_segments_with_same_heading_adjacency(&result.local_points, fixed_segments);
    if to_drop.is_empty() {
        return result;
    }

    let remaining = fixed_segments
        .iter()
        .filter(|segment| !to_drop.contains(&segment.index))
        .cloned()
        .collect::<Vec<_>>();

    run_elbow_edit_pipeline(
        element,
        data,
        lookup,
        Some(result.local_points),
        Some(remaining),
        start_binding_override,
        end_binding_override,
    )
}

fn fixed_segments_with_same_heading_adjacency(
    points: &[DrawPoint],
    fixed_segments: &[ElbowFixedSegment],
) -> HashSet<usize> {
    if points.len() < 3 || fixed_segments.is_empty() {
        return HashSet::new();
    }

    let fixed_indices = fixed_segments
        .iter()
        .map(|segment| segment.index)
        .collect::<HashSet<_>>();
    let mut to_drop = HashSet::new();

    for i in 1..(points.len() - 1) {
        let a = points[i - 1];
        let b = points[i];
        let c = points[i + 1];
        let prev_length = manhattan_distance(a, b);
        let next_length = manhattan_distance(b, c);
        if prev_length <= ElbowConstants::DEDUP_THRESHOLD
            || next_length <= ElbowConstants::DEDUP_THRESHOLD
        {
            continue;
        }

        let prev_heading = heading_for_segment(a, b);
        let next_heading = heading_for_segment(b, c);
        if prev_heading.is_none() || prev_heading != next_heading {
            continue;
        }

        let prev_index = i;
        let next_index = i + 1;
        if fixed_indices.contains(&prev_index) {
            to_drop.insert(prev_index);
        }
        if fixed_indices.contains(&next_index) {
            to_drop.insert(next_index);
        }
    }

    to_drop
}

fn heading_for_segment(a: DrawPoint, b: DrawPoint) -> Option<ElbowHeading> {
    let dx = (a.x - b.x).abs();
    let dy = (a.y - b.y).abs();
    if dx <= ElbowConstants::INTERSECTION_EPSILON && dy <= ElbowConstants::INTERSECTION_EPSILON {
        return None;
    }
    Some(ElbowGeometry::heading_for_segment(a, b))
}

fn manhattan_distance(a: DrawPoint, b: DrawPoint) -> f64 {
    (a.x - b.x).abs() + (a.y - b.y).abs()
}

fn to_pipeline_binding_override(
    override_value: &BindingOverride<ArrowBinding>,
) -> PipelineBindingOverride {
    match override_value {
        BindingOverride::Unset => PipelineBindingOverride::Unset,
        BindingOverride::Clear => PipelineBindingOverride::Null,
        BindingOverride::Value(binding) => PipelineBindingOverride::Value(binding.clone()),
    }
}

fn from_pipeline_result(result: super::elbow_edit_pipeline::ElbowEditResult) -> ElbowEditResult {
    ElbowEditResult {
        local_points: result.local_points,
        fixed_segments: result.fixed_segments,
        start_is_special: result.start_is_special,
        end_is_special: result.end_is_special,
    }
}

/// Transforms fixed segments when the owning element is resized/rotated.
pub fn transform_fixed_segments(
    segments: Option<&[ElbowFixedSegment]>,
    old_rect: DrawRect,
    new_rect: DrawRect,
    rotation: f64,
) -> Option<Vec<ElbowFixedSegment>> {
    let segments = segments.filter(|values| !values.is_empty())?;

    let old_space = ElementSpace::new(rotation, old_rect.center());
    let new_space = ElementSpace::new(rotation, new_rect.center());

    Some(
        segments
            .iter()
            .map(|segment| {
                let world_start = old_space.to_world(segment.start);
                let world_end = old_space.to_world(segment.end);
                ElbowFixedSegment {
                    index: segment.index,
                    start: new_space.from_world(world_start),
                    end: new_space.from_world(world_end),
                }
            })
            .collect(),
    )
}
