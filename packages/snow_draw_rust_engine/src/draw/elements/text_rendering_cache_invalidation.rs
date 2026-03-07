#![allow(dead_code)]

use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

/// Signature for backend-provided text rendering cache invalidation hooks.
pub type TextRenderingCacheInvalidator = Arc<dyn Fn() + Send + Sync + 'static>;

/// Listener notified whenever the cache revision changes.
pub type TextRenderingCacheRevisionListener = Arc<dyn Fn(u64) + Send + Sync + 'static>;

/// Callback used to clear backend text-layout measurement caches.
pub type TextLayoutCacheClearer = Arc<dyn Fn() + Send + Sync + 'static>;

/// Stable handle returned for registered callbacks.
pub type CallbackHandle = u64;

#[derive(Clone)]
struct CallbackEntry<T> {
    id: CallbackHandle,
    callback: T,
}

#[derive(Default)]
struct TextRenderingCacheInvalidationState {
    revision: u64,
    next_handle: CallbackHandle,
    invalidators: Vec<CallbackEntry<TextRenderingCacheInvalidator>>,
    revision_listeners: Vec<CallbackEntry<TextRenderingCacheRevisionListener>>,
    text_layout_cache_clearer: Option<TextLayoutCacheClearer>,
}

impl TextRenderingCacheInvalidationState {
    fn next_callback_handle(&mut self) -> CallbackHandle {
        let handle = self.next_handle;
        self.next_handle = self.next_handle.wrapping_add(1);
        handle
    }
}

fn shared_state() -> &'static Mutex<TextRenderingCacheInvalidationState> {
    static STATE: OnceLock<Mutex<TextRenderingCacheInvalidationState>> = OnceLock::new();
    STATE.get_or_init(|| Mutex::new(TextRenderingCacheInvalidationState::default()))
}

fn lock_state() -> MutexGuard<'static, TextRenderingCacheInvalidationState> {
    shared_state()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Returns the current text rendering cache revision.
///
/// Consumers can poll this value or subscribe with
/// [`add_text_rendering_cache_revision_listener`] to trigger repaints when
/// runtime font changes invalidate cached glyph shaping.
pub fn text_rendering_cache_revision() -> u64 {
    lock_state().revision
}

/// Registers a backend-specific [invalidator].
///
/// Duplicate callback references are ignored and return the existing handle.
pub fn register_text_rendering_cache_invalidator(
    invalidator: TextRenderingCacheInvalidator,
) -> CallbackHandle {
    let mut state = lock_state();

    if let Some(existing) = state
        .invalidators
        .iter()
        .find(|entry| Arc::ptr_eq(&entry.callback, &invalidator))
    {
        return existing.id;
    }

    let id = state.next_callback_handle();
    state.invalidators.push(CallbackEntry {
        id,
        callback: invalidator,
    });
    id
}

/// Unregisters a previously added [invalidator] by handle.
///
/// Returns `true` when a callback was removed.
pub fn unregister_text_rendering_cache_invalidator(invalidator_id: CallbackHandle) -> bool {
    let mut state = lock_state();
    let before = state.invalidators.len();
    state
        .invalidators
        .retain(|entry| entry.id != invalidator_id);
    before != state.invalidators.len()
}

/// Registers a listener that is notified when the revision increments.
///
/// Duplicate callback references are ignored and return the existing handle.
pub fn add_text_rendering_cache_revision_listener(
    listener: TextRenderingCacheRevisionListener,
) -> CallbackHandle {
    let mut state = lock_state();

    if let Some(existing) = state
        .revision_listeners
        .iter()
        .find(|entry| Arc::ptr_eq(&entry.callback, &listener))
    {
        return existing.id;
    }

    let id = state.next_callback_handle();
    state.revision_listeners.push(CallbackEntry {
        id,
        callback: listener,
    });
    id
}

/// Unregisters a revision listener by handle.
///
/// Returns `true` when a listener was removed.
pub fn remove_text_rendering_cache_revision_listener(listener_id: CallbackHandle) -> bool {
    let mut state = lock_state();
    let before = state.revision_listeners.len();
    state
        .revision_listeners
        .retain(|entry| entry.id != listener_id);
    before != state.revision_listeners.len()
}

/// Installs the text-layout cache clear hook used during invalidation.
///
/// Only one backend should own text layout caching at a time, so this keeps a
/// single optional callback.
pub fn set_text_layout_cache_clearer(clearer: Option<TextLayoutCacheClearer>) {
    lock_state().text_layout_cache_clearer = clearer;
}

/// Clears text-related rendering/layout caches and publishes a new revision.
///
/// Call this after runtime font registration completes to avoid stale fallback
/// glyph shaping from being reused.
pub fn invalidate_text_rendering_caches() {
    clear_text_layout_caches();

    let invalidators = {
        let state = lock_state();
        state
            .invalidators
            .iter()
            .map(|entry| Arc::clone(&entry.callback))
            .collect::<Vec<_>>()
    };

    for invalidator in invalidators {
        invalidator();
    }

    let (revision, listeners) = {
        let mut state = lock_state();
        state.revision = state.revision.wrapping_add(1);
        let listeners = state
            .revision_listeners
            .iter()
            .map(|entry| Arc::clone(&entry.callback))
            .collect::<Vec<_>>();
        (state.revision, listeners)
    };

    for listener in listeners {
        listener(revision);
    }
}

fn clear_text_layout_caches() {
    let clearer = { lock_state().text_layout_cache_clearer.clone() };
    if let Some(clearer) = clearer {
        clearer();
    }
}
