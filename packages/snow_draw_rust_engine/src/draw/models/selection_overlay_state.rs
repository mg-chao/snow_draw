#![allow(dead_code)]

use crate::draw::models::multi_select_lifecycle::MultiSelectOverlayState;
use std::fmt;

/// Application-layer selection overlay state.
///
/// This holds transient UI-only overlay data and does not participate in
/// undo/redo or serialization.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct SelectionOverlayState {
    pub multi_select_overlay: Option<MultiSelectOverlayState>,
}

impl SelectionOverlayState {
    /// Canonical empty overlay state.
    pub const EMPTY: Self = Self {
        multi_select_overlay: None,
    };

    /// Returns the canonical empty state.
    pub const fn empty() -> Self {
        Self::EMPTY
    }

    /// Returns true when a transient overlay is currently active.
    pub fn has_overlay(self) -> bool {
        self.multi_select_overlay.is_some()
    }

    /// Returns a copied state with optional replacement or reset semantics.
    ///
    /// When `reset_multi_select_overlay` is `true`, the overlay is cleared
    /// regardless of `multi_select_overlay`.
    pub fn copy_with(
        self,
        multi_select_overlay: Option<MultiSelectOverlayState>,
        reset_multi_select_overlay: bool,
    ) -> Self {
        Self {
            multi_select_overlay: if reset_multi_select_overlay {
                None
            } else {
                multi_select_overlay.or(self.multi_select_overlay)
            },
        }
    }
}

impl fmt::Display for SelectionOverlayState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let overlay = self
            .multi_select_overlay
            .map(|value| value.to_string())
            .unwrap_or_else(|| "null".to_string());
        write!(f, "SelectionOverlayState(multiSelectOverlay: {overlay})")
    }
}
