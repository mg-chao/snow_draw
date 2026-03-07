#![allow(dead_code)]

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::time::{Duration, SystemTime};

use crate::draw::history::history_metadata::HistoryMetadata;
use crate::draw::models::draw_state::DrawState;
use crate::draw::services::log::log_service::{LogData, LogService, ModuleLogger};
use crate::draw::store::history_delta::HistoryDelta;
use crate::draw::store::snapshot::PersistentSnapshot;

const DEFAULT_MAX_HISTORY_LENGTH: usize = 50;
const DEFAULT_COALESCING_WINDOW: Duration = Duration::from_millis(220);

/// Coalescing hint for high-frequency actions that should collapse history.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HistoryCoalescing {
    key: String,
    window: Duration,
}

impl HistoryCoalescing {
    /// Creates a coalescing hint.
    ///
    /// The key must not be empty.
    pub fn new(key: impl Into<String>, window: Option<Duration>) -> Self {
        let key = key.into();
        assert!(!key.is_empty(), "key must not be empty");

        Self {
            key,
            window: window.unwrap_or(DEFAULT_COALESCING_WINDOW),
        }
    }

    /// Stable group key used to match adjacent actions for coalescing.
    pub fn key(&self) -> &str {
        &self.key
    }

    /// Maximum time gap allowed between adjacent actions in this group.
    pub fn window(&self) -> Duration {
        self.window
    }
}

/// Immutable snapshot entry used by [`HistoryManagerSnapshot`].
#[derive(Clone, Debug, PartialEq)]
pub struct HistorySnapshotEntry {
    pub id: u64,
    pub delta: HistoryDelta,
    pub recorded_at: SystemTime,
    pub metadata: Option<HistoryMetadata>,
    pub coalescing: Option<HistoryCoalescing>,
}

impl HistorySnapshotEntry {
    /// Returns a copy with selected fields replaced.
    pub fn copy_with(
        &self,
        delta: Option<HistoryDelta>,
        recorded_at: Option<SystemTime>,
        metadata: Option<Option<HistoryMetadata>>,
        coalescing: Option<Option<HistoryCoalescing>>,
    ) -> Self {
        Self {
            id: self.id,
            delta: delta.unwrap_or_else(|| self.delta.clone()),
            recorded_at: recorded_at.unwrap_or(self.recorded_at),
            metadata: metadata.unwrap_or_else(|| self.metadata.clone()),
            coalescing: coalescing.unwrap_or_else(|| self.coalescing.clone()),
        }
    }
}

/// Serializable-free history state snapshot.
#[derive(Clone, Debug, PartialEq)]
pub struct HistoryManagerSnapshot {
    pub entries: Vec<HistorySnapshotEntry>,
    pub cursor: isize,
    pub next_entry_id: u64,
}

impl HistoryManagerSnapshot {
    /// Creates a snapshot from explicit components.
    pub fn new(entries: Vec<HistorySnapshotEntry>, cursor: isize, next_entry_id: u64) -> Self {
        Self {
            entries,
            cursor,
            next_entry_id,
        }
    }

    /// Returns a copy with selected fields replaced.
    pub fn copy_with(
        &self,
        entries: Option<Vec<HistorySnapshotEntry>>,
        cursor: Option<isize>,
        next_entry_id: Option<u64>,
    ) -> Self {
        Self {
            entries: entries.unwrap_or_else(|| self.entries.clone()),
            cursor: cursor.unwrap_or(self.cursor),
            next_entry_id: next_entry_id.unwrap_or(self.next_entry_id),
        }
    }
}

/// Manages undo/redo history as a linear sequence of deltas.
pub struct HistoryManager {
    pub max_history_length: usize,
    log: Option<ModuleLogger>,
    entries: Vec<HistorySnapshotEntry>,
    cursor: isize,
    next_entry_id: u64,
}

impl Default for HistoryManager {
    fn default() -> Self {
        Self::new(DEFAULT_MAX_HISTORY_LENGTH, None)
    }
}

impl HistoryManager {
    /// Creates a history manager with bounded undo depth.
    pub fn new(max_history_length: usize, log_service: Option<&LogService>) -> Self {
        assert!(
            max_history_length >= 1,
            "max_history_length must be greater than or equal to 1"
        );

        Self {
            max_history_length,
            log: log_service.map(LogService::history),
            entries: Vec::new(),
            cursor: -1,
            next_entry_id: 0,
        }
    }

    /// True when at least one undo entry exists.
    pub fn can_undo(&self) -> bool {
        self.cursor >= 0
    }

    /// True when at least one redo entry exists.
    pub fn can_redo(&self) -> bool {
        self.cursor < self.entries.len() as isize - 1
    }

    /// Number of currently available undo steps.
    pub fn undo_length(&self) -> usize {
        if self.cursor < 0 {
            0
        } else {
            self.cursor as usize + 1
        }
    }

    /// Number of currently available redo steps.
    pub fn redo_length(&self) -> usize {
        self.entries.len().saturating_sub(self.undo_length())
    }

    /// Descriptions for all undo entries from oldest to newest.
    pub fn undo_descriptions(&self) -> Vec<String> {
        if self.cursor < 0 {
            return Vec::new();
        }

        self.entries
            .iter()
            .take(self.cursor as usize + 1)
            .map(|entry| metadata_description(entry.metadata.as_ref()))
            .collect()
    }

    /// Descriptions for all redo entries from next to latest.
    pub fn redo_descriptions(&self) -> Vec<String> {
        self.entries
            .iter()
            .skip(self.cursor.saturating_add(1) as usize)
            .map(|entry| metadata_description(entry.metadata.as_ref()))
            .collect()
    }

    /// Records a new history entry from snapshots.
    pub fn record(
        &mut self,
        before: PersistentSnapshot,
        after: PersistentSnapshot,
        metadata: Option<HistoryMetadata>,
        coalescing: Option<HistoryCoalescing>,
        current_state: Option<&DrawState>,
        recorded_at: Option<SystemTime>,
    ) -> bool {
        let now = recorded_at.unwrap_or_else(SystemTime::now);

        if let (Some(coalescing_hint), Some(state)) = (coalescing.clone(), current_state) {
            if let Some(coalesced) = self.try_coalesce_current_record(
                after.clone(),
                metadata.clone(),
                coalescing_hint,
                state,
                now,
            ) {
                return coalesced;
            }
        }

        let delta = HistoryDelta::from_snapshots(&before, &after);
        if !delta.has_changes() {
            if let Some(log) = self.log.as_ref() {
                let mut data = LogData::new();
                data.insert(
                    "description".to_owned(),
                    metadata_description(metadata.as_ref()),
                );
                log.trace("History record skipped (no changes)", Some(&data));
            }
            return false;
        }

        self.drop_redo_entries();

        let entry = HistorySnapshotEntry {
            id: self.next_entry_id,
            delta,
            metadata,
            coalescing,
            recorded_at: now,
        };
        self.next_entry_id = self.next_entry_id.saturating_add(1);

        self.entries.push(entry.clone());
        self.cursor = self.entries.len() as isize - 1;

        if let Some(log) = self.log.as_ref() {
            let mut data = LogData::new();
            data.insert("entryId".to_owned(), entry.id.to_string());
            data.insert(
                "description".to_owned(),
                metadata_description(entry.metadata.as_ref()),
            );
            data.insert(
                "changedElements".to_owned(),
                (entry.delta.before_elements.len() + entry.delta.after_elements.len()).to_string(),
            );
            data.insert(
                "orderChanged".to_owned(),
                entry.delta.order_changed.to_string(),
            );
            data.insert(
                "selectionChanged".to_owned(),
                entry.delta.selection_changed().to_string(),
            );
            log.trace("History record", Some(&data));
        }

        self.prune_if_needed();
        true
    }

    fn try_coalesce_current_record(
        &mut self,
        after: PersistentSnapshot,
        metadata: Option<HistoryMetadata>,
        coalescing: HistoryCoalescing,
        current_state: &DrawState,
        recorded_at: SystemTime,
    ) -> Option<bool> {
        if !self.can_coalesce_current(&coalescing, recorded_at) {
            return None;
        }

        let current_index = self.cursor as usize;
        let current_entry = self.entries.get(current_index)?.clone();

        let parent_state =
            self.resolve_current_parent_state(current_state, &current_entry.delta)?;
        let merged_delta = self.build_coalesced_delta(&parent_state, &after);

        if !merged_delta.has_changes() {
            self.entries.remove(current_index);
            self.cursor -= 1;

            if let Some(log) = self.log.as_ref() {
                let mut data = LogData::new();
                data.insert("coalescingKey".to_owned(), coalescing.key().to_owned());
                log.trace("History coalesced and removed empty entry", Some(&data));
            }

            return Some(false);
        }

        self.entries[current_index] = current_entry.copy_with(
            Some(merged_delta),
            Some(recorded_at),
            Some(metadata),
            Some(Some(coalescing.clone())),
        );

        if let Some(log) = self.log.as_ref() {
            let mut data = LogData::new();
            data.insert("entryId".to_owned(), current_entry.id.to_string());
            data.insert("coalescingKey".to_owned(), coalescing.key().to_owned());
            data.insert(
                "description".to_owned(),
                metadata_description(self.entries[current_index].metadata.as_ref()),
            );
            log.trace("History coalesced into current entry", Some(&data));
        }

        Some(true)
    }

    fn build_coalesced_delta(
        &self,
        parent_state: &DrawState,
        after_snapshot: &PersistentSnapshot,
    ) -> HistoryDelta {
        let merged_before =
            self.snapshot_for_coalesced_state(parent_state, after_snapshot.include_selection);
        HistoryDelta::from_snapshots(&merged_before, after_snapshot)
    }

    fn snapshot_for_coalesced_state(
        &self,
        state: &DrawState,
        include_selection: bool,
    ) -> PersistentSnapshot {
        PersistentSnapshot::from_state(state, include_selection)
    }

    fn can_coalesce_current(
        &self,
        coalescing: &HistoryCoalescing,
        recorded_at: SystemTime,
    ) -> bool {
        if self.entries.is_empty() || self.cursor != self.entries.len() as isize - 1 {
            return false;
        }

        let current_index = self.cursor as usize;
        let Some(active) = self.entries[current_index].coalescing.as_ref() else {
            return false;
        };

        if active.key() != coalescing.key() {
            return false;
        }

        let Some(expires_at) = self.entries[current_index]
            .recorded_at
            .checked_add(coalescing.window())
        else {
            return true;
        };

        recorded_at <= expires_at
    }

    fn resolve_current_parent_state(
        &self,
        current_state: &DrawState,
        current_delta: &HistoryDelta,
    ) -> Option<DrawState> {
        match catch_unwind(AssertUnwindSafe(|| {
            current_delta.apply_backward(current_state)
        })) {
            Ok(state) => Some(state),
            Err(_) => {
                if let Some(log) = self.log.as_ref() {
                    let mut data = LogData::new();
                    data.insert("cursor".to_owned(), self.cursor.to_string());
                    data.insert("error".to_owned(), "panic while applying delta".to_owned());
                    log.warning("History coalescing anchor resolution failed", Some(&data));
                }
                None
            }
        }
    }

    /// Undoes the latest history record.
    pub fn undo(&mut self, current_state: &DrawState) -> Option<DrawState> {
        if !self.can_undo() {
            if let Some(log) = self.log.as_ref() {
                let mut data = LogData::new();
                data.insert("reason".to_owned(), "empty".to_owned());
                log.trace("History undo skipped", Some(&data));
            }
            return None;
        }

        let current_index = self.cursor as usize;
        let entry = self.entries.get(current_index)?.clone();
        let restored_state = entry.delta.apply_backward(current_state);
        self.cursor -= 1;

        if let Some(log) = self.log.as_ref() {
            let mut data = LogData::new();
            data.insert("entryId".to_owned(), entry.id.to_string());
            log.trace("History undo", Some(&data));
        }

        Some(restored_state)
    }

    /// Redoes the next history record.
    pub fn redo(&mut self, current_state: &DrawState) -> Option<DrawState> {
        if !self.can_redo() {
            if let Some(log) = self.log.as_ref() {
                let mut data = LogData::new();
                data.insert("reason".to_owned(), "empty".to_owned());
                log.trace("History redo skipped", Some(&data));
            }
            return None;
        }

        let target_index = self.cursor + 1;
        let entry = self.entries.get(target_index as usize)?.clone();
        let restored_state = entry.delta.apply_forward(current_state);
        self.cursor = target_index;

        if let Some(log) = self.log.as_ref() {
            let mut data = LogData::new();
            data.insert("entryId".to_owned(), entry.id.to_string());
            log.trace("History redo", Some(&data));
        }

        Some(restored_state)
    }

    /// Removes all undo/redo entries.
    pub fn clear(&mut self) {
        if let Some(log) = self.log.as_ref() {
            let mut data = LogData::new();
            data.insert("undoLength".to_owned(), self.undo_length().to_string());
            data.insert("redoLength".to_owned(), self.redo_length().to_string());
            log.trace("History cleared", Some(&data));
        }

        self.entries.clear();
        self.cursor = -1;
        self.next_entry_id = 0;
    }

    /// Captures the manager state for transport or temporary storage.
    pub fn snapshot(&self) -> HistoryManagerSnapshot {
        HistoryManagerSnapshot::new(self.entries.clone(), self.cursor, self.next_entry_id)
    }

    /// Restores manager state from a previous snapshot.
    pub fn restore(&mut self, snapshot: HistoryManagerSnapshot) {
        self.entries = snapshot.entries;
        self.cursor = clamp_cursor(snapshot.cursor, self.entries.len());
        self.next_entry_id = resolve_next_entry_id(
            snapshot.next_entry_id,
            next_entry_id_from_entries(&self.entries),
        );
    }

    fn drop_redo_entries(&mut self) {
        if !self.can_redo() {
            return;
        }

        let remove_start = self.cursor.saturating_add(1) as usize;
        let removed_count = self.entries.len().saturating_sub(remove_start);
        self.entries.drain(remove_start..);

        if let Some(log) = self.log.as_ref() {
            let mut data = LogData::new();
            data.insert("removedCount".to_owned(), removed_count.to_string());
            log.trace("History redo entries discarded", Some(&data));
        }
    }

    fn prune_if_needed(&mut self) {
        let overflow = self.entries.len().saturating_sub(self.max_history_length);
        if overflow == 0 {
            return;
        }

        self.entries.drain(0..overflow);
        self.cursor -= overflow as isize;
        if self.cursor < -1 {
            self.cursor = -1;
        }

        if let Some(log) = self.log.as_ref() {
            let mut data = LogData::new();
            data.insert("overflow".to_owned(), overflow.to_string());
            data.insert(
                "maxHistoryLength".to_owned(),
                self.max_history_length.to_string(),
            );
            log.debug("History pruned", Some(&data));
        }
    }
}

fn metadata_description(metadata: Option<&HistoryMetadata>) -> String {
    metadata
        .map(|value| value.description().to_owned())
        .unwrap_or_default()
}

fn resolve_next_entry_id(requested_next_entry_id: u64, min_next_entry_id: u64) -> u64 {
    requested_next_entry_id.max(min_next_entry_id)
}

fn next_entry_id_from_entries(entries: &[HistorySnapshotEntry]) -> u64 {
    entries
        .iter()
        .map(|entry| entry.id)
        .max()
        .map_or(0, |max_id| max_id.saturating_add(1))
}

fn clamp_cursor(cursor: isize, entry_count: usize) -> isize {
    if entry_count == 0 {
        return -1;
    }
    if cursor < -1 {
        return -1;
    }
    if cursor >= entry_count as isize {
        return entry_count as isize - 1;
    }
    cursor
}
