#![allow(dead_code)]

use std::collections::BTreeSet;
use std::fmt;

pub use crate::draw::models::selection_overlay_state::SelectionOverlayState;
use crate::draw::types::draw_rect::DrawRect;

/// Overlay state for a multi-selected element group.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MultiSelectOverlayState {
    /// Axis-aligned bounds in the overlay's unrotated local space.
    pub bounds: DrawRect,
    /// Overlay rotation in radians.
    pub rotation: f64,
}

impl MultiSelectOverlayState {
    /// Creates a multi-select overlay with zero rotation.
    pub const fn new(bounds: DrawRect) -> Self {
        Self {
            bounds,
            rotation: 0.0,
        }
    }

    /// Creates a multi-select overlay with explicit bounds and rotation.
    pub const fn with_rotation(bounds: DrawRect, rotation: f64) -> Self {
        Self { bounds, rotation }
    }

    /// Returns a copied state with selectively replaced fields.
    pub fn copy_with(self, bounds: Option<DrawRect>, rotation: Option<f64>) -> Self {
        Self {
            bounds: bounds.unwrap_or(self.bounds),
            rotation: rotation.unwrap_or(self.rotation),
        }
    }
}

impl fmt::Display for MultiSelectOverlayState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "MultiSelectOverlayState(bounds: {}, rotation: {})",
            self.bounds, self.rotation
        )
    }
}

/// Multi-select overlay lifecycle rules.
///
/// Centralizes updates for transient overlay state:
/// - overlay resets whenever the selection set changes;
/// - rotation updates after rotate finishes;
/// - bounds update after move/resize finishes.
#[derive(Clone, Copy, Debug, Default)]
pub struct MultiSelectLifecycle;

impl MultiSelectLifecycle {
    /// Applies selection changes and resets overlay state when needed.
    pub fn on_selection_changed(
        new_selected_ids: &BTreeSet<String>,
        new_overlay_bounds: Option<DrawRect>,
    ) -> SelectionOverlayState {
        if new_selected_ids.len() < 2 {
            return SelectionOverlayState::empty();
        }

        let Some(bounds) = new_overlay_bounds else {
            return SelectionOverlayState::empty();
        };

        SelectionOverlayState {
            multi_select_overlay: Some(MultiSelectOverlayState::new(bounds)),
        }
    }

    /// Applies rotate completion by updating both bounds and rotation.
    pub fn on_rotate_finished(
        current: SelectionOverlayState,
        new_rotation: f64,
        bounds: DrawRect,
    ) -> SelectionOverlayState {
        current.copy_with(
            Some(MultiSelectOverlayState::with_rotation(bounds, new_rotation)),
            false,
        )
    }

    /// Applies move completion by updating bounds and preserving rotation.
    pub fn on_move_finished(
        current: SelectionOverlayState,
        new_bounds: DrawRect,
    ) -> SelectionOverlayState {
        let rotation = current
            .multi_select_overlay
            .map(|overlay| overlay.rotation)
            .unwrap_or(0.0);

        current.copy_with(
            Some(MultiSelectOverlayState::with_rotation(new_bounds, rotation)),
            false,
        )
    }

    /// Applies resize completion by reusing move-completion behavior.
    pub fn on_resize_finished(
        current: SelectionOverlayState,
        new_bounds: DrawRect,
    ) -> SelectionOverlayState {
        Self::on_move_finished(current, new_bounds)
    }
}
