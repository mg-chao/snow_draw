use crate::draw::core::app_error::{AppError, ErrorSeverity};
use std::error::Error;
use std::fmt;

/// Error thrown when history recording fails.
///
/// Mirrors the Dart `HistoryRecordingError`:
/// - `action` identifies the failed history operation.
/// - `cause` stores an optional underlying error.
#[derive(Debug)]
pub struct HistoryRecordingError {
    pub action: String,
    pub cause: Option<Box<dyn Error + Send + Sync + 'static>>,
}

impl HistoryRecordingError {
    pub fn new(action: impl Into<String>) -> Self {
        Self {
            action: action.into(),
            cause: None,
        }
    }

    pub fn with_cause<E>(action: impl Into<String>, cause: E) -> Self
    where
        E: Error + Send + Sync + 'static,
    {
        Self {
            action: action.into(),
            cause: Some(Box::new(cause)),
        }
    }

    pub fn with_optional_cause(
        action: impl Into<String>,
        cause: Option<Box<dyn Error + Send + Sync + 'static>>,
    ) -> Self {
        Self {
            action: action.into(),
            cause,
        }
    }
}

impl fmt::Display for HistoryRecordingError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let cause_text = self
            .cause
            .as_deref()
            .map(ToString::to_string)
            .unwrap_or_else(|| "null".to_owned());
        write!(
            f,
            "HistoryRecordingError(action: {}, cause: {})",
            self.action, cause_text
        )
    }
}

impl Error for HistoryRecordingError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        self.cause
            .as_deref()
            .map(|cause| cause as &(dyn Error + 'static))
    }
}

impl AppError for HistoryRecordingError {
    fn severity(&self) -> ErrorSeverity {
        ErrorSeverity::Degradable
    }

    fn cause(&self) -> Option<&(dyn Error + 'static)> {
        self.cause
            .as_deref()
            .map(|cause| cause as &(dyn Error + 'static))
    }
}
