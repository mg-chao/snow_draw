#![allow(dead_code)]

use indexmap::IndexMap;
use serde_json::Value;
use std::fmt;
use std::time::{SystemTime, UNIX_EPOCH};

/// Metadata attached to an [`ErrorContext`].
///
/// Values use JSON data to model Dart's `dynamic` metadata map.
pub type ErrorMetadata = IndexMap<String, Value>;

/// Error context information for debugging and tracking.
#[derive(Clone, Debug, PartialEq)]
pub struct ErrorContext {
    pub operation_name: String,
    pub metadata: ErrorMetadata,
    pub timestamp: SystemTime,
    pub stack_trace: Option<String>,
}

impl ErrorContext {
    /// Creates a context with the current timestamp and empty metadata.
    pub fn new(operation_name: impl Into<String>) -> Self {
        Self {
            operation_name: operation_name.into(),
            metadata: ErrorMetadata::new(),
            timestamp: SystemTime::now(),
            stack_trace: None,
        }
    }

    /// Creates a context with full control over optional fields.
    pub fn with_details(
        operation_name: impl Into<String>,
        metadata: ErrorMetadata,
        timestamp: Option<SystemTime>,
        stack_trace: Option<String>,
    ) -> Self {
        Self {
            operation_name: operation_name.into(),
            metadata,
            timestamp: timestamp.unwrap_or_else(SystemTime::now),
            stack_trace,
        }
    }

    /// Returns a copy with optional updates.
    ///
    /// Additional metadata is merged into the existing metadata map. When a key
    /// exists in both maps, the additional metadata value wins.
    pub fn copy_with(
        &self,
        operation_name: Option<String>,
        additional_metadata: Option<ErrorMetadata>,
        timestamp: Option<SystemTime>,
        stack_trace: Option<String>,
    ) -> Self {
        let mut next_metadata = self.metadata.clone();
        if let Some(additional_metadata) = additional_metadata {
            if !additional_metadata.is_empty() {
                next_metadata.extend(additional_metadata);
            }
        }

        Self {
            operation_name: operation_name.unwrap_or_else(|| self.operation_name.clone()),
            metadata: next_metadata,
            timestamp: timestamp.unwrap_or(self.timestamp),
            stack_trace: stack_trace.or_else(|| self.stack_trace.clone()),
        }
    }
}

impl fmt::Display for ErrorContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "ErrorContext:")?;
        writeln!(f, "  Operation: {}", self.operation_name)?;
        writeln!(f, "  Timestamp: {}", format_timestamp(self.timestamp))?;

        if self.metadata.is_empty() {
            return Ok(());
        }

        writeln!(f, "  Metadata:")?;
        for (key, value) in &self.metadata {
            writeln!(f, "    {key}: {}", format_metadata_value(value))?;
        }

        Ok(())
    }
}

fn format_timestamp(timestamp: SystemTime) -> String {
    match timestamp.duration_since(UNIX_EPOCH) {
        Ok(duration) => format!(
            "{}.{:03}s since unix epoch",
            duration.as_secs(),
            duration.subsec_millis()
        ),
        Err(error) => {
            let duration = error.duration();
            format!(
                "-{}.{:03}s since unix epoch",
                duration.as_secs(),
                duration.subsec_millis()
            )
        }
    }
}

fn format_metadata_value(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        _ => value.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn copy_with_merges_metadata() {
        let mut base_metadata = ErrorMetadata::new();
        base_metadata.insert("kind".to_string(), json!("base"));
        base_metadata.insert("count".to_string(), json!(1));

        let context = ErrorContext::with_details(
            "render_frame",
            base_metadata,
            Some(UNIX_EPOCH),
            Some("stack-a".to_string()),
        );

        let mut additional = ErrorMetadata::new();
        additional.insert("count".to_string(), json!(2));
        additional.insert("region".to_string(), json!("toolbar"));

        let next = context.copy_with(None, Some(additional), None, None);

        assert_eq!(next.operation_name, "render_frame");
        assert_eq!(next.stack_trace.as_deref(), Some("stack-a"));
        assert_eq!(next.metadata.get("kind"), Some(&json!("base")));
        assert_eq!(next.metadata.get("count"), Some(&json!(2)));
        assert_eq!(next.metadata.get("region"), Some(&json!("toolbar")));
    }
}
