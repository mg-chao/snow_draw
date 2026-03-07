#![allow(dead_code)]

use std::collections::BTreeSet;
use std::fmt;

use crate::draw::models::camera_state::CameraState;
use crate::draw::models::interaction_state::InteractionState;

use super::edit_events::DrawEvent;

/// Marker trait for events that report state changes in the draw domain.
pub trait StateChangeEvent: DrawEvent {}

/// Emitted when document-level element state changes.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct DocumentChangedEvent {
    pub elements_version: i64,
    pub element_count: usize,
}

impl DocumentChangedEvent {
    pub fn new(elements_version: i64, element_count: usize) -> Self {
        Self {
            elements_version,
            element_count,
        }
    }
}

impl fmt::Display for DocumentChangedEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "DocumentChangedEvent(version: {}, count: {})",
            self.elements_version, self.element_count
        )
    }
}

impl DrawEvent for DocumentChangedEvent {}
impl StateChangeEvent for DocumentChangedEvent {}

/// Emitted when the current selection changes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SelectionChangedEvent {
    pub selected_ids: BTreeSet<String>,
    pub selection_version: i32,
}

impl SelectionChangedEvent {
    pub fn new<I, S>(selected_ids: I, selection_version: i32) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        Self {
            selected_ids: selected_ids.into_iter().map(Into::into).collect(),
            selection_version,
        }
    }

    pub fn selected_count(&self) -> usize {
        self.selected_ids.len()
    }
}

impl fmt::Display for SelectionChangedEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "SelectionChangedEvent(version: {}, count: {})",
            self.selection_version,
            self.selected_ids.len()
        )
    }
}

impl DrawEvent for SelectionChangedEvent {}
impl StateChangeEvent for SelectionChangedEvent {}

/// Emitted when camera/view state changes.
#[derive(Clone, Debug, PartialEq)]
pub struct ViewChangedEvent {
    pub camera: CameraState,
}

impl ViewChangedEvent {
    pub fn new(camera: CameraState) -> Self {
        Self { camera }
    }
}

impl fmt::Display for ViewChangedEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "ViewChangedEvent(camera: {})", self.camera)
    }
}

impl DrawEvent for ViewChangedEvent {}
impl StateChangeEvent for ViewChangedEvent {}

/// Emitted when interaction mode/state changes.
#[derive(Clone, Debug, PartialEq)]
pub struct InteractionChangedEvent {
    pub interaction: InteractionState,
}

impl InteractionChangedEvent {
    pub fn new(interaction: InteractionState) -> Self {
        Self { interaction }
    }
}

impl fmt::Display for InteractionChangedEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "InteractionChangedEvent(interaction: {:?})",
            self.interaction
        )
    }
}

impl DrawEvent for InteractionChangedEvent {}
impl StateChangeEvent for InteractionChangedEvent {}

/// Emitted when undo/redo availability changes.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct HistoryAvailabilityChangedEvent {
    pub can_undo: bool,
    pub can_redo: bool,
}

impl HistoryAvailabilityChangedEvent {
    pub fn new(can_undo: bool, can_redo: bool) -> Self {
        Self { can_undo, can_redo }
    }
}

impl fmt::Display for HistoryAvailabilityChangedEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "HistoryAvailabilityChangedEvent(canUndo: {}, canRedo: {})",
            self.can_undo, self.can_redo
        )
    }
}

impl DrawEvent for HistoryAvailabilityChangedEvent {}
impl StateChangeEvent for HistoryAvailabilityChangedEvent {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn document_changed_event_display_matches_dart_shape() {
        let event = DocumentChangedEvent::new(7, 3);
        assert_eq!(
            event.to_string(),
            "DocumentChangedEvent(version: 7, count: 3)"
        );
    }

    #[test]
    fn selection_changed_event_clones_ids_into_set() {
        let ids = ["a", "b", "a"];
        let event = SelectionChangedEvent::new(ids, 12);
        assert_eq!(event.selection_version, 12);
        assert_eq!(event.selected_count(), 2);
        assert_eq!(
            event.to_string(),
            "SelectionChangedEvent(version: 12, count: 2)"
        );
    }

    #[test]
    fn history_availability_event_display_matches_dart_shape() {
        let event = HistoryAvailabilityChangedEvent::new(true, false);
        assert_eq!(
            event.to_string(),
            "HistoryAvailabilityChangedEvent(canUndo: true, canRedo: false)"
        );
    }
}
