#![allow(dead_code)]

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::time::SystemTime;

/// Categories for recorded history entries.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum HistoryRecordType {
    Edit,
    Create,
    Delete,
    Style,
    Selection,
    Other,
}

/// Metadata for history entries.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct HistoryMetadata {
    description: String,
    record_type: HistoryRecordType,
    affected_element_ids: HashSet<String>,
    timestamp: SystemTime,
    extra: Option<HashMap<String, Value>>,
}

impl HistoryMetadata {
    pub fn new(
        description: impl Into<String>,
        record_type: HistoryRecordType,
        affected_element_ids: HashSet<String>,
        timestamp: Option<SystemTime>,
        extra: Option<HashMap<String, Value>>,
    ) -> Self {
        Self {
            description: description.into(),
            record_type,
            affected_element_ids,
            timestamp: timestamp.unwrap_or_else(SystemTime::now),
            extra,
        }
    }

    pub fn for_edit(
        operation_type: impl AsRef<str>,
        element_ids: HashSet<String>,
        extra: Option<HashMap<String, Value>>,
    ) -> Self {
        let element_count = element_ids.len();
        let suffix = if element_count == 1 { "" } else { "s" };
        let description = format!(
            "{} {} element{}",
            operation_type.as_ref(),
            element_count,
            suffix
        );

        Self::new(
            description,
            HistoryRecordType::Edit,
            element_ids,
            None,
            extra,
        )
    }

    pub fn for_move(element_ids: HashSet<String>) -> Self {
        Self::for_edit("Move", element_ids, None)
    }

    pub fn for_resize(element_ids: HashSet<String>) -> Self {
        Self::for_edit("Resize", element_ids, None)
    }

    pub fn for_rotate(element_ids: HashSet<String>) -> Self {
        Self::for_edit("Rotate", element_ids, None)
    }

    pub fn description(&self) -> &str {
        &self.description
    }

    pub const fn record_type(&self) -> HistoryRecordType {
        self.record_type
    }

    pub fn affected_element_ids(&self) -> &HashSet<String> {
        &self.affected_element_ids
    }

    pub fn timestamp(&self) -> &SystemTime {
        &self.timestamp
    }

    pub fn extra(&self) -> Option<&HashMap<String, Value>> {
        self.extra.as_ref()
    }
}

impl fmt::Display for HistoryMetadata {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "HistoryMetadata({}, {} elements)",
            self.description,
            self.affected_element_ids.len()
        )
    }
}
