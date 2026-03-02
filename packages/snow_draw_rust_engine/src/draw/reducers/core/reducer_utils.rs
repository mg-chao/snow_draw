#![allow(dead_code)]

use std::collections::BTreeSet;

use crate::draw::models::application_state::SelectionOverlayState;
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::element_state::ElementState;
use crate::draw::models::multi_select_lifecycle::MultiSelectLifecycle;
use crate::draw::utils::selection_calculator::SelectionCalculator;

/// Reads an element z-index.
///
/// This keeps `resolve_next_z_index` reusable across compatibility element
/// models while still supporting the primary `ElementState` type.
pub trait ZIndexReadable {
    fn z_index(&self) -> i64;
}

impl ZIndexReadable for ElementState {
    fn z_index(&self) -> i64 {
        self.z_index
    }
}

impl<T> ZIndexReadable for &T
where
    T: ZIndexReadable + ?Sized,
{
    fn z_index(&self) -> i64 {
        (*self).z_index()
    }
}

/// Resolves the next z-index for a newly appended element.
///
/// Uses the highest explicit z-index value in `elements` rather than list
/// length so newly appended elements remain top-most even when existing
/// z-indices are sparse.
pub fn resolve_next_z_index<T, I>(elements: I) -> i64
where
    T: ZIndexReadable,
    I: IntoIterator<Item = T>,
{
    let mut max_z_index = -1_i64;
    for element in elements {
        let z_index = element.z_index();
        if z_index > max_z_index {
            max_z_index = z_index;
        }
    }
    max_z_index + 1
}

/// Applies a selection change to `DrawState`.
///
/// Mirrors Dart `applySelectionChange`:
/// - No-op when selection is unchanged and overlay refresh is not forced.
/// - Recomputes selected elements and multi-select bounds.
/// - Uses `on_move_finished` when forcing refresh for unchanged multi-select.
/// - Uses `on_selection_changed` for all other selection transitions.
pub fn apply_selection_change(
    state: &DrawState,
    selected_ids: BTreeSet<String>,
    force_refresh_overlay: bool,
) -> DrawState {
    let selection_unchanged = set_equals(&state.domain.selection.selected_ids, &selected_ids);

    if selection_unchanged && !force_refresh_overlay {
        return state.clone();
    }

    let selected_elements = selected_ids
        .iter()
        .filter_map(|id| state.domain.document.get_element_by_id(id).cloned())
        .collect::<Vec<_>>();
    let overlay_bounds = if selected_elements.len() > 1 {
        SelectionCalculator::compute_selection_bounds_for_elements(selected_elements.as_slice())
    } else {
        None
    };

    let current_overlay = state.application.selection_overlay;
    let next_overlay = resolve_next_overlay(
        current_overlay,
        &selected_ids,
        selection_unchanged,
        force_refresh_overlay,
        overlay_bounds,
    );

    if selection_unchanged {
        if next_overlay == current_overlay {
            return state.clone();
        }

        let next_application = state.application.copy_with(None, None, Some(next_overlay));
        return state.copy_with(None, Some(next_application));
    }

    let next_application = if next_overlay == current_overlay {
        state.application.clone()
    } else {
        state.application.copy_with(None, None, Some(next_overlay))
    };

    let next_domain = state.domain.copy_with(
        None,
        Some(state.domain.selection.with_selected_ids(selected_ids)),
    );

    state.copy_with(Some(next_domain), Some(next_application))
}

fn resolve_next_overlay(
    current_overlay: SelectionOverlayState,
    selected_ids: &BTreeSet<String>,
    selection_unchanged: bool,
    force_refresh_overlay: bool,
    overlay_bounds: Option<crate::draw::types::draw_rect::DrawRect>,
) -> SelectionOverlayState {
    if selection_unchanged && force_refresh_overlay {
        if let Some(bounds) = overlay_bounds {
            return MultiSelectLifecycle::on_move_finished(current_overlay, bounds);
        }
    }

    MultiSelectLifecycle::on_selection_changed(selected_ids, overlay_bounds)
}

fn set_equals<T>(a: &BTreeSet<T>, b: &BTreeSet<T>) -> bool
where
    T: Ord,
{
    std::ptr::eq(a, b) || a == b
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;
    use std::sync::Arc;

    use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
    use crate::draw::models::draw_state::DrawState;
    use crate::draw::models::element_state::ElementState;
    use crate::draw::models::multi_select_lifecycle::MultiSelectOverlayState;
    use crate::draw::models::selection_overlay_state::SelectionOverlayState;
    use crate::draw::reducers::core::reducer_utils::{
        apply_selection_change, resolve_next_z_index, ZIndexReadable,
    };
    use crate::draw::types::draw_rect::DrawRect;

    #[derive(Clone, Copy)]
    struct FakeElement {
        z_index: i64,
    }

    impl ZIndexReadable for FakeElement {
        fn z_index(&self) -> i64 {
            self.z_index
        }
    }

    #[test]
    fn resolve_next_z_index_uses_max_value() {
        let elements = [
            FakeElement { z_index: 0 },
            FakeElement { z_index: 10 },
            FakeElement { z_index: 4 },
        ];
        assert_eq!(resolve_next_z_index(elements), 11);
    }

    #[test]
    fn resolve_next_z_index_empty_starts_at_zero() {
        let elements: [FakeElement; 0] = [];
        assert_eq!(resolve_next_z_index(elements), 0);
    }

    #[test]
    fn apply_selection_change_updates_selected_ids() {
        let state = DrawState::default();
        let selected_ids = ["a".to_string(), "b".to_string()]
            .into_iter()
            .collect::<BTreeSet<_>>();

        let next_state = apply_selection_change(&state, selected_ids.clone(), false);
        assert_eq!(next_state.domain.selection.selected_ids, selected_ids);
    }

    #[test]
    fn apply_selection_change_noop_when_unchanged_without_refresh() {
        let mut state = DrawState::default();
        state.domain.selection.selected_ids = ["a".to_string()].into_iter().collect();

        let next_state =
            apply_selection_change(&state, state.domain.selection.selected_ids.clone(), false);

        assert_eq!(next_state, state);
    }

    #[test]
    fn apply_selection_change_force_refresh_updates_multi_select_overlay_bounds() {
        let mut state = DrawState::default();
        state.domain.document.elements = vec![
            ElementState::new(
                "a",
                DrawRect::new(0.0, 0.0, 10.0, 10.0),
                0.0,
                1.0,
                0,
                Arc::new(RectangleData::default()),
            ),
            ElementState::new(
                "b",
                DrawRect::new(20.0, 20.0, 30.0, 30.0),
                0.0,
                1.0,
                1,
                Arc::new(RectangleData::default()),
            ),
        ];
        let selected_ids = ["a".to_string(), "b".to_string()]
            .into_iter()
            .collect::<BTreeSet<_>>();
        state.domain.selection.selected_ids = selected_ids.clone();

        let next_state = apply_selection_change(&state, selected_ids, true);
        let overlay = next_state
            .application
            .selection_overlay
            .multi_select_overlay
            .expect("multi-select overlay should be present");

        assert_eq!(overlay.bounds, DrawRect::new(0.0, 0.0, 30.0, 30.0));
        assert_eq!(overlay.rotation, 0.0);
    }

    #[test]
    fn apply_selection_change_single_selection_clears_multi_select_overlay() {
        let mut state = DrawState::default();
        state.application.selection_overlay = SelectionOverlayState {
            multi_select_overlay: Some(MultiSelectOverlayState::with_rotation(
                DrawRect::new(0.0, 0.0, 30.0, 30.0),
                0.5,
            )),
        };
        state.domain.selection.selected_ids =
            ["a".to_string(), "b".to_string()].into_iter().collect();

        let next_state =
            apply_selection_change(&state, ["a".to_string()].into_iter().collect(), false);

        assert_eq!(
            next_state.domain.selection.selected_ids,
            ["a".to_string()].into_iter().collect()
        );
        assert_eq!(
            next_state.application.selection_overlay,
            SelectionOverlayState::empty()
        );
    }
}
