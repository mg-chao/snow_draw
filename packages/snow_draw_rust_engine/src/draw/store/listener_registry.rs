#![allow(dead_code)]

use std::any::Any;
use std::backtrace::Backtrace;
use std::collections::BTreeSet;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Arc, Mutex, MutexGuard};

use indexmap::IndexMap;

use crate::draw::core::callbacks::VoidCallback;
use crate::draw::models::draw_state::DrawState;

use super::draw_store_interface::{DrawStateChange, StateChangeListener};

type ListenerKey = usize;

/// Callback invoked when a listener panics during notification.
pub type ListenerErrorHandler = Arc<dyn Fn(&(dyn Any + Send), &Backtrace) + Send + Sync + 'static>;

/// Listener registry.
///
/// Manages registration, unregistration, and notification of state listeners.
/// Supports fine-grained change-type filtering to notify only relevant
/// listeners.
#[derive(Clone, Default)]
pub struct ListenerRegistry {
    inner: Arc<Mutex<ListenerRegistryInner>>,
}

#[derive(Default)]
struct ListenerRegistryInner {
    on_error: Option<ListenerErrorHandler>,
    listeners: IndexMap<ListenerKey, ListenerEntry>,
    next_revision: u64,
}

/// Internal entry for one listener and its normalized change mask.
#[derive(Clone)]
struct ListenerEntry {
    listener: StateChangeListener<DrawState>,
    change_types: BTreeSet<DrawStateChange>,
    revision: u64,
}

impl ListenerEntry {
    fn matches(&self, state_changes: &BTreeSet<DrawStateChange>) -> bool {
        self.change_types
            .iter()
            .any(|change| state_changes.contains(change))
    }
}

impl ListenerRegistry {
    /// Creates an empty listener registry.
    pub fn new(on_error: Option<ListenerErrorHandler>) -> Self {
        Self {
            inner: Arc::new(Mutex::new(ListenerRegistryInner {
                on_error,
                listeners: IndexMap::new(),
                next_revision: 0,
            })),
        }
    }

    /// Registers a listener.
    ///
    /// `change_types = None` or an empty set listens to all tracked state
    /// changes.
    ///
    /// If the listener is already registered, its change mask is updated while
    /// preserving the original notification order.
    pub fn register(
        &self,
        listener: StateChangeListener<DrawState>,
        change_types: Option<BTreeSet<DrawStateChange>>,
    ) -> VoidCallback {
        let key = listener_key(&listener);
        let normalized_change_types = normalize_change_types(change_types);

        {
            let mut inner = self.lock_inner();
            let revision = inner.next_revision;
            inner.next_revision = inner.next_revision.wrapping_add(1);

            let entry = ListenerEntry {
                listener: Arc::clone(&listener),
                change_types: normalized_change_types,
                revision,
            };
            inner.listeners.insert(key, entry);
        }

        let registry = self.clone();
        Arc::new(move || {
            let _ = registry.unregister_by_key(key);
        })
    }

    /// Unregisters a listener.
    pub fn unregister(&self, listener: &StateChangeListener<DrawState>) -> bool {
        self.unregister_by_key(listener_key(listener))
    }

    /// Notifies all matching listeners in registration order.
    pub fn notify(&self, previous: &DrawState, next: &DrawState) {
        let entries_snapshot = {
            let inner = self.lock_inner();
            if inner.listeners.is_empty() {
                return;
            }
            inner.listeners.values().cloned().collect::<Vec<_>>()
        };

        let state_changes = compute_draw_state_changes(previous, next);
        if state_changes.is_empty() {
            return;
        }

        self.notify_entries(entries_snapshot, next, &state_changes);
    }

    /// Removes all listeners.
    pub fn clear(&self) {
        self.lock_inner().listeners.clear();
    }

    /// Number of registered listeners.
    pub fn count(&self) -> usize {
        self.lock_inner().listeners.len()
    }

    /// Whether there are no registered listeners.
    pub fn is_empty(&self) -> bool {
        self.count() == 0
    }

    /// Whether at least one listener is registered.
    pub fn is_not_empty(&self) -> bool {
        !self.is_empty()
    }

    fn lock_inner(&self) -> MutexGuard<'_, ListenerRegistryInner> {
        self.inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn unregister_by_key(&self, key: ListenerKey) -> bool {
        self.lock_inner().listeners.shift_remove(&key).is_some()
    }

    fn notify_entries(
        &self,
        entries: Vec<ListenerEntry>,
        next: &DrawState,
        state_changes: &BTreeSet<DrawStateChange>,
    ) {
        let on_error = self.lock_inner().on_error.clone();

        for entry in entries {
            if !self.is_current_entry(&entry) {
                continue;
            }
            if !entry.matches(state_changes) {
                continue;
            }

            if let Err(payload) = catch_unwind(AssertUnwindSafe(|| (entry.listener)(next))) {
                if let Some(handler) = on_error.as_ref() {
                    let backtrace = Backtrace::force_capture();
                    handler(payload.as_ref(), &backtrace);
                }
            }
        }
    }

    fn is_current_entry(&self, entry: &ListenerEntry) -> bool {
        let key = listener_key(&entry.listener);
        self.lock_inner()
            .listeners
            .get(&key)
            .map(|current| current.revision == entry.revision)
            .unwrap_or(false)
    }
}

fn listener_key(listener: &StateChangeListener<DrawState>) -> ListenerKey {
    Arc::as_ptr(listener) as *const () as usize
}

fn normalize_change_types(value: Option<BTreeSet<DrawStateChange>>) -> BTreeSet<DrawStateChange> {
    match value {
        Some(set) if !set.is_empty() => set,
        _ => all_draw_state_changes(),
    }
}

fn all_draw_state_changes() -> BTreeSet<DrawStateChange> {
    [
        DrawStateChange::Document,
        DrawStateChange::Selection,
        DrawStateChange::View,
        DrawStateChange::Interaction,
    ]
    .into_iter()
    .collect()
}

/// Best-effort local change detection used until `state_change_detector` is
/// fully translated.
fn compute_draw_state_changes(previous: &DrawState, next: &DrawState) -> BTreeSet<DrawStateChange> {
    let mut changes = BTreeSet::new();

    if previous.domain.document != next.domain.document {
        changes.insert(DrawStateChange::Document);
    }
    if previous.domain.selection != next.domain.selection {
        changes.insert(DrawStateChange::Selection);
    }
    if previous.application.view != next.application.view {
        changes.insert(DrawStateChange::View);
    }
    if previous.application.interaction != next.application.interaction {
        changes.insert(DrawStateChange::Interaction);
    }

    changes
}
