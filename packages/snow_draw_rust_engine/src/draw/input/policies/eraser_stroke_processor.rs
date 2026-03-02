#![allow(dead_code)]

use std::collections::HashMap;
use std::sync::Arc;

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::core::element_hit_tester::{
    ElementHitTester, ElementState as HitTesterElementState,
};
use crate::draw::models::draw_state_view::{DocumentState, DrawStateView, ElementState};
use crate::draw::types::draw_point::DrawPoint;

/// Resolves the hit tester used for an element during eraser processing.
pub type EraserHitTesterResolver =
    dyn Fn(&ElementState) -> Option<Arc<dyn ElementHitTester>> + Send + Sync;

/// Converts pointer movement into eraser-hit candidates.
///
/// The processor keeps per-pointer stroke continuity and samples each stroke
/// segment against element candidates. The current `DrawStateView` translation
/// does not expose a point-query spatial index yet, so this module performs a
/// direct candidate scan and preserves the same hit semantics.
#[derive(Clone)]
pub struct EraserStrokeProcessor {
    hit_tester_resolver: Arc<EraserHitTesterResolver>,
    last_processed_positions: HashMap<i64, DrawPoint>,
    effective_element_cache: HashMap<String, ElementState>,
    cached_effective_state_view_ptr: Option<usize>,
}

impl EraserStrokeProcessor {
    const DISTANCE_SQUARED_EPSILON: f64 = 1e-9;
    const SAMPLE_STEP_FACTOR: f64 = 0.5;

    pub fn new(hit_tester_resolver: Arc<EraserHitTesterResolver>) -> Self {
        Self {
            hit_tester_resolver,
            last_processed_positions: HashMap::new(),
            effective_element_cache: HashMap::new(),
            cached_effective_state_view_ptr: None,
        }
    }

    pub fn with_hit_tester_resolver<F>(hit_tester_resolver: F) -> Self
    where
        F: Fn(&ElementState) -> Option<Arc<dyn ElementHitTester>> + Send + Sync + 'static,
    {
        Self::new(Arc::new(hit_tester_resolver))
    }

    /// Clears all stroke state.
    pub fn reset(&mut self) {
        self.last_processed_positions.clear();
        self.clear_effective_element_cache();
    }

    /// Clears the cached last position for a pointer.
    pub fn clear_pointer(&mut self, pointer_id: i64) {
        self.last_processed_positions.remove(&pointer_id);
    }

    /// Marks elements intersecting the latest pointer movement segment.
    ///
    /// Returns `true` when at least one new element was queued for preview.
    #[allow(clippy::too_many_arguments)]
    pub fn mark_elements_for_erase<FIsQueuedForPreview, FQueuePreview>(
        &mut self,
        pointer_id: i64,
        position: DrawPoint,
        state_view: &DrawStateView,
        tolerance: f64,
        mut is_queued_for_preview: FIsQueuedForPreview,
        mut queue_preview: FQueuePreview,
    ) -> bool
    where
        FIsQueuedForPreview: FnMut(&str) -> bool,
        FQueuePreview: FnMut(&ElementState) -> bool,
    {
        let previous = self.last_processed_positions.insert(pointer_id, position);
        let stroke_start = previous.unwrap_or(position);
        let include_start = previous.is_none();
        let resolved_tolerance = Self::sanitize_tolerance(tolerance);

        let document = &state_view.state.domain.document;
        if document.elements.is_empty() {
            self.clear_effective_element_cache();
            return false;
        }

        let has_preview_overrides = !state_view.preview_elements_by_id().is_empty();
        self.sync_effective_element_cache(state_view, has_preview_overrides);

        let mut has_new_hits = false;
        Self::visit_stroke_samples(
            stroke_start,
            position,
            resolved_tolerance,
            include_start,
            |sample| {
                if self.visit_sample_candidates(
                    document,
                    sample,
                    resolved_tolerance,
                    state_view,
                    has_preview_overrides,
                    &mut is_queued_for_preview,
                    &mut queue_preview,
                ) {
                    has_new_hits = true;
                }
            },
        );

        has_new_hits
    }

    fn visit_sample_candidates<FIsQueuedForPreview, FQueuePreview>(
        &mut self,
        document: &DocumentState,
        sample: DrawPoint,
        tolerance: f64,
        state_view: &DrawStateView,
        has_preview_overrides: bool,
        is_queued_for_preview: &mut FIsQueuedForPreview,
        queue_preview: &mut FQueuePreview,
    ) -> bool
    where
        FIsQueuedForPreview: FnMut(&str) -> bool,
        FQueuePreview: FnMut(&ElementState) -> bool,
    {
        let mut has_new_hits = false;

        for candidate in &document.elements {
            if is_queued_for_preview(&candidate.id) {
                continue;
            }

            let element =
                self.resolve_effective_element(candidate, state_view, has_preview_overrides);
            if !self.is_element_hit_at_sample(&element, sample, tolerance) {
                continue;
            }

            if queue_preview(&element) {
                has_new_hits = true;
            }
        }

        has_new_hits
    }

    fn clear_effective_element_cache(&mut self) {
        self.effective_element_cache.clear();
        self.cached_effective_state_view_ptr = None;
    }

    fn sync_effective_element_cache(
        &mut self,
        state_view: &DrawStateView,
        has_preview_overrides: bool,
    ) {
        if !has_preview_overrides {
            self.clear_effective_element_cache();
            return;
        }

        let state_view_ptr = state_view as *const DrawStateView as usize;
        if self.cached_effective_state_view_ptr != Some(state_view_ptr) {
            self.effective_element_cache.clear();
            self.cached_effective_state_view_ptr = Some(state_view_ptr);
        }
    }

    fn resolve_effective_element(
        &mut self,
        candidate: &ElementState,
        state_view: &DrawStateView,
        has_preview_overrides: bool,
    ) -> ElementState {
        if !has_preview_overrides {
            return candidate.clone();
        }

        if let Some(cached) = self.effective_element_cache.get(&candidate.id) {
            return cached.clone();
        }

        let effective = state_view.effective_element(candidate);
        self.effective_element_cache
            .insert(candidate.id.clone(), effective.clone());
        effective
    }

    fn sanitize_tolerance(tolerance: f64) -> f64 {
        if !tolerance.is_finite() || tolerance <= 0.0 {
            return 0.0;
        }
        tolerance
    }

    fn is_element_hit_at_sample(
        &self,
        element: &ElementState,
        sample: DrawPoint,
        tolerance: f64,
    ) -> bool {
        if let Some(hit_tester) = (self.hit_tester_resolver)(element) {
            let tester_element = HitTesterElementState::new(element.id.clone(), element.rect);
            return hit_tester.hit_test_with_tolerance(&tester_element, sample, tolerance);
        }

        self.is_inside_rect_with_tolerance(element, sample, tolerance)
    }

    fn is_inside_rect_with_tolerance(
        &self,
        element: &ElementState,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool {
        let rect = element.rect;
        let local = if element.rotation == 0.0 {
            position
        } else {
            ElementSpace::new(element.rotation, rect.center()).from_world(position)
        };

        local.x >= rect.min_x - tolerance
            && local.x <= rect.max_x + tolerance
            && local.y >= rect.min_y - tolerance
            && local.y <= rect.max_y + tolerance
    }

    fn visit_stroke_samples<F>(
        start: DrawPoint,
        end: DrawPoint,
        tolerance: f64,
        include_start: bool,
        mut on_sample: F,
    ) where
        F: FnMut(DrawPoint),
    {
        let dx = end.x - start.x;
        let dy = end.y - start.y;
        let distance_squared = dx * dx + dy * dy;
        if !distance_squared.is_finite() || distance_squared <= Self::DISTANCE_SQUARED_EPSILON {
            if include_start {
                on_sample(end);
            }
            return;
        }

        let sample_step = tolerance * Self::SAMPLE_STEP_FACTOR;
        if sample_step <= 0.0 {
            if include_start {
                on_sample(start);
            }
            on_sample(end);
            return;
        }

        let distance = distance_squared.sqrt();
        let sample_count = ((distance / sample_step).ceil() as usize).max(1);

        if include_start {
            on_sample(start);
        }

        for i in 1..=sample_count {
            let t = i as f64 / sample_count as f64;
            on_sample(DrawPoint::new(start.x + dx * t, start.y + dy * t));
        }
    }
}

impl Default for EraserStrokeProcessor {
    fn default() -> Self {
        Self::with_hit_tester_resolver(|_| None)
    }
}
