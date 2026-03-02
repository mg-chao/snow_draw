use core::fmt::Display;
use std::error::Error;

/// Severity levels for application-level errors.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorSeverity {
    Recoverable,
    Degradable,
    Fatal,
}

/// Shared error base for application-level failures.
///
/// This mirrors the Dart `AppError` contract:
/// - `message` defaults to the error's display text.
/// - `severity` is required.
/// - `cause` defaults to no underlying cause.
pub trait AppError: Error + Display {
    /// Human-readable error message.
    fn message(&self) -> String {
        self.to_string()
    }

    /// Severity associated with this error.
    fn severity(&self) -> ErrorSeverity;

    /// Optional underlying cause.
    fn cause(&self) -> Option<&(dyn Error + 'static)> {
        None
    }
}

/// Convenience base trait with default message/cause handling from `AppError`.
pub trait AppErrorBase: AppError {}

impl<T> AppErrorBase for T where T: AppError + ?Sized {}
