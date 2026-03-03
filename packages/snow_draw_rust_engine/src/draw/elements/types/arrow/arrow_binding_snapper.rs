#![allow(dead_code)]

use crate::draw::config::draw_config::SnapConfig;
pub use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding, ArrowBindingMode, ArrowBindingResult,
};
pub use crate::draw::elements::types::arrow::arrow_binding_target_cache::ArrowBindingTargetCache;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};
use crate::draw::utils::camera_zoom::resolve_zoom_adjusted_distance;
use crate::draw::utils::snapping_mode::SnappingMode;

const PREFERRED_BINDING_STICKINESS_FACTOR: f64 = 0.3;
const DEFAULT_TARGET_CACHE_THRESHOLD_FACTOR: f64 = 0.4;
const DEFAULT_EMPTY_CACHE_THRESHOLD_FACTOR: f64 = 0.75;

/// Cache policy controlling how aggressively nearby-target queries are reused.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ArrowBindingCachePolicy {
    pub target_cache_threshold_factor: f64,
    pub empty_cache_threshold_factor: f64,
}

impl ArrowBindingCachePolicy {
    pub const fn new(
        target_cache_threshold_factor: f64,
        empty_cache_threshold_factor: f64,
    ) -> Self {
        Self {
            target_cache_threshold_factor,
            empty_cache_threshold_factor,
        }
    }

    pub const fn default_policy() -> Self {
        Self::new(
            DEFAULT_TARGET_CACHE_THRESHOLD_FACTOR,
            DEFAULT_EMPTY_CACHE_THRESHOLD_FACTOR,
        )
    }
}

impl Default for ArrowBindingCachePolicy {
    fn default() -> Self {
        Self::default_policy()
    }
}

/// Minimal element interface required by arrow binding snapping.
pub trait ArrowBindingElement {
    fn id(&self) -> &str;
    fn opacity(&self) -> f64;
}

/// State view required by arrow binding snapping.
pub trait ArrowBindingState<E>
where
    E: ArrowBindingElement + Clone,
{
    fn camera_zoom(&self) -> f64;
    fn elements_version(&self) -> i64;
    fn get_element_by_id(&self, id: &str) -> Option<E>;

    fn visit_arrow_bindable_elements_at_point(
        &self,
        position: DrawPoint,
        distance: f64,
        excluded_element_id: Option<&str>,
        visitor: &mut dyn FnMut(E) -> bool,
    );
}

/// Binding resolver integration for geometry/domain-specific logic.
pub trait ArrowBindingResolver<E>
where
    E: ArrowBindingElement + Clone,
{
    fn is_bindable_target(&self, target: &E) -> bool;

    fn resolve_binding_search_distance(&self, snap_distance: f64) -> f64;

    fn resolve_binding_candidate_for_target(
        &self,
        world_point: DrawPoint,
        target: &E,
        snap_distance: f64,
        reference_point: Option<DrawPoint>,
    ) -> Option<ArrowBindingResult>;

    fn resolve_elbow_binding_candidate_for_target(
        &self,
        world_point: DrawPoint,
        target: &E,
        snap_distance: f64,
        has_arrowhead: bool,
    ) -> Option<ArrowBindingResult>;

    fn resolve_binding_candidate(
        &self,
        world_point: DrawPoint,
        targets: &[E],
        snap_distance: f64,
        preferred_binding: Option<&ArrowBinding>,
        allow_new_binding: bool,
        reference_point: Option<DrawPoint>,
    ) -> Option<ArrowBindingResult>;

    fn resolve_elbow_binding_candidate(
        &self,
        world_point: DrawPoint,
        targets: &[E],
        snap_distance: f64,
        preferred_binding: Option<&ArrowBinding>,
        allow_new_binding: bool,
        has_arrowhead: bool,
    ) -> Option<ArrowBindingResult>;
}

/// Shared arrow-binding helpers used by create and edit interactions.
pub struct ArrowBindingSnapper;

impl ArrowBindingSnapper {
    /// Returns whether binding lookup should run for this snapping mode.
    pub fn should_attempt_binding(snap_config: &SnapConfig, snapping_mode: SnappingMode) -> bool {
        snap_config.enable_arrow_binding
            && snapping_mode != SnappingMode::Grid
            && !(snap_config.enabled && snapping_mode == SnappingMode::None)
    }

    /// Resolves effective binding distance in world units.
    pub fn resolve_binding_distance<S, E>(state: &S, snap_config: &SnapConfig) -> f64
    where
        S: ArrowBindingState<E>,
        E: ArrowBindingElement + Clone,
    {
        resolve_zoom_adjusted_distance(snap_config.arrow_binding_distance, state.camera_zoom())
    }

    /// Attempts to snap to the currently preferred binding target directly.
    ///
    /// This fast path avoids a spatial query while the pointer remains close
    /// to the already-bound target.
    #[allow(clippy::too_many_arguments)]
    pub fn resolve_preferred_binding_candidate_direct<S, E, R>(
        state: &S,
        world_point: DrawPoint,
        arrow_type: ArrowType,
        arrowhead_style: ArrowheadStyle,
        snap_distance: f64,
        allow_new_binding: bool,
        preferred_binding: Option<&ArrowBinding>,
        reference_point: Option<DrawPoint>,
        excluded_element_id: Option<&str>,
        resolver: &R,
    ) -> Option<ArrowBindingResult>
    where
        S: ArrowBindingState<E>,
        E: ArrowBindingElement + Clone,
        R: ArrowBindingResolver<E>,
    {
        let preferred_binding = preferred_binding?;
        let target = state.get_element_by_id(&preferred_binding.element_id)?;
        if target.opacity() <= 0.0
            || excluded_element_id.is_some_and(|excluded| target.id() == excluded)
            || !resolver.is_bindable_target(&target)
        {
            return None;
        }

        let candidate = resolve_binding_candidate_for_target(
            &target,
            world_point,
            arrow_type,
            arrowhead_style,
            snap_distance,
            reference_point,
            resolver,
        )?;

        if !allow_new_binding
            || candidate.distance <= snap_distance * PREFERRED_BINDING_STICKINESS_FACTOR
        {
            Some(candidate)
        } else {
            None
        }
    }

    /// Resolves an endpoint binding candidate with shared lookup/caching policy.
    #[allow(clippy::too_many_arguments)]
    pub fn resolve_endpoint_binding_candidate<S, E, R>(
        state: &S,
        world_point: DrawPoint,
        arrow_type: ArrowType,
        arrowhead_style: ArrowheadStyle,
        should_lookup_bindings: bool,
        snap_distance: f64,
        allow_new_binding: bool,
        has_bindable_targets: bool,
        preferred_binding: Option<&ArrowBinding>,
        reference_point: Option<DrawPoint>,
        cache: Option<&mut ArrowBindingTargetCache<E>>,
        excluded_element_id: Option<&str>,
        cache_policy: ArrowBindingCachePolicy,
        resolver: &R,
    ) -> Option<ArrowBindingResult>
    where
        S: ArrowBindingState<E>,
        E: ArrowBindingElement + Clone,
        R: ArrowBindingResolver<E>,
    {
        if !can_resolve_endpoint_binding_lookup(
            snap_distance,
            should_lookup_bindings,
            allow_new_binding,
            preferred_binding,
        ) {
            if let Some(cache) = cache {
                cache.reset();
            }
            return None;
        }

        let preferred_direct = Self::resolve_preferred_binding_candidate_direct(
            state,
            world_point,
            arrow_type,
            arrowhead_style,
            snap_distance,
            allow_new_binding,
            preferred_binding,
            reference_point,
            excluded_element_id,
            resolver,
        );
        if preferred_direct.is_some() {
            return preferred_direct;
        }

        if !allow_new_binding || !has_bindable_targets {
            return None;
        }

        let search_distance = resolver.resolve_binding_search_distance(snap_distance);
        let targets = Self::resolve_binding_targets_cached(
            state,
            world_point,
            search_distance,
            cache,
            excluded_element_id,
            cache_policy,
        );
        if targets.is_empty() {
            return None;
        }

        if arrow_type == ArrowType::Elbow {
            return resolver.resolve_elbow_binding_candidate(
                world_point,
                &targets,
                snap_distance,
                preferred_binding,
                allow_new_binding,
                arrowhead_style != ArrowheadStyle::None,
            );
        }

        resolver.resolve_binding_candidate(
            world_point,
            &targets,
            snap_distance,
            preferred_binding,
            allow_new_binding,
            reference_point,
        )
    }

    /// Resolves nearby bindable targets using `cache` when possible.
    pub fn resolve_binding_targets_cached<S, E>(
        state: &S,
        position: DrawPoint,
        distance: f64,
        cache: Option<&mut ArrowBindingTargetCache<E>>,
        excluded_element_id: Option<&str>,
        cache_policy: ArrowBindingCachePolicy,
    ) -> Vec<E>
    where
        S: ArrowBindingState<E>,
        E: ArrowBindingElement + Clone,
    {
        let Some(cache) = cache else {
            return resolve_binding_targets(state, position, distance, excluded_element_id);
        };

        let elements_version = state.elements_version();
        let threshold_factor = if cache.targets().is_empty() {
            cache_policy.empty_cache_threshold_factor
        } else {
            cache_policy.target_cache_threshold_factor
        };
        let threshold = distance * threshold_factor;
        if cache.is_valid(position, threshold, distance, elements_version) {
            return cache.targets().to_vec();
        }

        let targets = resolve_binding_targets(state, position, distance, excluded_element_id);
        cache.update(position, distance, elements_version, targets.clone());
        targets
    }
}

fn resolve_binding_targets<S, E>(
    state: &S,
    position: DrawPoint,
    distance: f64,
    excluded_element_id: Option<&str>,
) -> Vec<E>
where
    S: ArrowBindingState<E>,
    E: ArrowBindingElement + Clone,
{
    let mut targets = Vec::new();
    let mut visitor = |element: E| {
        targets.push(element);
        true
    };
    state.visit_arrow_bindable_elements_at_point(
        position,
        distance,
        excluded_element_id,
        &mut visitor,
    );
    targets
}

fn resolve_binding_candidate_for_target<E, R>(
    target: &E,
    world_point: DrawPoint,
    arrow_type: ArrowType,
    arrowhead_style: ArrowheadStyle,
    snap_distance: f64,
    reference_point: Option<DrawPoint>,
    resolver: &R,
) -> Option<ArrowBindingResult>
where
    E: ArrowBindingElement + Clone,
    R: ArrowBindingResolver<E>,
{
    if arrow_type == ArrowType::Elbow {
        resolver.resolve_elbow_binding_candidate_for_target(
            world_point,
            target,
            snap_distance,
            arrowhead_style != ArrowheadStyle::None,
        )
    } else {
        resolver.resolve_binding_candidate_for_target(
            world_point,
            target,
            snap_distance,
            reference_point,
        )
    }
}

fn can_resolve_endpoint_binding_lookup(
    snap_distance: f64,
    should_lookup_bindings: bool,
    allow_new_binding: bool,
    preferred_binding: Option<&ArrowBinding>,
) -> bool {
    snap_distance > 0.0
        && should_lookup_bindings
        && (allow_new_binding || preferred_binding.is_some())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[derive(Clone, Debug, PartialEq)]
    struct TestElement {
        id: String,
        opacity: f64,
        bindable: bool,
    }

    impl ArrowBindingElement for TestElement {
        fn id(&self) -> &str {
            &self.id
        }

        fn opacity(&self) -> f64 {
            self.opacity
        }
    }

    struct TestState {
        zoom: f64,
        elements_version: i64,
        elements: HashMap<String, TestElement>,
        nearby: Vec<TestElement>,
    }

    impl ArrowBindingState<TestElement> for TestState {
        fn camera_zoom(&self) -> f64 {
            self.zoom
        }

        fn elements_version(&self) -> i64 {
            self.elements_version
        }

        fn get_element_by_id(&self, id: &str) -> Option<TestElement> {
            self.elements.get(id).cloned()
        }

        fn visit_arrow_bindable_elements_at_point(
            &self,
            _position: DrawPoint,
            _distance: f64,
            excluded_element_id: Option<&str>,
            visitor: &mut dyn FnMut(TestElement) -> bool,
        ) {
            for element in &self.nearby {
                if excluded_element_id.is_some_and(|excluded| excluded == element.id) {
                    continue;
                }
                if !visitor(element.clone()) {
                    break;
                }
            }
        }
    }

    #[derive(Clone, Copy)]
    struct TestResolver;

    impl ArrowBindingResolver<TestElement> for TestResolver {
        fn is_bindable_target(&self, target: &TestElement) -> bool {
            target.bindable
        }

        fn resolve_binding_search_distance(&self, snap_distance: f64) -> f64 {
            snap_distance * 1.4
        }

        fn resolve_binding_candidate_for_target(
            &self,
            world_point: DrawPoint,
            target: &TestElement,
            _snap_distance: f64,
            _reference_point: Option<DrawPoint>,
        ) -> Option<ArrowBindingResult> {
            if !target.bindable || target.opacity <= 0.0 {
                return None;
            }
            Some(ArrowBindingResult {
                binding: ArrowBinding::new(
                    target.id.clone(),
                    DrawPoint::ZERO,
                    ArrowBindingMode::Orbit,
                ),
                snap_point: world_point,
                distance: 1.0,
                z_index: 0,
            })
        }

        fn resolve_elbow_binding_candidate_for_target(
            &self,
            world_point: DrawPoint,
            target: &TestElement,
            snap_distance: f64,
            _has_arrowhead: bool,
        ) -> Option<ArrowBindingResult> {
            self.resolve_binding_candidate_for_target(world_point, target, snap_distance, None)
        }

        fn resolve_binding_candidate(
            &self,
            world_point: DrawPoint,
            targets: &[TestElement],
            snap_distance: f64,
            _preferred_binding: Option<&ArrowBinding>,
            _allow_new_binding: bool,
            _reference_point: Option<DrawPoint>,
        ) -> Option<ArrowBindingResult> {
            let target = targets.first()?;
            self.resolve_binding_candidate_for_target(world_point, target, snap_distance, None)
        }

        fn resolve_elbow_binding_candidate(
            &self,
            world_point: DrawPoint,
            targets: &[TestElement],
            snap_distance: f64,
            preferred_binding: Option<&ArrowBinding>,
            allow_new_binding: bool,
            _has_arrowhead: bool,
        ) -> Option<ArrowBindingResult> {
            self.resolve_binding_candidate(
                world_point,
                targets,
                snap_distance,
                preferred_binding,
                allow_new_binding,
                None,
            )
        }
    }

    fn make_state() -> TestState {
        let element = TestElement {
            id: "target-1".to_string(),
            opacity: 1.0,
            bindable: true,
        };
        let mut elements = HashMap::new();
        elements.insert(element.id.clone(), element.clone());

        TestState {
            zoom: 2.0,
            elements_version: 7,
            elements,
            nearby: vec![element],
        }
    }

    #[test]
    fn should_attempt_binding_matches_dart_logic() {
        let mut snap = SnapConfig::default();
        snap.enable_arrow_binding = true;
        snap.enabled = false;
        assert!(ArrowBindingSnapper::should_attempt_binding(
            &snap,
            SnappingMode::Object
        ));
        assert!(!ArrowBindingSnapper::should_attempt_binding(
            &snap,
            SnappingMode::Grid
        ));

        snap.enabled = true;
        assert!(!ArrowBindingSnapper::should_attempt_binding(
            &snap,
            SnappingMode::None
        ));
    }

    #[test]
    fn resolve_binding_distance_applies_zoom_conversion() {
        let state = make_state();
        let snap = SnapConfig::default();
        let world_distance = ArrowBindingSnapper::resolve_binding_distance(&state, &snap);
        assert_eq!(world_distance, snap.arrow_binding_distance / 2.0);
    }

    #[test]
    fn resolves_preferred_direct_candidate_when_target_is_valid() {
        let state = make_state();
        let resolver = TestResolver;
        let binding = ArrowBinding::new("target-1", DrawPoint::ZERO, ArrowBindingMode::Orbit);

        let candidate = ArrowBindingSnapper::resolve_preferred_binding_candidate_direct(
            &state,
            DrawPoint::new(10.0, 20.0),
            ArrowType::Straight,
            ArrowheadStyle::Standard,
            10.0,
            false,
            Some(&binding),
            None,
            None,
            &resolver,
        );

        assert!(candidate.is_some());
        assert_eq!(
            candidate.map(|c| c.binding.element_id),
            Some("target-1".to_string())
        );
    }

    #[test]
    fn endpoint_lookup_resets_cache_when_lookup_is_disabled() {
        let state = make_state();
        let resolver = TestResolver;
        let mut cache = ArrowBindingTargetCache::<TestElement>::default();
        cache.update(
            DrawPoint::new(1.0, 1.0),
            10.0,
            state.elements_version(),
            state.nearby.clone(),
        );

        let candidate = ArrowBindingSnapper::resolve_endpoint_binding_candidate(
            &state,
            DrawPoint::ZERO,
            ArrowType::Straight,
            ArrowheadStyle::None,
            false,
            10.0,
            true,
            true,
            None,
            None,
            Some(&mut cache),
            None,
            ArrowBindingCachePolicy::default(),
            &resolver,
        );

        assert!(candidate.is_none());
        assert!(cache.targets().is_empty());
    }
}
