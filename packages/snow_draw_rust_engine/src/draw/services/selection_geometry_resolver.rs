#![allow(dead_code)]

use crate::draw::models::element_state::ElementState;
use crate::draw::models::selection_geometry::SelectionGeometry;
use crate::draw::models::selection_overlay_state::SelectionOverlayState;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::utils::selection_calculator::SelectionCalculator;

/// Resolves selection overlay geometry from a single computation path.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SelectionGeometryResolver;

impl SelectionGeometryResolver {
    /// Creates a stateless resolver.
    pub const fn new() -> Self {
        Self
    }

    /// Resolves the current selection geometry.
    pub fn resolve(
        selected_elements: &[ElementState],
        selection_overlay: SelectionOverlayState,
        selection_bounds: Option<DrawRect>,
        overlay_bounds_override: Option<DrawRect>,
        overlay_rotation_override: Option<f64>,
    ) -> SelectionGeometry {
        if selected_elements.is_empty() {
            return SelectionGeometry::none();
        }

        if selected_elements.len() == 1 {
            let element = &selected_elements[0];
            return SelectionGeometry::new(
                Some(element.rect),
                Some(element.center()),
                non_zero_rotation(element.rotation),
                true,
                false,
            );
        }

        let overlay = selection_overlay.multi_select_overlay;
        let bounds = overlay_bounds_override
            .or_else(|| overlay.map(|state| state.bounds))
            .or(selection_bounds)
            .or_else(|| compute_selection_bounds_for_elements(selected_elements))
            .expect("multi-selection bounds should resolve for non-empty selected_elements");

        let rotation = overlay_rotation_override
            .or_else(|| overlay.map(|state| state.rotation))
            .unwrap_or(0.0);

        SelectionGeometry::new(
            Some(bounds),
            Some(bounds.center()),
            non_zero_rotation(rotation),
            true,
            true,
        )
    }
}

fn non_zero_rotation(rotation: f64) -> Option<f64> {
    if rotation == 0.0 {
        None
    } else {
        Some(rotation)
    }
}

fn compute_selection_bounds_for_elements(selected_elements: &[ElementState]) -> Option<DrawRect> {
    SelectionCalculator::compute_selection_bounds_for_elements(selected_elements)
}

pub const SELECTION_GEOMETRY_RESOLVER: SelectionGeometryResolver = SelectionGeometryResolver::new();
