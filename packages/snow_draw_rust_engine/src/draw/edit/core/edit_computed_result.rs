#![allow(dead_code)]

use std::collections::HashMap;

use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_rect::DrawRect;

/// Shared geometry result for edit preview and commit.
///
/// This mirrors the Dart `EditComputedResult` value object.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct EditComputedResult {
    /// Updated elements keyed by element id.
    pub updated_elements: HashMap<String, ElementState>,
    /// Overlay bounds for multi-select edit previews.
    pub multi_select_bounds: Option<DrawRect>,
    /// Overlay rotation (radians) for multi-select edit previews.
    pub multi_select_rotation: Option<f64>,
}

impl EditComputedResult {
    pub fn new(
        updated_elements: HashMap<String, ElementState>,
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
