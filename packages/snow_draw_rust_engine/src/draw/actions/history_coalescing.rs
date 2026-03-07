#![allow(dead_code)]

use std::time::Duration;

/// Coalescing hint for high-frequency actions that should collapse history.
///
/// Adjacent actions with the same key dispatched inside `window` can be merged
/// into a single history record.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct HistoryCoalescing {
    /// Stable group key used to match adjacent actions.
    pub key: String,
    /// Maximum time gap allowed between adjacent actions in this group.
    pub window: Duration,
}

impl HistoryCoalescing {
    /// Default coalescing window (220ms), matching Dart defaults.
    pub const DEFAULT_WINDOW: Duration = Duration::from_millis(220);

    pub fn new(key: impl Into<String>) -> Self {
        Self::with_window(key, Self::DEFAULT_WINDOW)
    }

    pub fn with_window(key: impl Into<String>, window: Duration) -> Self {
        let key = key.into();
        assert!(!key.is_empty(), "key must not be empty");

        Self { key, window }
    }
}

/// Optional interface for actions that expose history coalescing hints.
pub trait HistoryCoalescingProvider {
    /// Returns coalescing metadata, or `None` to disable coalescing.
    fn history_coalescing(&self) -> Option<&HistoryCoalescing> {
        None
    }
}
