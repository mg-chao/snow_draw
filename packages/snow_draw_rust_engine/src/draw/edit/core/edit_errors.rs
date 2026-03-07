#![allow(dead_code)]

use crate::draw::core::app_error::{AppError, AppErrorBase, ErrorSeverity};
use crate::draw::core::error_context::ErrorContext;
use std::error::Error;
use std::fmt;

const CONTEXT_REGISTRY_HINT: &str = "This usually indicates a bug in the edit operation registry.";
const CONTEXT_DISPATCH_HINT: &str =
    "Ensure that the correct operation is being dispatched for the context type.";
const TRANSFORM_DISPATCH_HINT: &str =
    "This usually indicates a state corruption or incorrect operation dispatch.";
const PARAMS_MAPPING_HINT: &str =
    "This usually indicates a wrong edit intent mapping or parameters injection.";

/// Edit system error base trait.
pub trait EditError: AppErrorBase {}

impl<T> EditError for T where T: AppErrorBase + ?Sized {}

fn build_type_mismatch_message(
    error_name: &str,
    operation_name: &str,
    value_name: &str,
    expected: &str,
    actual: &str,
    additional_info: Option<&str>,
    hints: &[&str],
) -> String {
    let mut lines = Vec::with_capacity(5 + hints.len());
    lines.push(format!("{error_name}:"));
    lines.push(format!("  Operation: {operation_name}"));
    lines.push(format!("  Expected {value_name} type: {expected}"));
    lines.push(format!("  Actual {value_name} type: {actual}"));

    if let Some(additional_info) = additional_info {
        lines.push(format!("  Additional info: {additional_info}"));
    }

    lines.extend(hints.iter().map(|hint| format!("  {hint}")));
    lines.join("\n")
}

/// Thrown when an edit context of an unexpected type is provided to an
/// operation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EditContextTypeMismatchError {
    pub expected: String,
    pub actual: String,
    pub operation_name: String,
    pub additional_info: Option<String>,
}

impl EditContextTypeMismatchError {
    pub fn new(
        expected: impl Into<String>,
        actual: impl Into<String>,
        operation_name: impl Into<String>,
        additional_info: Option<String>,
    ) -> Self {
        Self {
            expected: expected.into(),
            actual: actual.into(),
            operation_name: operation_name.into(),
            additional_info,
        }
    }

    pub fn from_types<TExpected, TActual>(
        operation_name: impl Into<String>,
        additional_info: Option<String>,
    ) -> Self
    where
        TExpected: 'static,
        TActual: 'static,
    {
        Self::new(
            std::any::type_name::<TExpected>(),
            std::any::type_name::<TActual>(),
            operation_name,
            additional_info,
        )
    }
}

impl fmt::Display for EditContextTypeMismatchError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&build_type_mismatch_message(
            "EditContextTypeMismatchError",
            &self.operation_name,
            "context",
            &self.expected,
            &self.actual,
            self.additional_info.as_deref(),
            &[CONTEXT_REGISTRY_HINT, CONTEXT_DISPATCH_HINT],
        ))
    }
}

impl Error for EditContextTypeMismatchError {}

impl AppError for EditContextTypeMismatchError {
    fn severity(&self) -> ErrorSeverity {
        ErrorSeverity::Fatal
    }
}

/// Thrown when an edit transform of an unexpected type is provided to an
/// operation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EditTransformTypeMismatchError {
    pub expected: String,
    pub actual: String,
    pub operation_name: String,
    pub additional_info: Option<String>,
}

impl EditTransformTypeMismatchError {
    pub fn new(
        expected: impl Into<String>,
        actual: impl Into<String>,
        operation_name: impl Into<String>,
        additional_info: Option<String>,
    ) -> Self {
        Self {
            expected: expected.into(),
            actual: actual.into(),
            operation_name: operation_name.into(),
            additional_info,
        }
    }

    pub fn from_types<TExpected, TActual>(
        operation_name: impl Into<String>,
        additional_info: Option<String>,
    ) -> Self
    where
        TExpected: 'static,
        TActual: 'static,
    {
        Self::new(
            std::any::type_name::<TExpected>(),
            std::any::type_name::<TActual>(),
            operation_name,
            additional_info,
        )
    }
}

impl fmt::Display for EditTransformTypeMismatchError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&build_type_mismatch_message(
            "EditTransformTypeMismatchError",
            &self.operation_name,
            "transform",
            &self.expected,
            &self.actual,
            self.additional_info.as_deref(),
            &[TRANSFORM_DISPATCH_HINT],
        ))
    }
}

impl Error for EditTransformTypeMismatchError {}

impl AppError for EditTransformTypeMismatchError {
    fn severity(&self) -> ErrorSeverity {
        ErrorSeverity::Fatal
    }
}

/// Thrown when edit operation params of an unexpected type are provided.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EditParamsTypeMismatchError {
    pub expected: String,
    pub actual: String,
    pub operation_name: String,
    pub additional_info: Option<String>,
}

impl EditParamsTypeMismatchError {
    pub fn new(
        expected: impl Into<String>,
        actual: impl Into<String>,
        operation_name: impl Into<String>,
        additional_info: Option<String>,
    ) -> Self {
        Self {
            expected: expected.into(),
            actual: actual.into(),
            operation_name: operation_name.into(),
            additional_info,
        }
    }

    pub fn from_types<TExpected, TActual>(
        operation_name: impl Into<String>,
        additional_info: Option<String>,
    ) -> Self
    where
        TExpected: 'static,
        TActual: 'static,
    {
        Self::new(
            std::any::type_name::<TExpected>(),
            std::any::type_name::<TActual>(),
            operation_name,
            additional_info,
        )
    }
}

impl fmt::Display for EditParamsTypeMismatchError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&build_type_mismatch_message(
            "EditParamsTypeMismatchError",
            &self.operation_name,
            "params",
            &self.expected,
            &self.actual,
            self.additional_info.as_deref(),
            &[PARAMS_MAPPING_HINT],
        ))
    }
}

impl Error for EditParamsTypeMismatchError {}

impl AppError for EditParamsTypeMismatchError {
    fn severity(&self) -> ErrorSeverity {
        ErrorSeverity::Fatal
    }
}

/// Thrown when required edit-session data is missing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EditMissingDataError {
    pub data_name: String,
    pub operation_name: Option<String>,
}

impl EditMissingDataError {
    pub fn new(data_name: impl Into<String>, operation_name: Option<String>) -> Self {
        Self {
            data_name: data_name.into(),
            operation_name,
        }
    }
}

impl fmt::Display for EditMissingDataError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let operation_prefix = self
            .operation_name
            .as_deref()
            .map_or(String::new(), |name| format!("[{name}] "));
        write!(
            f,
            "EditMissingDataError: {operation_prefix}Missing required data: {}",
            self.data_name
        )
    }
}

impl Error for EditMissingDataError {}

impl AppError for EditMissingDataError {
    fn severity(&self) -> ErrorSeverity {
        ErrorSeverity::Degradable
    }
}

/// Wrapper for edit errors with additional context information.
#[derive(Debug)]
pub struct EditErrorWithContext {
    pub inner_error: Box<dyn EditError + Send + Sync>,
    pub context: ErrorContext,
}

impl EditErrorWithContext {
    pub fn new<E>(inner_error: E, context: ErrorContext) -> Self
    where
        E: EditError + Send + Sync + 'static,
    {
        Self {
            inner_error: Box::new(inner_error),
            context,
        }
    }

    pub fn from_box(inner_error: Box<dyn EditError + Send + Sync>, context: ErrorContext) -> Self {
        Self {
            inner_error,
            context,
        }
    }
}

impl fmt::Display for EditErrorWithContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}\n{}", self.inner_error, self.context)
    }
}

impl Error for EditErrorWithContext {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        Some(self.inner_error.as_ref())
    }
}

impl AppError for EditErrorWithContext {
    fn severity(&self) -> ErrorSeverity {
        self.inner_error.severity()
    }

    fn cause(&self) -> Option<&(dyn Error + 'static)> {
        Some(self.inner_error.as_ref())
    }
}
