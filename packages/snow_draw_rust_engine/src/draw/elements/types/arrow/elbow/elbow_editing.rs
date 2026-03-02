#![allow(dead_code)]

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::types::arrow::arrow_data::{ArrowBinding, ArrowData, ElbowFixedSegment};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::utils::combined_element_lookup::CombinedElementLookup;

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
///
/// The heavy edit pipeline from Dart `part` files is translated in dedicated
/// modules. Until those modules are wired together, this function keeps the
/// public shape stable and returns a conservative result.
pub fn compute_elbow_edit<E>(
    element: &E,
    data: &ArrowData,
    lookup: &CombinedElementLookup<'_, E>,
    local_points_override: Option<Vec<DrawPoint>>,
    fixed_segments_override: Option<Vec<ElbowFixedSegment>>,
    start_binding_override: BindingOverride<ArrowBinding>,
    end_binding_override: BindingOverride<ArrowBinding>,
    finalize: bool,
) -> ElbowEditResult {
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
    _element: &E,
    data: &ArrowData,
    _lookup: &CombinedElementLookup<'_, E>,
    local_points_override: Option<Vec<DrawPoint>>,
    fixed_segments_override: Option<Vec<ElbowFixedSegment>>,
    start_binding_override: BindingOverride<ArrowBinding>,
    end_binding_override: BindingOverride<ArrowBinding>,
) -> ElbowEditResult {
    // Resolve overrides now so callers can safely pass tri-state updates even
    // before full endpoint drag/fixed-segment pipeline translation lands.
    let _start_binding = start_binding_override.resolve(data.start_binding.clone());
    let _end_binding = end_binding_override.resolve(data.end_binding.clone());

    ElbowEditResult {
        local_points: local_points_override.unwrap_or_else(|| data.points.clone()),
        fixed_segments: fixed_segments_override.or_else(|| data.fixed_segments.clone()),
        start_is_special: data.start_is_special,
        end_is_special: data.end_is_special,
    }
}

fn finalize_elbow_edit_result<E>(
    _element: &E,
    _data: &ArrowData,
    _lookup: &CombinedElementLookup<'_, E>,
    result: ElbowEditResult,
    _start_binding_override: BindingOverride<ArrowBinding>,
    _end_binding_override: BindingOverride<ArrowBinding>,
) -> ElbowEditResult {
    // Dart finalization removes fixed-segment adjacency artifacts and reruns
    // the pipeline. Keep this as a no-op until those helpers are translated.
    result
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
