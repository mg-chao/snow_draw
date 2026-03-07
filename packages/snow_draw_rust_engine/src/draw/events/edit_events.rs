#![allow(dead_code)]

use std::fmt;

/// Base marker trait for draw-domain events.
pub trait DrawEvent: fmt::Debug + fmt::Display + Send + Sync + 'static {}

/// Base marker trait for edit-domain events.
pub trait EditEvent: DrawEvent {}

/// Session identifier for edit operations.
pub type EditSessionId = String;

/// Stable identifier for an edit operation.
pub type EditOperationId = &'static str;

/// Reason for cancelling an edit session.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum EditCancelReason {
    UserCancelled,
    ConflictingAction,
    NewEditStarted,
}

impl fmt::Display for EditCancelReason {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let value = match self {
            Self::UserCancelled => "userCancelled",
            Self::ConflictingAction => "conflictingAction",
            Self::NewEditStarted => "newEditStarted",
        };
        f.write_str(value)
    }
}

/// Shared interface for events bound to an edit session.
pub trait EditSessionEvent: EditEvent {
    fn session_id(&self) -> &EditSessionId;
    fn operation_id(&self) -> EditOperationId;
    fn event_name(&self) -> &'static str;
}

/// Edit session started event.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct EditSessionStartedEvent {
    pub session_id: EditSessionId,
    pub operation_id: EditOperationId,
}

impl EditSessionStartedEvent {
    pub const EVENT_NAME: &'static str = "EditSessionStarted";

    pub fn new(session_id: impl Into<EditSessionId>, operation_id: EditOperationId) -> Self {
        Self {
            session_id: session_id.into(),
            operation_id,
        }
    }
}

impl DrawEvent for EditSessionStartedEvent {}
impl EditEvent for EditSessionStartedEvent {}

impl EditSessionEvent for EditSessionStartedEvent {
    fn session_id(&self) -> &EditSessionId {
        &self.session_id
    }

    fn operation_id(&self) -> EditOperationId {
        self.operation_id
    }

    fn event_name(&self) -> &'static str {
        Self::EVENT_NAME
    }
}

impl fmt::Display for EditSessionStartedEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        format_session_event(f, self.event_name(), &self.session_id, self.operation_id)
    }
}

/// Edit session updated event.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct EditSessionUpdatedEvent {
    pub session_id: EditSessionId,
    pub operation_id: EditOperationId,
}

impl EditSessionUpdatedEvent {
    pub const EVENT_NAME: &'static str = "EditSessionUpdated";

    pub fn new(session_id: impl Into<EditSessionId>, operation_id: EditOperationId) -> Self {
        Self {
            session_id: session_id.into(),
            operation_id,
        }
    }
}

impl DrawEvent for EditSessionUpdatedEvent {}
impl EditEvent for EditSessionUpdatedEvent {}

impl EditSessionEvent for EditSessionUpdatedEvent {
    fn session_id(&self) -> &EditSessionId {
        &self.session_id
    }

    fn operation_id(&self) -> EditOperationId {
        self.operation_id
    }

    fn event_name(&self) -> &'static str {
        Self::EVENT_NAME
    }
}

impl fmt::Display for EditSessionUpdatedEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        format_session_event(f, self.event_name(), &self.session_id, self.operation_id)
    }
}

/// Edit session finished event.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct EditSessionFinishedEvent {
    pub session_id: EditSessionId,
    pub operation_id: EditOperationId,
}

impl EditSessionFinishedEvent {
    pub const EVENT_NAME: &'static str = "EditSessionFinished";

    pub fn new(session_id: impl Into<EditSessionId>, operation_id: EditOperationId) -> Self {
        Self {
            session_id: session_id.into(),
            operation_id,
        }
    }
}

impl DrawEvent for EditSessionFinishedEvent {}
impl EditEvent for EditSessionFinishedEvent {}

impl EditSessionEvent for EditSessionFinishedEvent {
    fn session_id(&self) -> &EditSessionId {
        &self.session_id
    }

    fn operation_id(&self) -> EditOperationId {
        self.operation_id
    }

    fn event_name(&self) -> &'static str {
        Self::EVENT_NAME
    }
}

impl fmt::Display for EditSessionFinishedEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        format_session_event(f, self.event_name(), &self.session_id, self.operation_id)
    }
}

/// Edit session cancelled event.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct EditSessionCancelledEvent {
    pub session_id: EditSessionId,
    pub operation_id: EditOperationId,
    pub reason: EditCancelReason,
}

impl EditSessionCancelledEvent {
    pub const EVENT_NAME: &'static str = "EditSessionCancelled";

    pub fn new(
        session_id: impl Into<EditSessionId>,
        operation_id: EditOperationId,
        reason: EditCancelReason,
    ) -> Self {
        Self {
            session_id: session_id.into(),
            operation_id,
            reason,
        }
    }
}

impl DrawEvent for EditSessionCancelledEvent {}
impl EditEvent for EditSessionCancelledEvent {}

impl EditSessionEvent for EditSessionCancelledEvent {
    fn session_id(&self) -> &EditSessionId {
        &self.session_id
    }

    fn operation_id(&self) -> EditOperationId {
        self.operation_id
    }

    fn event_name(&self) -> &'static str {
        Self::EVENT_NAME
    }
}

impl fmt::Display for EditSessionCancelledEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}(session: {}, reason: {})",
            Self::EVENT_NAME,
            self.session_id,
            self.reason
        )
    }
}

fn format_session_event(
    f: &mut fmt::Formatter<'_>,
    event_name: &str,
    session_id: &EditSessionId,
    operation_id: EditOperationId,
) -> fmt::Result {
    write!(
        f,
        "{event_name}(session: {session_id}, operation: {operation_id})"
    )
}
