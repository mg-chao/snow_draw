#![allow(dead_code)]

use std::collections::HashMap;

use crate::draw::models::document_state::{DocumentState, ElementState};
use crate::draw::types::draw_rect::DrawRect;

use super::super::rect_intersection::rects_intersect;

/// Resolves visible scene elements in z-order with preview replacements applied.
pub fn resolve_visible_element_scene(
    document: &DocumentState,
    viewport_rect: DrawRect,
    preview_elements_by_id: &HashMap<String, ElementState>,
    excluded_element_id: Option<&str>,
) -> Vec<ElementState> {
    let visible_elements = document.query_elements_in_rect_ordered(viewport_rect);

    if preview_elements_by_id.is_empty() && excluded_element_id.is_none() {
        return visible_elements;
    }

    let mut effective_by_id = HashMap::<String, ElementState>::new();

    for element in visible_elements {
        if excluded_element_id.is_some_and(|excluded| element.id == excluded) {
            continue;
        }

        if let Some(preview) = preview_elements_by_id.get(&element.id) {
            if is_in_viewport(preview, viewport_rect) {
                effective_by_id.insert(element.id.clone(), preview.clone());
            }
            continue;
        }

        effective_by_id.insert(element.id.clone(), element);
    }

    let mut added_preview_only = false;
    for preview in preview_elements_by_id.values() {
        if excluded_element_id.is_some_and(|excluded| preview.id == excluded)
            || effective_by_id.contains_key(&preview.id)
        {
            continue;
        }

        if !is_in_viewport(preview, viewport_rect) {
            continue;
        }

        effective_by_id.insert(preview.id.clone(), preview.clone());
        added_preview_only = true;
    }

    let mut effective_elements = effective_by_id.into_values().collect::<Vec<_>>();
    if !added_preview_only || effective_elements.len() < 2 {
        return effective_elements;
    }

    effective_elements.sort_by(|a, b| {
        let a_order = resolve_order_index(document, a);
        let b_order = resolve_order_index(document, b);
        a_order.cmp(&b_order).then_with(|| a.id.cmp(&b.id))
    });

    effective_elements
}

fn resolve_order_index(document: &DocumentState, element: &ElementState) -> i64 {
    document
        .get_order_index(&element.id)
        .and_then(|index| i64::try_from(index).ok())
        .unwrap_or(element.z_index)
}

fn is_in_viewport(element: &ElementState, viewport_rect: DrawRect) -> bool {
    rects_intersect(compute_element_world_aabb(element), viewport_rect)
}

fn compute_element_world_aabb(element: &ElementState) -> DrawRect {
    if element.rotation == 0.0 {
        return element.rect;
    }

    let center = element.rect.center();
    let half_width = element.rect.width().abs() / 2.0;
    let half_height = element.rect.height().abs() / 2.0;
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
