#![allow(dead_code)]

use std::collections::BTreeSet;
use std::fmt;

/// Document capabilities required by [`DomainState`].
///
/// The full model translation is incremental, so this trait lets `DomainState`
/// remain compile-friendly while still exposing meaningful domain operations.
pub trait DomainDocument: Clone + PartialEq {
    type Element: Clone;
    type GlobalElements: Clone + PartialEq;

    fn elements(&self) -> &[Self::Element];
    fn global_elements(&self) -> &Self::GlobalElements;
    fn elements_version(&self) -> i32;
    fn copy_with_elements(&self, elements: Vec<Self::Element>) -> Self;
}

/// Selection capabilities required by [`DomainState`].
///
/// This mirrors the selection behavior from the Dart model (`withAdded`,
/// `withRemoved`, `withToggled`, and so on).
pub trait DomainSelection: Clone + PartialEq {
    fn has_selection(&self) -> bool;
    fn is_single_select(&self) -> bool;
    fn is_multi_select(&self) -> bool;
    fn count(&self) -> usize;
    fn selected_ids(&self) -> &BTreeSet<String>;
    fn selection_version(&self) -> i32;

    fn with_selected_ids(&self, ids: BTreeSet<String>) -> Self;
    fn with_selected(&self, element_id: &str) -> Self;
    fn with_added(&self, element_id: &str) -> Self;
    fn with_removed(&self, element_id: &str) -> Self;
    fn with_toggled(&self, element_id: &str) -> Self;
    fn cleared(&self) -> Self;
}

/// Domain-layer state.
///
/// Includes all state that must be persisted and participates in undo/redo.
/// This is a pure data layer with no UI or interaction state.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct DomainState<D, S> {
    /// Document data (element list, versions, and so on).
    pub document: D,

    /// Selected element ID set.
    ///
    /// Only IDs are stored; transient overlay visuals are not.
    pub selection: S,
}

impl<D, S> DomainState<D, S> {
    pub const fn new(document: D, selection: S) -> Self {
        Self {
            document,
            selection,
        }
    }

    /// Factory method equivalent to `DomainState(document: ..., selection: default)`.
    pub fn from_document(document: D) -> Self
    where
        S: Default,
    {
        Self {
            document,
            selection: S::default(),
        }
    }

    /// Factory method equivalent to `DomainState.empty()`.
    pub fn empty() -> Self
    where
        D: Default,
        S: Default,
    {
        Self {
            document: D::default(),
            selection: S::default(),
        }
    }

    pub fn copy_with(&self, document: Option<D>, selection: Option<S>) -> Self
    where
        D: Clone,
        S: Clone,
    {
        Self {
            document: document.unwrap_or_else(|| self.document.clone()),
            selection: selection.unwrap_or_else(|| self.selection.clone()),
        }
    }
}

impl<D, S> DomainState<D, S>
where
    D: DomainDocument,
    S: DomainSelection,
{
    /// Convenient access to the element list.
    pub fn elements(&self) -> &[D::Element] {
        self.document.elements()
    }

    /// Convenient access to document-level global elements.
    pub fn global_elements(&self) -> &D::GlobalElements {
        self.document.global_elements()
    }

    /// Elements version.
    pub fn elements_version(&self) -> i32 {
        self.document.elements_version()
    }

    /// Whether any element is selected.
    pub fn has_selection(&self) -> bool {
        self.selection.has_selection()
    }

    /// Number of selected elements.
    pub fn selection_count(&self) -> usize {
        self.selection.count()
    }

    /// Whether this is a single selection.
    pub fn is_single_selection(&self) -> bool {
        self.selection.is_single_select()
    }

    /// Whether this is a multi-selection.
    pub fn is_multi_selection(&self) -> bool {
        self.selection.is_multi_select()
    }

    pub fn selected_ids(&self) -> &BTreeSet<String> {
        self.selection.selected_ids()
    }

    pub fn selection_version(&self) -> i32 {
        self.selection.selection_version()
    }

    /// Clear selection.
    pub fn clear_selection(&self) -> Self {
        if !self.selection.has_selection() {
            return self.clone();
        }

        self.copy_with(None, Some(self.selection.cleared()))
    }

    /// Set the selection.
    pub fn with_selection(&self, ids: BTreeSet<String>) -> Self {
        self.copy_with(None, Some(self.selection.with_selected_ids(ids)))
    }

    /// Select a single element.
    pub fn with_selected(&self, element_id: impl AsRef<str>) -> Self {
        self.copy_with(
            None,
            Some(self.selection.with_selected(element_id.as_ref())),
        )
    }

    /// Add an element to the selection.
    pub fn with_added(&self, element_id: impl AsRef<str>) -> Self {
        self.copy_with(None, Some(self.selection.with_added(element_id.as_ref())))
    }

    /// Remove an element from the selection.
    pub fn with_removed(&self, element_id: impl AsRef<str>) -> Self {
        self.copy_with(None, Some(self.selection.with_removed(element_id.as_ref())))
    }

    /// Toggle element selection.
    pub fn with_toggled(&self, element_id: impl AsRef<str>) -> Self {
        self.copy_with(None, Some(self.selection.with_toggled(element_id.as_ref())))
    }

    /// Update the element list.
    pub fn with_elements(&self, elements: Vec<D::Element>) -> Self {
        self.copy_with(Some(self.document.copy_with_elements(elements)), None)
    }
}

impl<D, S> fmt::Display for DomainState<D, S>
where
    D: DomainDocument,
    S: DomainSelection,
{
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "DomainState(elements: {}, selectedIds: {})",
            self.elements().len(),
            self.selection_count()
        )
    }
}
