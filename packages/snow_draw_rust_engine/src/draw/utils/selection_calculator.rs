#![allow(dead_code)]

use crate::draw::types::draw_rect::DrawRect;

pub type DrawState = crate::draw::models::draw_state::DrawState;
pub type DomainState = crate::draw::models::draw_state::DomainState;
pub type SelectionState = crate::draw::models::selection_state::SelectionState;
pub type ElementState = crate::draw::models::element_state::ElementState;

/// Selection bounds and selected-element helpers.
pub struct SelectionCalculator;

impl SelectionCalculator {
    /// Resolves selected elements from current state.
    pub fn get_selected_elements(state: &DrawState) -> Vec<ElementState> {
        let document = &state.domain.document;
        state
            .domain
            .selection
            .selected_ids
            .iter()
            .filter_map(|id| document.get_element_by_id(id).cloned())
            .collect()
    }

    /// Computes selection bounds for a set of elements.
    ///
    /// For a single selection, this returns the element's own rectangle.
    /// For multiple elements, this returns the merged world AABB.
    pub fn compute_selection_bounds_for_elements(selected: &[ElementState]) -> Option<DrawRect> {
        if selected.is_empty() {
            return None;
        }

        if selected.len() == 1 {
            return Some(selected[0].rect);
        }

        let mut bounds = Self::compute_element_world_aabb(&selected[0]);
        for element in &selected[1..] {
            bounds = Self::expand_bounds(bounds, Self::compute_element_world_aabb(element));
        }
        Some(bounds)
    }

    /// Computes axis-aligned world bounds for a potentially rotated element.
    pub fn compute_element_world_aabb(element: &ElementState) -> DrawRect {
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

    fn expand_bounds(a: DrawRect, b: DrawRect) -> DrawRect {
        DrawRect::new(
            a.min_x.min(b.min_x),
            a.min_y.min(b.min_y),
            a.max_x.max(b.max_x),
            a.max_y.max(b.max_y),
        )
    }
}
