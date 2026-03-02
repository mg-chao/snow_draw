#![allow(dead_code)]

use crate::draw::models::domain_state::DomainSelection;
use crate::draw::types::draw_rect::DrawRect;
use std::collections::BTreeSet;
use std::fmt;

/// Overlay state for multi-selection handles.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MultiSelectOverlayState {
    /// Axis-aligned overlay bounds in the overlay's local (unrotated) frame.
    pub bounds: DrawRect,
    /// Overlay rotation in radians.
    pub rotation: f64,
}

impl MultiSelectOverlayState {
    /// Creates an overlay state with zero rotation.
    pub const fn new(bounds: DrawRect) -> Self {
        Self {
            bounds,
            rotation: 0.0,
        }
    }

    /// Creates an overlay state with explicit bounds and rotation.
    pub const fn with_rotation(bounds: DrawRect, rotation: f64) -> Self {
        Self { bounds, rotation }
    }

    /// Returns a copy with optional field replacements.
    pub fn copy_with(&self, bounds: Option<DrawRect>, rotation: Option<f64>) -> Self {
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

/// Immutable domain selection state.
///
/// Mirrors Dart behavior: selected ids are modeled as a set and
/// `selection_version` increments only when selection membership changes.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct SelectionState {
    pub selected_ids: BTreeSet<String>,
    pub selection_version: i32,
}

impl SelectionState {
    /// Creates a selection state from explicit fields.
    pub fn new(selected_ids: BTreeSet<String>, selection_version: i32) -> Self {
        Self {
            selected_ids: Self::freeze_selected_ids(selected_ids),
            selection_version,
        }
    }

    /// Returns the canonical empty selection state.
    pub fn empty() -> Self {
        Self::default()
    }

    /// Returns true when at least one element is selected.
    pub fn has_selection(&self) -> bool {
        !self.selected_ids.is_empty()
    }

    /// Returns true when more than one element is selected.
    pub fn is_multi_select(&self) -> bool {
        self.selected_ids.len() > 1
    }

    /// Returns true when exactly one element is selected.
    pub fn is_single_select(&self) -> bool {
        self.selected_ids.len() == 1
    }

    /// Number of selected element ids.
    pub fn count(&self) -> usize {
        self.selected_ids.len()
    }

    /// Returns a copy with optional field replacements.
    ///
    /// If `selected_ids` changes and `selection_version` is not provided, the
    /// version is incremented to preserve Dart semantics.
    pub fn copy_with(
        &self,
        selected_ids: Option<BTreeSet<String>>,
        selection_version: Option<i32>,
    ) -> Self {
        let next_selected_ids = selected_ids
            .map(Self::freeze_selected_ids)
            .unwrap_or_else(|| self.selected_ids.clone());
        let has_selection_changed = !Self::set_equals(&self.selected_ids, &next_selected_ids);

        let next_selection_version = selection_version.unwrap_or_else(|| {
            if has_selection_changed {
                self.selection_version.saturating_add(1)
            } else {
                self.selection_version
            }
        });

        if !has_selection_changed && next_selection_version == self.selection_version {
            return self.clone();
        }

        Self {
            selected_ids: next_selected_ids,
            selection_version: next_selection_version,
        }
    }

    /// Sets single selection.
    pub fn with_selected(&self, element_id: impl Into<String>) -> Self {
        let mut ids = BTreeSet::new();
        ids.insert(element_id.into());
        self.with_selected_ids_internal(ids)
    }

    /// Sets multi-selection.
    pub fn with_selected_ids(&self, ids: BTreeSet<String>) -> Self {
        self.with_selected_ids_internal(ids)
    }

    /// Adds an element to the selection.
    pub fn with_added(&self, element_id: impl AsRef<str>) -> Self {
        let element_id = element_id.as_ref();
        if self.selected_ids.contains(element_id) {
            return self.clone();
        }

        let mut ids = self.selected_ids.clone();
        ids.insert(element_id.to_owned());
        self.with_selected_ids_internal(ids)
    }

    /// Removes an element from the selection.
    pub fn with_removed(&self, element_id: impl AsRef<str>) -> Self {
        let element_id = element_id.as_ref();
        if !self.selected_ids.contains(element_id) {
            return self.clone();
        }

        let mut ids = self.selected_ids.clone();
        ids.remove(element_id);
        self.with_selected_ids_internal(ids)
    }

    /// Toggles an element's selection state.
    pub fn with_toggled(&self, element_id: impl AsRef<str>) -> Self {
        let element_id = element_id.as_ref();
        if self.selected_ids.contains(element_id) {
            self.with_removed(element_id)
        } else {
            self.with_added(element_id)
        }
    }

    /// Clears selection.
    pub fn cleared(&self) -> Self {
        if self.selected_ids.is_empty() {
            return self.clone();
        }

        Self {
            selected_ids: BTreeSet::new(),
            selection_version: self.selection_version.saturating_add(1),
        }
    }

    fn with_selected_ids_internal(&self, ids: BTreeSet<String>) -> Self {
        let frozen_ids = Self::freeze_selected_ids(ids);
        if Self::set_equals(&self.selected_ids, &frozen_ids) {
            return self.clone();
        }

        Self {
            selected_ids: frozen_ids,
            selection_version: self.selection_version.saturating_add(1),
        }
    }

    fn set_equals<T: Ord>(a: &BTreeSet<T>, b: &BTreeSet<T>) -> bool {
        a == b
    }

    fn freeze_selected_ids(ids: BTreeSet<String>) -> BTreeSet<String> {
        ids
    }
}

impl Default for SelectionState {
    fn default() -> Self {
        Self {
            selected_ids: BTreeSet::new(),
            selection_version: 0,
        }
    }
}

impl DomainSelection for SelectionState {
    fn has_selection(&self) -> bool {
        SelectionState::has_selection(self)
    }

    fn is_single_select(&self) -> bool {
        SelectionState::is_single_select(self)
    }

    fn is_multi_select(&self) -> bool {
        SelectionState::is_multi_select(self)
    }

    fn count(&self) -> usize {
        SelectionState::count(self)
    }

    fn selected_ids(&self) -> &BTreeSet<String> {
        &self.selected_ids
    }

    fn selection_version(&self) -> i32 {
        self.selection_version
    }

    fn with_selected_ids(&self, ids: BTreeSet<String>) -> Self {
        SelectionState::with_selected_ids(self, ids)
    }

    fn with_selected(&self, element_id: &str) -> Self {
        SelectionState::with_selected(self, element_id.to_owned())
    }

    fn with_added(&self, element_id: &str) -> Self {
        SelectionState::with_added(self, element_id)
    }

    fn with_removed(&self, element_id: &str) -> Self {
        SelectionState::with_removed(self, element_id)
    }

    fn with_toggled(&self, element_id: &str) -> Self {
        SelectionState::with_toggled(self, element_id)
    }

    fn cleared(&self) -> Self {
        SelectionState::cleared(self)
    }
}

impl fmt::Display for SelectionState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "SelectionState(ids: {}, version: {})",
            self.selected_ids.len(),
            self.selection_version
        )
    }
}
