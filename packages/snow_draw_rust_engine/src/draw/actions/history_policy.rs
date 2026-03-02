#![allow(dead_code)]

/// History recording policy for actions.
///
/// This policy is consumed by store middleware to determine if an action
/// should create an undo snapshot.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum HistoryPolicy {
    /// Do not record history (default).
    #[default]
    None,
    /// Record a history snapshot.
    Record,
    /// Skip history middleware handling.
    ///
    /// Intended for history-control actions like undo/redo/clear.
    Skip,
}

/// Interface used by actions to declare history behavior.
pub trait HistoryPolicyProvider {
    /// Returns the history policy for the action.
    fn history_policy(&self) -> HistoryPolicy {
        HistoryPolicy::None
    }
}
