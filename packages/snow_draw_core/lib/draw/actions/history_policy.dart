/// History recording policy for actions.
///
/// This is used by the store middleware layer to decide whether an action
/// should create an undo snapshot.
enum HistoryPolicy {
  /// Do not record history (default).
  none,

  /// Record a history snapshot.
  record,

  /// Skip middleware handling.
  ///
  /// Intended for history-control actions themselves (undo/redo/clear).
  skip,
}

/// Mixin that allows actions to declare history behavior.
mixin HistoryPolicyProvider {
  /// History policy for this action.
  HistoryPolicy get historyPolicy;

  /// Whether this action needs a special "pre-action" snapshot.
  ///
  /// Most actions can snapshot the current state directly. Some actions (e.g.
  /// finishing element creation) need a snapshot that excludes transient state.
  bool get requiresPreActionSnapshot => false;
}
