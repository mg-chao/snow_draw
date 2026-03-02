#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_binding_resolver::{
    ArrowBindingResolver, ArrowBindingResolverDelegate, ElementStateLike,
};
use crate::draw::types::draw_rect::DrawRect;
use std::collections::{HashMap, HashSet};

/// Shared geometry result for edit preview and commit.
///
/// Mirrors the Dart `EditComputedResult` shape used by edit operations.
#[derive(Clone, Debug, PartialEq)]
pub struct EditComputedResult<E> {
    pub updated_elements: HashMap<String, E>,
    pub multi_select_bounds: Option<DrawRect>,
    pub multi_select_rotation: Option<f64>,
}

impl<E> EditComputedResult<E> {
    pub fn new(
        updated_elements: HashMap<String, E>,
        multi_select_bounds: Option<DrawRect>,
        multi_select_rotation: Option<f64>,
    ) -> Self {
        Self {
            updated_elements,
            multi_select_bounds,
            multi_select_rotation,
        }
    }
}

/// Minimum draw-state view required by [`EditComputePipeline`].
pub trait EditComputeState<E> {
    /// Returns the current document element map by element id.
    fn element_map(&self) -> &HashMap<String, E>;
}

/// Arrow-binding cleanup hook executed before binding resolution.
///
/// The dedicated cleanup module is translated separately, so the pipeline uses
/// this trait to stay composable and compile-friendly in the meantime.
pub trait ArrowBindingCleanup<E> {
    fn unbind_arrow_like_elements(
        &self,
        transformed_elements: &HashMap<String, E>,
        base_elements: &HashMap<String, E>,
    ) -> HashMap<String, E>;
}

/// Default cleanup strategy that leaves transformed elements unchanged.
#[derive(Clone, Copy, Debug, Default)]
pub struct NoopArrowBindingCleanup;

impl<E> ArrowBindingCleanup<E> for NoopArrowBindingCleanup {
    fn unbind_arrow_like_elements(
        &self,
        _transformed_elements: &HashMap<String, E>,
        _base_elements: &HashMap<String, E>,
    ) -> HashMap<String, E> {
        HashMap::new()
    }
}

/// Shared post-geometry pipeline for standard edit operations.
///
/// After an operation applies geometry (move/resize/rotate), the remaining
/// pipeline is identical: unbind arrows, resolve bindings, and package the
/// result.
#[derive(Clone, Copy, Debug, Default)]
pub struct EditComputePipeline;

impl EditComputePipeline {
    /// Runs the shared post-geometry pipeline on `updated_by_id`.
    ///
    /// Returns `None` when `updated_by_id` is empty.
    /// Uses [`NoopArrowBindingCleanup`] for the cleanup step.
    pub fn finalize<S, E, D>(
        state: &S,
        updated_by_id: HashMap<String, E>,
        multi_select_bounds: Option<DrawRect>,
        multi_select_rotation: Option<f64>,
        skip_binding_update: Option<&dyn Fn(&str, &E) -> bool>,
        binding_delegate: &D,
    ) -> Option<EditComputedResult<E>>
    where
        S: EditComputeState<E>,
        E: ElementStateLike,
        D: ArrowBindingResolverDelegate<E>,
    {
        Self::finalize_with_cleanup(
            state,
            updated_by_id,
            multi_select_bounds,
            multi_select_rotation,
            skip_binding_update,
            binding_delegate,
            &NoopArrowBindingCleanup,
        )
    }

    /// Runs the shared post-geometry pipeline with an explicit cleanup hook.
    pub fn finalize_with_cleanup<S, E, D, C>(
        state: &S,
        updated_by_id: HashMap<String, E>,
        multi_select_bounds: Option<DrawRect>,
        multi_select_rotation: Option<f64>,
        skip_binding_update: Option<&dyn Fn(&str, &E) -> bool>,
        binding_delegate: &D,
        cleanup: &C,
    ) -> Option<EditComputedResult<E>>
    where
        S: EditComputeState<E>,
        E: ElementStateLike,
        D: ArrowBindingResolverDelegate<E>,
        C: ArrowBindingCleanup<E>,
    {
        if updated_by_id.is_empty() {
            return None;
        }

        let base_elements = state.element_map();
        let mut merged = updated_by_id;

        let cleanup_updates = cleanup.unbind_arrow_like_elements(&merged, base_elements);
        merged.extend(cleanup_updates);

        let changed_element_ids = merged.keys().cloned().collect::<HashSet<_>>();
        let binding_updates = ArrowBindingResolver::INSTANCE.resolve(
            base_elements,
            &merged,
            &changed_element_ids,
            binding_delegate,
        );

        for (id, element) in binding_updates {
            let should_skip = skip_binding_update
                .map(|predicate| predicate(id.as_str(), &element))
                .unwrap_or(false);
            if should_skip {
                continue;
            }
            merged.insert(id, element);
        }

        Some(EditComputedResult::new(
            merged,
            multi_select_bounds,
            multi_select_rotation,
        ))
    }
}
