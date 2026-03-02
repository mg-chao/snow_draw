/// Reason for canceling an edit session.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum EditCancelReason {
    UserCancelled,
    ConflictingAction,
    NewEditStarted,
}

impl EditCancelReason {
    /// Returns the stable Dart-compatible identifier for this reason.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::UserCancelled => "userCancelled",
            Self::ConflictingAction => "conflictingAction",
            Self::NewEditStarted => "newEditStarted",
        }
    }
}
