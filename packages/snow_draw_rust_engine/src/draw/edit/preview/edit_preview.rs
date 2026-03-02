#![allow(dead_code)]

use std::collections::{HashMap, HashSet};

use crate::draw::models::draw_state::DrawState;
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::EditContext;

/// Effective selection geometry used while an edit preview is active.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SelectionPreview {
    pub bounds: DrawRect,
    pub center: DrawPoint,
    pub rotation: Option<f64>,
}

impl SelectionPreview {
    pub const fn new(bounds: DrawRect, center: DrawPoint, rotation: Option<f64>) -> Self {
        Self {
            bounds,
            center,
            rotation,
        }
    }
}

/// Preview payload for rendering/hit-testing during edit interactions.
#[derive(Clone, Debug, PartialEq)]
pub struct EditPreview {
    pub preview_elements_by_id: HashMap<String, ElementState>,
    pub selection_preview: Option<SelectionPreview>,
}

impl EditPreview {
    pub fn new(
        preview_elements_by_id: HashMap<String, ElementState>,
        selection_preview: Option<SelectionPreview>,
    ) -> Self {
        Self {
            preview_elements_by_id,
            selection_preview,
        }
    }

    /// Equivalent to Dart's `EditPreview.none` singleton value.
    pub fn none() -> Self {
        Self {
            preview_elements_by_id: HashMap::new(),
            selection_preview: None,
        }
    }
}

impl Default for EditPreview {
    fn default() -> Self {
        Self::none()
    }
}

/// Builds the effective selection preview for the current edit session.
///
/// This mirrors Dart's `buildSelectionPreview`. The translated `DrawState`
/// model is still incremental and does not expose a document element map yet,
/// so this function currently resolves selected elements from
/// `preview_elements_by_id` first, then falls back to state-backed lookup when
/// available.
pub fn build_selection_preview(
    state: &DrawState,
    context: &EditContext,
    preview_elements_by_id: &HashMap<String, ElementState>,
    multi_select_bounds: Option<DrawRect>,
    multi_select_rotation: Option<f64>,
) -> Option<SelectionPreview> {
    let mut selected_elements = Vec::with_capacity(context.selected_ids_at_start.len());
    for id in &context.selected_ids_at_start {
        if let Some(preview) = preview_elements_by_id.get(id) {
            selected_elements.push(preview.clone());
            continue;
        }

        if let Some(base_element) = lookup_base_element(state, id) {
            selected_elements.push(base_element);
        }
    }

    build_selection_preview_from_selected_elements(
        context,
        selected_elements,
        multi_select_bounds,
        multi_select_rotation,
    )
}

/// Alternate entry point for callers that already have a base element map.
pub fn build_selection_preview_with_base_elements(
    context: &EditContext,
    preview_elements_by_id: &HashMap<String, ElementState>,
    base_elements_by_id: &HashMap<String, ElementState>,
    multi_select_bounds: Option<DrawRect>,
    multi_select_rotation: Option<f64>,
) -> Option<SelectionPreview> {
    let selected_elements = selected_elements_from_maps(
        &context.selected_ids_at_start,
        preview_elements_by_id,
        base_elements_by_id,
    );

    build_selection_preview_from_selected_elements(
        context,
        selected_elements,
        multi_select_bounds,
        multi_select_rotation,
    )
}

fn selected_elements_from_maps(
    selected_ids: &HashSet<String>,
    preview_elements_by_id: &HashMap<String, ElementState>,
    base_elements_by_id: &HashMap<String, ElementState>,
) -> Vec<ElementState> {
    let mut selected_elements = Vec::with_capacity(selected_ids.len());

    for id in selected_ids {
        if let Some(preview) = preview_elements_by_id.get(id) {
            selected_elements.push(preview.clone());
            continue;
        }

        if let Some(base) = base_elements_by_id.get(id) {
            selected_elements.push(base.clone());
        }
    }

    selected_elements
}

fn build_selection_preview_from_selected_elements(
    context: &EditContext,
    selected_elements: Vec<ElementState>,
    multi_select_bounds: Option<DrawRect>,
    multi_select_rotation: Option<f64>,
) -> Option<SelectionPreview> {
    if selected_elements.is_empty() {
        return None;
    }

    if selected_elements.len() == 1 {
        let element = &selected_elements[0];
        let bounds = element.rect;

        return Some(SelectionPreview::new(
            bounds,
            bounds.center(),
            normalize_rotation(Some(element.rotation)),
        ));
    }

    let bounds = multi_select_bounds.unwrap_or(context.start_bounds);
    Some(SelectionPreview::new(
        bounds,
        bounds.center(),
        normalize_rotation(multi_select_rotation),
    ))
}

fn normalize_rotation(rotation: Option<f64>) -> Option<f64> {
    let value = rotation.unwrap_or(0.0);
    if value == 0.0 {
        None
    } else {
        Some(value)
    }
}

fn lookup_base_element(_state: &DrawState, _id: &str) -> Option<ElementState> {
    _state.domain.document.get_element_by_id(_id).cloned()
}
