#![allow(dead_code)]

use core::fmt;
use indexmap::IndexMap;
use serde_json::{Map as JsonMap, Value};

/// Base trait for draw events.
///
/// This mirrors the `DrawEvent` base class from Dart.
pub trait DrawEvent: fmt::Debug + fmt::Display + Send + Sync {}

/// JSON-backed event payload map used for validation details.
pub type EventPayloadMap = IndexMap<String, Value>;

/// Error event.
#[derive(Clone, Debug, PartialEq)]
pub struct ErrorEvent {
    pub message: String,
    pub error: String,
    pub stack_trace: Option<String>,
}

impl ErrorEvent {
    /// Creates a new error event.
    pub fn new(
        message: impl Into<String>,
        error: impl fmt::Display,
        stack_trace: Option<String>,
    ) -> Self {
        Self {
            message: message.into(),
            error: error.to_string(),
            stack_trace,
        }
    }
}

impl fmt::Display for ErrorEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "ErrorEvent(message: {}, error: {})",
            self.message, self.error
        )
    }
}

impl DrawEvent for ErrorEvent {}

/// Validation failure event.
#[derive(Clone, Debug, PartialEq)]
pub struct ValidationFailedEvent {
    pub action: String,
    pub reason: String,
    pub details: EventPayloadMap,
}

impl ValidationFailedEvent {
    /// Creates a new validation failure event.
    ///
    /// The payload is normalized into an owned tree so event details are
    /// isolated from caller-side mutation.
    pub fn new(
        action: impl Into<String>,
        reason: impl Into<String>,
        details: EventPayloadMap,
    ) -> Self {
        Self {
            action: action.into(),
            reason: reason.into(),
            details: freeze_event_payload_map(details),
        }
    }

    /// Creates a new validation failure event with empty details.
    pub fn with_empty_details(action: impl Into<String>, reason: impl Into<String>) -> Self {
        Self::new(action, reason, EventPayloadMap::new())
    }
}

impl fmt::Display for ValidationFailedEvent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "ValidationFailedEvent(action: {}, reason: {})",
            self.action, self.reason
        )
    }
}

impl DrawEvent for ValidationFailedEvent {}

/// Returns an immutable snapshot of event payload details.
///
/// In Rust this is represented as a fully-owned JSON tree, which prevents
/// aliasing with caller-owned mutable maps.
pub fn freeze_event_payload_map(payload: EventPayloadMap) -> EventPayloadMap {
    payload
        .into_iter()
        .map(|(key, value)| (key, freeze_payload_value(value)))
        .collect()
}

fn freeze_payload_value(value: Value) -> Value {
    match value {
        Value::Array(items) => Value::Array(items.into_iter().map(freeze_payload_value).collect()),
        Value::Object(entries) => Value::Object(
            entries
                .into_iter()
                .map(|(key, value)| (key, freeze_payload_value(value)))
                .collect::<JsonMap<String, Value>>(),
        ),
        primitive => primitive,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn error_event_formats_like_dart_to_string() {
        let event = ErrorEvent::new("Failed to render", "bad state", Some("line 1".to_string()));
        assert_eq!(
            event.to_string(),
            "ErrorEvent(message: Failed to render, error: bad state)"
        );
    }

    #[test]
    fn validation_failed_event_formats_like_dart_to_string() {
        let event = ValidationFailedEvent::with_empty_details("resize", "negative width");
        assert_eq!(
            event.to_string(),
            "ValidationFailedEvent(action: resize, reason: negative width)"
        );
    }

    #[test]
    fn freeze_payload_map_keeps_nested_json_structure() {
        let mut details = EventPayloadMap::new();
        details.insert(
            "nested".to_string(),
            json!({
                "arr": [1, 2, {"flag": true}],
                "obj": {"k": "v"}
            }),
        );

        let frozen = freeze_event_payload_map(details.clone());
        assert_eq!(frozen, details);
    }
}
