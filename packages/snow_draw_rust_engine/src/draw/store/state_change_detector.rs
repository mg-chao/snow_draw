#![allow(dead_code)]

use std::collections::BTreeSet;
use std::ptr;

use crate::draw::models::draw_state::DrawState;

use super::draw_store_interface::DrawStateChange;

/// Returns tracked [`DrawStateChange`] values between two states.
///
/// This centralizes change-detection semantics so listener filtering and event
/// emission stay consistent.
pub fn compute_draw_state_changes(
    previous: &DrawState,
    next: &DrawState,
) -> BTreeSet<DrawStateChange> {
    let mut changes = BTreeSet::new();

    if has_document_state_changed(previous, next) {
        changes.insert(DrawStateChange::Document);
    }
    if has_selection_state_changed(previous, next) {
        changes.insert(DrawStateChange::Selection);
    }
    if has_view_state_changed(previous, next) {
        changes.insert(DrawStateChange::View);
    }
    if has_interaction_state_changed(previous, next) {
        changes.insert(DrawStateChange::Interaction);
    }

    changes
}

/// Returns whether persisted document content changed.
///
/// Dart change detection keys off `elementsVersion` when available.
pub fn has_document_state_changed(previous: &DrawState, next: &DrawState) -> bool {
    let previous_document = &previous.domain.document;
    let next_document = &next.domain.document;

    !ptr::eq(previous_document, next_document)
        && DocumentChangeComparable::has_document_change(previous_document, next_document)
}

/// Returns whether persisted selection changed.
///
/// Dart change detection keys off `selectionVersion` when available.
pub fn has_selection_state_changed(previous: &DrawState, next: &DrawState) -> bool {
    let previous_selection = &previous.domain.selection;
    let next_selection = &next.domain.selection;

    !ptr::eq(previous_selection, next_selection)
        && SelectionChangeComparable::has_selection_change(previous_selection, next_selection)
}

/// Returns whether view state changed.
pub fn has_view_state_changed(previous: &DrawState, next: &DrawState) -> bool {
    let previous_view = &previous.application.view;
    let next_view = &next.application.view;

    !ptr::eq(previous_view, next_view) && previous_view != next_view
}

/// Returns whether interaction state changed.
pub fn has_interaction_state_changed(previous: &DrawState, next: &DrawState) -> bool {
    let previous_interaction = &previous.application.interaction;
    let next_interaction = &next.application.interaction;

    !ptr::eq(previous_interaction, next_interaction) && previous_interaction != next_interaction
}

/// Domain-specific document change detector.
///
/// When a version counter exists we compare versions, otherwise we fall back to
/// structural inequality.
trait DocumentChangeComparable {
    fn has_document_change(&self, other: &Self) -> bool;
}

impl DocumentChangeComparable for crate::draw::models::draw_state::DomainDocumentState {
    fn has_document_change(&self, other: &Self) -> bool {
        self.elements_version != other.elements_version
    }
}

impl DocumentChangeComparable for crate::draw::models::document_state::DocumentState {
    fn has_document_change(&self, other: &Self) -> bool {
        self.elements_version != other.elements_version
    }
}

/// Domain-specific selection change detector.
///
/// When a version counter exists we compare versions, otherwise we fall back to
/// structural inequality.
trait SelectionChangeComparable {
    fn has_selection_change(&self, other: &Self) -> bool;
}

impl SelectionChangeComparable for crate::draw::models::draw_state::DomainSelectionState {
    fn has_selection_change(&self, other: &Self) -> bool {
        self.selection_version != other.selection_version
    }
}
