#![allow(dead_code)]

use crate::draw::models::application_state::SelectionOverlayState as AppSelectionOverlayState;
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::element_state::ElementState;
use crate::draw::models::selection_derived_data::SelectionDerivedData;
use crate::draw::models::selection_geometry::SelectionGeometry;
use crate::draw::models::selection_overlay_state::SelectionOverlayState;
use crate::draw::types::draw_rect::DrawRect;

/// Pure (stateless) computer for selection-derived data.
pub struct SelectionDataComputer;

impl SelectionDataComputer {
    /// Computes a full [`SelectionDerivedData`] snapshot for a specific state.
    ///
    pub fn compute(state: &DrawState) -> SelectionDerivedData {
        let Some(selected_elements) = Self::resolve_selected_elements(state) else {
            return SelectionDerivedData::empty();
        };

        let selection_overlay =
            Self::resolve_selection_overlay(&state.application.selection_overlay);
        Self::compute_from_selected_elements(selected_elements, selection_overlay)
    }

    /// Computes selection-derived data from explicit selected elements.
    ///
    /// This mirrors the Dart `SelectionDataComputer.compute` logic and is
    /// usable by callers that already resolved selected elements in a richer
    /// state model.
    pub fn compute_from_selected_elements(
        selected_elements: Vec<ElementState>,
        selection_overlay: SelectionOverlayState,
    ) -> SelectionDerivedData {
        if selected_elements.is_empty() {
            return SelectionDerivedData::empty();
        }

        let selection_bounds = Self::compute_selection_bounds_for_elements(&selected_elements)
            .expect("selection bounds should exist for non-empty selected elements");

        let geometry = Self::resolve_selection_geometry(
            &selected_elements,
            selection_overlay,
            Some(selection_bounds),
            None,
            None,
        );

        let (selection_rotation, selection_center) = if selected_elements.len() == 1 {
            let single = &selected_elements[0];
            (Some(single.rotation), Some(single.center()))
        } else {
            (None, None)
        };

        SelectionDerivedData::new(
            selected_elements,
            Some(selection_bounds),
            geometry.bounds,
            geometry.rotation,
            geometry.center,
            selection_rotation,
            selection_center,
        )
    }

    fn resolve_selected_elements(state: &DrawState) -> Option<Vec<ElementState>> {
        Some(
            state
                .domain
                .selection
                .selected_ids
                .iter()
                .filter_map(|id| state.domain.document.get_element_by_id(id).cloned())
                .collect(),
        )
    }

    fn resolve_selection_overlay(
        selection_overlay: &AppSelectionOverlayState,
    ) -> SelectionOverlayState {
        *selection_overlay
    }

    fn resolve_selection_geometry(
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
                Self::normalize_rotation(element.rotation),
                true,
                false,
            );
        }

        let overlay = selection_overlay.multi_select_overlay;
        let bounds = overlay_bounds_override
            .or_else(|| overlay.map(|value| value.bounds))
            .or(selection_bounds)
            .or_else(|| Self::compute_selection_bounds_for_elements(selected_elements))
            .expect("multi-select geometry requires bounds");

        let rotation = overlay_rotation_override
            .or_else(|| overlay.map(|value| value.rotation))
            .unwrap_or(0.0);

        SelectionGeometry::new(
            Some(bounds),
            Some(bounds.center()),
            Self::normalize_rotation(rotation),
            true,
            true,
        )
    }

    fn compute_selection_bounds_for_elements(selected: &[ElementState]) -> Option<DrawRect> {
        if selected.is_empty() {
            return None;
        }

        if selected.len() == 1 {
            return Some(selected[0].rect);
        }

        let mut bounds = Self::compute_element_world_aabb(&selected[0]);
        for element in &selected[1..] {
            bounds = Self::merge_bounds(bounds, Self::compute_element_world_aabb(element));
        }

        Some(bounds)
    }

    fn compute_element_world_aabb(element: &ElementState) -> DrawRect {
        let rect = element.rect;
        if element.rotation == 0.0 {
            return rect;
        }

        let center = rect.center();
        let half_width = rect.width().abs() / 2.0;
        let half_height = rect.height().abs() / 2.0;
        let cos_theta = element.rotation.cos().abs();
        let sin_theta = element.rotation.sin().abs();
        let x_extent = half_width * cos_theta + half_height * sin_theta;
        let y_extent = half_width * sin_theta + half_height * cos_theta;

        DrawRect::new(
            center.x - x_extent,
            center.y - y_extent,
            center.x + x_extent,
            center.y + y_extent,
        )
    }

    fn merge_bounds(a: DrawRect, b: DrawRect) -> DrawRect {
        DrawRect::new(
            a.min_x.min(b.min_x),
            a.min_y.min(b.min_y),
            a.max_x.max(b.max_x),
            a.max_y.max(b.max_y),
        )
    }

    fn normalize_rotation(rotation: f64) -> Option<f64> {
        if rotation == 0.0 {
            None
        } else {
            Some(rotation)
        }
    }
}
