/// Reason for canceling an edit session.
enum EditCancelReason {
  /// User cancelled explicitly.
  userCancelled,

  /// Cancelled due to a conflicting action.
  conflictingAction,

  /// New edit operation started.
  newEditStarted,
}
