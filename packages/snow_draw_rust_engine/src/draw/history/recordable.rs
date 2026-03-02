#![allow(dead_code)]

/// Marker trait for actions that should be recorded in history.
pub trait Recordable {
    /// Human-readable description for this history entry.
    fn history_description(&self) -> String;

    /// Category used by history policies and UI grouping.
    fn record_type(&self) -> HistoryRecordType;
}

/// Categories for recorded history entries.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum HistoryRecordType {
    Edit,
    Create,
    Delete,
    Style,
    Selection,
    #[default]
    Other,
}
