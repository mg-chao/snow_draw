#![allow(dead_code)]

pub use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Element snapshot used by element-specific hit testers.
///
/// This mirrors Dart by using the canonical draw-model element state.

/// Hit testing interface for a single element type.
///
/// Mirrors the Dart `ElementHitTester` abstraction while providing an idiomatic
/// Rust API without default arguments.
pub trait ElementHitTester: Send + Sync {
    /// Returns true when `position` hits `element` with zero tolerance.
    fn hit_test(&self, element: &ElementState, position: DrawPoint) -> bool {
        self.hit_test_with_tolerance(element, position, 0.0)
    }

    /// Returns true when `position` hits `element` with `tolerance`.
    fn hit_test_with_tolerance(
        &self,
        element: &ElementState,
        position: DrawPoint,
        tolerance: f64,
    ) -> bool;

    /// Returns the element bounds used for selection overlays.
    fn get_bounds(&self, element: &ElementState) -> DrawRect;
}
