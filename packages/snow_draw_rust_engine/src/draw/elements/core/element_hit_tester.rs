#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Element snapshot used by element-specific hit testers.
///
/// The canonical model translation (`draw/models/element_state.rs`) is still
/// in flight, so this local fallback keeps the hit-tester contract usable.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ElementState {
    pub id: String,
    pub rect: DrawRect,
}

impl ElementState {
    pub fn new(id: impl Into<String>, rect: DrawRect) -> Self {
        Self {
            id: id.into(),
            rect,
        }
    }
}

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
