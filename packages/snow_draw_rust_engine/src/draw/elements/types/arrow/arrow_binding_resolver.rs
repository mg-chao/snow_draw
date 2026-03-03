#![allow(dead_code)]

use crate::draw::core::coordinates::element_space::ElementSpace;
pub use crate::draw::elements::types::arrow::arrow_binding::{ArrowBinding, ArrowBindingMode};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};
use crate::draw::utils::combined_element_lookup::CombinedElementLookup;
use std::collections::{HashMap, HashSet};

type FixedSegmentOf<E> = <<E as ElementStateLike>::ArrowData as ArrowLikeData>::FixedSegment;

/// Arrow-like payload shape required by binding resolution.
pub trait ArrowLikeData: Clone + PartialEq {
    type FixedSegment: Clone + PartialEq;

    fn points(&self) -> &[DrawPoint];
    fn arrow_type(&self) -> ArrowType;
    fn start_arrowhead(&self) -> ArrowheadStyle;
    fn end_arrowhead(&self) -> ArrowheadStyle;
    fn start_binding(&self) -> Option<&ArrowBinding>;
    fn end_binding(&self) -> Option<&ArrowBinding>;
    fn fixed_segments(&self) -> Option<&[Self::FixedSegment]> {
        None
    }

    fn with_points(&self, points: Vec<DrawPoint>) -> Self;

    fn with_elbow_edit(
        &self,
        points: Vec<DrawPoint>,
        fixed_segments: Option<Vec<Self::FixedSegment>>,
        start_is_special: Option<bool>,
        end_is_special: Option<bool>,
    ) -> Self {
        let _ = (fixed_segments, start_is_special, end_is_special);
        self.with_points(points)
    }
}

/// Element shape required by [`ArrowBindingResolver`].
pub trait ElementStateLike: Clone {
    type ArrowData: ArrowLikeData;

    fn id(&self) -> &str;
    fn rect(&self) -> DrawRect;
    fn rotation(&self) -> f64;
    fn arrow_like_data(&self) -> Option<&Self::ArrowData>;
    fn copy_with_rect_and_data(&self, rect: DrawRect, data: Self::ArrowData) -> Self;
}

/// Result of recomputing geometry after point updates.
#[derive(Clone, Debug, PartialEq)]
pub struct ArrowGeometryUpdate {
    pub rect: DrawRect,
    pub normalized_points: Vec<DrawPoint>,
}

/// Result of elbow edit processing.
#[derive(Clone, Debug, PartialEq)]
pub struct ElbowEditResult<S> {
    pub local_points: Vec<DrawPoint>,
    pub fixed_segments: Option<Vec<S>>,
    pub start_is_special: Option<bool>,
    pub end_is_special: Option<bool>,
}

/// Delegate that bridges the resolver to geometry, binding and elbow services.
pub trait ArrowBindingResolverDelegate<E: ElementStateLike> {
    fn resolve_world_points(
        &self,
        rect: DrawRect,
        normalized_points: &[DrawPoint],
    ) -> Vec<DrawPoint>;

    fn resolve_arrow_geometry_update(
        &self,
        local_points: &[DrawPoint],
        old_rect: DrawRect,
        rotation: f64,
        arrow_type: ArrowType,
    ) -> ArrowGeometryUpdate;

    fn resolve_bound_point(
        &self,
        binding: &ArrowBinding,
        target: &E,
        reference_point: Option<DrawPoint>,
    ) -> Option<DrawPoint>;

    fn resolve_elbow_bound_point(
        &self,
        binding: &ArrowBinding,
        target: &E,
        has_arrowhead: bool,
    ) -> Option<DrawPoint>;

    fn compute_elbow_edit(
        &self,
        element: &E,
        data: &E::ArrowData,
        lookup: &CombinedElementLookup<'_, E>,
        local_points_override: &[DrawPoint],
        fixed_segments_override: Option<&[FixedSegmentOf<E>]>,
    ) -> Option<ElbowEditResult<FixedSegmentOf<E>>> {
        let _ = (
            element,
            data,
            lookup,
            local_points_override,
            fixed_segments_override,
        );
        None
    }

    fn transform_fixed_segments(
        &self,
        segments: Option<&[FixedSegmentOf<E>]>,
        _old_rect: DrawRect,
        _new_rect: DrawRect,
        _rotation: f64,
    ) -> Option<Vec<FixedSegmentOf<E>>> {
        segments.map(|value| value.to_vec())
    }
}

/// Resolves arrow bindings when bound elements change.
///
/// Mirrors the Dart resolver behavior:
/// every pass scans current arrow-like elements and applies endpoint updates
/// when either bound target has changed.
#[derive(Clone, Copy, Debug, Default)]
pub struct ArrowBindingResolver;

impl ArrowBindingResolver {
    /// Global stateless resolver instance.
    pub const INSTANCE: Self = Self;

    pub const fn new() -> Self {
        Self
    }

    /// Resolves bound arrows when elements change.
    ///
    /// Uses [`CombinedElementLookup`] to avoid allocating merged maps.
    pub fn resolve<E, D>(
        &self,
        base_elements: &HashMap<String, E>,
        updated_elements: &HashMap<String, E>,
        changed_element_ids: &HashSet<String>,
        delegate: &D,
    ) -> HashMap<String, E>
    where
        E: ElementStateLike,
        D: ArrowBindingResolverDelegate<E>,
    {
        if changed_element_ids.is_empty() {
            return HashMap::new();
        }

        let lookup = CombinedElementLookup::new(base_elements, updated_elements);
        let mut updates = HashMap::new();

        for element in lookup.values() {
            let Some(data) = element.arrow_like_data() else {
                continue;
            };

            let start_binding = data.start_binding();
            let end_binding = data.end_binding();
            if start_binding.is_none() && end_binding.is_none() {
                continue;
            }

            let update_start = start_binding
                .is_some_and(|binding| changed_element_ids.contains(&binding.element_id));
            let update_end = end_binding
                .is_some_and(|binding| changed_element_ids.contains(&binding.element_id));
            if !update_start && !update_end {
                continue;
            }

            let updated =
                apply_bindings(element, data, &lookup, update_start, update_end, delegate);
            if let Some(updated_element) = updated {
                updates.insert(updated_element.id().to_string(), updated_element);
            }
        }

        updates
    }
}

fn apply_bindings<E, D>(
    element: &E,
    data: &E::ArrowData,
    lookup: &CombinedElementLookup<'_, E>,
    update_start: bool,
    update_end: bool,
    delegate: &D,
) -> Option<E>
where
    E: ElementStateLike,
    D: ArrowBindingResolverDelegate<E>,
{
    assert!(
        update_start || update_end,
        "At least one endpoint must be updated."
    );

    let mut local_points = resolve_local_points(element, data, delegate);
    if local_points.len() < 2 {
        return None;
    }

    let sync_both_ends = data.start_binding().is_some() && data.end_binding().is_some();
    let should_update_start = update_start || sync_both_ends;
    let should_update_end = update_end || sync_both_ends;

    let rect = element.rect();
    let space = ElementSpace::new(element.rotation(), rect.center());
    let is_elbow = data.arrow_type() == ArrowType::Elbow;
    let max_iterations = if should_update_start && should_update_end && local_points.len() == 2 {
        4
    } else {
        2
    };

    let mut changed_at_least_once = false;
    for _ in 0..max_iterations {
        let mut changed_this_pass = false;
        let start_reference = space.to_world(local_points[1]);
        let end_reference = space.to_world(local_points[local_points.len() - 2]);

        changed_this_pass |= apply_bound_endpoint(
            data.start_binding(),
            should_update_start,
            0,
            start_reference,
            lookup,
            space,
            is_elbow,
            data.start_arrowhead() != ArrowheadStyle::None,
            &mut local_points,
            delegate,
        );

        changed_this_pass |= apply_bound_endpoint(
            data.end_binding(),
            should_update_end,
            local_points.len() - 1,
            end_reference,
            lookup,
            space,
            is_elbow,
            data.end_arrowhead() != ArrowheadStyle::None,
            &mut local_points,
            delegate,
        );

        if !changed_this_pass {
            break;
        }
        changed_at_least_once = true;
    }

    if !changed_at_least_once {
        return None;
    }

    if data.arrow_type() == ArrowType::Elbow {
        if let Some(updated) =
            apply_elbow_binding_result(element, data, lookup, &local_points, delegate)
        {
            return Some(updated);
        }
    }

    let geometry = delegate.resolve_arrow_geometry_update(
        &local_points,
        element.rect(),
        element.rotation(),
        data.arrow_type(),
    );
    let updated_data = data.with_points(geometry.normalized_points);
    build_updated_element_or_null(element, data, updated_data, geometry.rect)
}

fn apply_bound_endpoint<E, D>(
    binding: Option<&ArrowBinding>,
    should_update: bool,
    point_index: usize,
    reference_point: DrawPoint,
    lookup: &CombinedElementLookup<'_, E>,
    space: ElementSpace,
    is_elbow: bool,
    has_arrowhead: bool,
    local_points: &mut [DrawPoint],
    delegate: &D,
) -> bool
where
    E: ElementStateLike,
    D: ArrowBindingResolverDelegate<E>,
{
    let Some(binding) = binding else {
        return false;
    };
    if !should_update {
        return false;
    }

    let next_local = resolve_bound_local_point(
        binding,
        lookup,
        space,
        is_elbow,
        has_arrowhead,
        Some(reference_point),
        delegate,
    );
    let Some(next_local) = next_local else {
        return false;
    };

    let Some(current) = local_points.get(point_index).copied() else {
        return false;
    };
    if current == next_local {
        return false;
    }

    if let Some(slot) = local_points.get_mut(point_index) {
        *slot = next_local;
        true
    } else {
        false
    }
}

fn apply_elbow_binding_result<E, D>(
    element: &E,
    data: &E::ArrowData,
    lookup: &CombinedElementLookup<'_, E>,
    local_points: &[DrawPoint],
    delegate: &D,
) -> Option<E>
where
    E: ElementStateLike,
    D: ArrowBindingResolverDelegate<E>,
{
    let updated =
        delegate.compute_elbow_edit(element, data, lookup, local_points, data.fixed_segments())?;

    let geometry = delegate.resolve_arrow_geometry_update(
        &updated.local_points,
        element.rect(),
        element.rotation(),
        data.arrow_type(),
    );
    let transformed_fixed_segments = delegate.transform_fixed_segments(
        updated.fixed_segments.as_deref(),
        element.rect(),
        geometry.rect,
        element.rotation(),
    );
    let updated_data = data.with_elbow_edit(
        geometry.normalized_points,
        transformed_fixed_segments,
        updated.start_is_special,
        updated.end_is_special,
    );

    build_updated_element_or_null(element, data, updated_data, geometry.rect)
}

fn build_updated_element_or_null<E>(
    element: &E,
    previous_data: &E::ArrowData,
    next_data: E::ArrowData,
    next_rect: DrawRect,
) -> Option<E>
where
    E: ElementStateLike,
{
    if &next_data == previous_data && next_rect == element.rect() {
        return None;
    }
    Some(element.copy_with_rect_and_data(next_rect, next_data))
}

fn resolve_bound_local_point<E, D>(
    binding: &ArrowBinding,
    lookup: &CombinedElementLookup<'_, E>,
    space: ElementSpace,
    is_elbow: bool,
    has_arrowhead: bool,
    reference_point: Option<DrawPoint>,
    delegate: &D,
) -> Option<DrawPoint>
where
    E: ElementStateLike,
    D: ArrowBindingResolverDelegate<E>,
{
    let target = lookup.get(&binding.element_id)?;
    let bound_point = if is_elbow {
        delegate.resolve_elbow_bound_point(binding, target, has_arrowhead)?
    } else {
        delegate.resolve_bound_point(binding, target, reference_point)?
    };

    Some(space.from_world(bound_point))
}

fn resolve_local_points<E, D>(element: &E, data: &E::ArrowData, delegate: &D) -> Vec<DrawPoint>
where
    E: ElementStateLike,
    D: ArrowBindingResolverDelegate<E>,
{
    delegate.resolve_world_points(element.rect(), data.points())
}
