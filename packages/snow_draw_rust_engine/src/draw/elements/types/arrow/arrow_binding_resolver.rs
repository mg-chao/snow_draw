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
        self.resolve_with_skip(
            base_elements,
            updated_elements,
            changed_element_ids,
            delegate,
            &HashSet::new(),
        )
    }

    /// Resolves bound arrows while skipping arrows that are already updated.
    pub fn resolve_with_skip<E, D>(
        &self,
        base_elements: &HashMap<String, E>,
        updated_elements: &HashMap<String, E>,
        changed_element_ids: &HashSet<String>,
        delegate: &D,
        skip_arrow_ids: &HashSet<String>,
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
            if skip_arrow_ids.contains(element.id()) {
                continue;
            }
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

            let updated = apply_bindings(
                element,
                data,
                &lookup,
                update_start,
                update_end,
                changed_element_ids,
                delegate,
            );
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
    changed_element_ids: &HashSet<String>,
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
    let original_points = local_points.clone();

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

    maybe_translate_midpoints_with_shared_bindable(
        data,
        changed_element_ids,
        &original_points,
        &mut local_points,
    );

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

fn maybe_translate_midpoints_with_shared_bindable<D>(
    data: &D,
    changed_element_ids: &HashSet<String>,
    original_points: &[DrawPoint],
    updated_points: &mut [DrawPoint],
) where
    D: ArrowLikeData,
{
    if updated_points.len() <= 2 || original_points.len() != updated_points.len() {
        return;
    }

    let Some(start_binding) = data.start_binding() else {
        return;
    };
    let Some(end_binding) = data.end_binding() else {
        return;
    };
    if start_binding.element_id != end_binding.element_id
        || !changed_element_ids.contains(&start_binding.element_id)
    {
        return;
    }

    let start_delta = updated_points[0] - original_points[0];
    let end_delta =
        updated_points[updated_points.len() - 1] - original_points[original_points.len() - 1];
    if !points_almost_equal(start_delta, end_delta) {
        return;
    }

    for index in 1..updated_points.len() - 1 {
        updated_points[index] = original_points[index] + start_delta;
    }
}

fn points_almost_equal(a: DrawPoint, b: DrawPoint) -> bool {
    (a.x - b.x).abs() <= 1e-9 && (a.y - b.y).abs() <= 1e-9
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Clone, Debug, PartialEq)]
    struct TestArrowData {
        points: Vec<DrawPoint>,
        arrow_type: ArrowType,
        start_arrowhead: ArrowheadStyle,
        end_arrowhead: ArrowheadStyle,
        start_binding: Option<ArrowBinding>,
        end_binding: Option<ArrowBinding>,
    }

    impl ArrowLikeData for TestArrowData {
        type FixedSegment = ();

        fn points(&self) -> &[DrawPoint] {
            &self.points
        }

        fn arrow_type(&self) -> ArrowType {
            self.arrow_type
        }

        fn start_arrowhead(&self) -> ArrowheadStyle {
            self.start_arrowhead
        }

        fn end_arrowhead(&self) -> ArrowheadStyle {
            self.end_arrowhead
        }

        fn start_binding(&self) -> Option<&ArrowBinding> {
            self.start_binding.as_ref()
        }

        fn end_binding(&self) -> Option<&ArrowBinding> {
            self.end_binding.as_ref()
        }

        fn with_points(&self, points: Vec<DrawPoint>) -> Self {
            let mut next = self.clone();
            next.points = points;
            next
        }
    }

    #[derive(Clone, Debug, PartialEq)]
    struct TestElement {
        id: String,
        rect: DrawRect,
        rotation: f64,
        arrow_data: Option<TestArrowData>,
    }

    impl ElementStateLike for TestElement {
        type ArrowData = TestArrowData;

        fn id(&self) -> &str {
            &self.id
        }

        fn rect(&self) -> DrawRect {
            self.rect
        }

        fn rotation(&self) -> f64 {
            self.rotation
        }

        fn arrow_like_data(&self) -> Option<&Self::ArrowData> {
            self.arrow_data.as_ref()
        }

        fn copy_with_rect_and_data(&self, rect: DrawRect, data: Self::ArrowData) -> Self {
            Self {
                id: self.id.clone(),
                rect,
                rotation: self.rotation,
                arrow_data: Some(data),
            }
        }
    }

    #[derive(Clone, Copy, Debug, Default)]
    struct TestDelegate;

    impl ArrowBindingResolverDelegate<TestElement> for TestDelegate {
        fn resolve_world_points(
            &self,
            _rect: DrawRect,
            normalized_points: &[DrawPoint],
        ) -> Vec<DrawPoint> {
            normalized_points.to_vec()
        }

        fn resolve_arrow_geometry_update(
            &self,
            local_points: &[DrawPoint],
            _old_rect: DrawRect,
            _rotation: f64,
            _arrow_type: ArrowType,
        ) -> ArrowGeometryUpdate {
            ArrowGeometryUpdate {
                rect: DrawRect::from_point_cloud(local_points.iter().copied()),
                normalized_points: local_points.to_vec(),
            }
        }

        fn resolve_bound_point(
            &self,
            binding: &ArrowBinding,
            target: &TestElement,
            _reference_point: Option<DrawPoint>,
        ) -> Option<DrawPoint> {
            Some(DrawPoint::new(
                target.rect.min_x + target.rect.width() * binding.anchor.x,
                target.rect.min_y + target.rect.height() * binding.anchor.y,
            ))
        }

        fn resolve_elbow_bound_point(
            &self,
            binding: &ArrowBinding,
            target: &TestElement,
            _has_arrowhead: bool,
        ) -> Option<DrawPoint> {
            self.resolve_bound_point(binding, target, None)
        }
    }

    #[test]
    fn recompute_keeps_middle_points_moving_with_dual_bound_target() {
        let bindable = bindable_element("bindable-1", DrawRect::new(100.0, 100.0, 220.0, 220.0));
        let arrow = arrow_element(
            "arrow-1",
            vec![
                DrawPoint::new(100.0, 160.0),
                DrawPoint::new(160.0, 120.0),
                DrawPoint::new(220.0, 160.0),
            ],
            Some(binding("bindable-1", 0.0, 0.5)),
            Some(binding("bindable-1", 1.0, 0.5)),
        );

        let delta = DrawPoint::new(40.0, 20.0);
        let moved_bindable = TestElement {
            rect: bindable.rect.translate(delta),
            ..bindable.clone()
        };

        let base = HashMap::from([
            (bindable.id.clone(), bindable.clone()),
            (arrow.id.clone(), arrow.clone()),
        ]);
        let updated = HashMap::from([(bindable.id.clone(), moved_bindable)]);
        let changed = HashSet::from([bindable.id.clone()]);

        let resolution =
            ArrowBindingResolver::INSTANCE.resolve(&base, &updated, &changed, &TestDelegate);

        let updated_arrow = resolution.get("arrow-1").expect("updated arrow");
        let updated_points = updated_arrow
            .arrow_data
            .as_ref()
            .expect("arrow data")
            .points
            .clone();

        assert_eq!(updated_points.len(), 3);
        for (updated_point, original_point) in updated_points
            .iter()
            .zip(arrow.arrow_data.as_ref().expect("arrow data").points.iter())
        {
            assert!((updated_point.x - original_point.x - delta.x).abs() <= 1e-9);
            assert!((updated_point.y - original_point.y - delta.y).abs() <= 1e-9);
        }
    }

    #[test]
    fn skips_recomputing_arrows_that_are_simultaneously_updated() {
        let bindable = bindable_element("bindable-1", DrawRect::new(100.0, 100.0, 220.0, 220.0));
        let arrow = arrow_element(
            "arrow-1",
            vec![
                DrawPoint::new(100.0, 160.0),
                DrawPoint::new(160.0, 120.0),
                DrawPoint::new(220.0, 160.0),
            ],
            Some(binding("bindable-1", 0.0, 0.5)),
            Some(binding("bindable-1", 1.0, 0.5)),
        );
        let moved_bindable = TestElement {
            rect: bindable.rect.translate(DrawPoint::new(40.0, 20.0)),
            ..bindable.clone()
        };
        let moved_arrow = arrow_element(
            "arrow-1",
            vec![
                DrawPoint::new(105.0, 165.0),
                DrawPoint::new(165.0, 125.0),
                DrawPoint::new(225.0, 165.0),
            ],
            Some(binding("bindable-1", 0.0, 0.5)),
            Some(binding("bindable-1", 1.0, 0.5)),
        );

        let base = HashMap::from([
            (bindable.id.clone(), bindable.clone()),
            (arrow.id.clone(), arrow.clone()),
        ]);
        let updated = HashMap::from([
            (bindable.id.clone(), moved_bindable),
            (arrow.id.clone(), moved_arrow),
        ]);
        let changed = HashSet::from([bindable.id.clone(), arrow.id.clone()]);

        let without_skip =
            ArrowBindingResolver::INSTANCE.resolve(&base, &updated, &changed, &TestDelegate);
        let with_skip = ArrowBindingResolver::INSTANCE.resolve_with_skip(
            &base,
            &updated,
            &changed,
            &TestDelegate,
            &HashSet::from([arrow.id.clone()]),
        );

        assert!(without_skip.contains_key(arrow.id.as_str()));
        assert!(!with_skip.contains_key(arrow.id.as_str()));
    }

    fn bindable_element(id: &str, rect: DrawRect) -> TestElement {
        TestElement {
            id: id.to_owned(),
            rect,
            rotation: 0.0,
            arrow_data: None,
        }
    }

    fn arrow_element(
        id: &str,
        points: Vec<DrawPoint>,
        start_binding: Option<ArrowBinding>,
        end_binding: Option<ArrowBinding>,
    ) -> TestElement {
        TestElement {
            id: id.to_owned(),
            rect: DrawRect::from_point_cloud(points.iter().copied()),
            rotation: 0.0,
            arrow_data: Some(TestArrowData {
                points,
                arrow_type: ArrowType::Curved,
                start_arrowhead: ArrowheadStyle::None,
                end_arrowhead: ArrowheadStyle::None,
                start_binding,
                end_binding,
            }),
        }
    }

    fn binding(id: &str, x: f64, y: f64) -> ArrowBinding {
        ArrowBinding::new(id.to_owned(), DrawPoint::new(x, y), ArrowBindingMode::Orbit)
    }
}
