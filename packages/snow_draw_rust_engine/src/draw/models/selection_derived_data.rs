#![allow(dead_code)]

use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Immutable snapshot of selection-derived data.
///
/// This is computed from a specific draw-state snapshot (and optionally an edit
/// preview/session) and reused by callers during a single frame or event
/// handler.
#[derive(Clone, Debug, PartialEq)]
pub struct SelectionDerivedData {
    /// Selected elements captured for this snapshot.
    pub selected_elements: Vec<ElementState>,

    /// Axis-aligned selection bounds in world coordinates.
    pub selection_bounds: Option<DrawRect>,

    /// Overlay bounds used for rendering handles and overlays.
    ///
    /// For multi-select, this stores unrotated bounds in the overlay's local
    /// frame. Callers may rotate this around [`Self::overlay_center`] by
    /// [`Self::overlay_rotation`].
    pub overlay_bounds: Option<DrawRect>,

    /// Overlay rotation in radians.
    ///
    /// `None` when rotation is zero or when selection is empty.
    pub overlay_rotation: Option<f64>,

    /// Overlay center in world coordinates.
    pub overlay_center: Option<DrawPoint>,

    /// Single-select rotation in radians.
    ///
    /// `None` when selection is not singular.
    pub selection_rotation: Option<f64>,

    /// Single-select center in world coordinates.
    ///
    /// `None` when selection is not singular.
    pub selection_center: Option<DrawPoint>,
}

impl SelectionDerivedData {
    /// Creates a snapshot with explicit fields.
    pub fn new(
        selected_elements: Vec<ElementState>,
        selection_bounds: Option<DrawRect>,
        overlay_bounds: Option<DrawRect>,
        overlay_rotation: Option<f64>,
        overlay_center: Option<DrawPoint>,
        selection_rotation: Option<f64>,
        selection_center: Option<DrawPoint>,
    ) -> Self {
        Self {
            selected_elements,
            selection_bounds,
            overlay_bounds,
            overlay_rotation,
            overlay_center,
            selection_rotation,
            selection_center,
        }
    }

    /// Equivalent to Dart's `SelectionDerivedData.empty`.
    pub fn empty() -> Self {
        Self::default()
    }

    /// Returns `true` when there is at least one selected element.
    pub fn has_selection(&self) -> bool {
        !self.selected_elements.is_empty()
    }

    /// Returns `true` when exactly one element is selected.
    pub fn is_single_select(&self) -> bool {
        self.selected_elements.len() == 1
    }

    /// Returns `true` when more than one element is selected.
    pub fn is_multi_select(&self) -> bool {
        self.selected_elements.len() > 1
    }
}

impl Default for SelectionDerivedData {
    fn default() -> Self {
        Self {
            selected_elements: Vec::new(),
            selection_bounds: None,
            overlay_bounds: None,
            overlay_rotation: None,
            overlay_center: None,
            selection_rotation: None,
            selection_center: None,
        }
    }
}
