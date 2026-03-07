#![allow(dead_code)]

use std::fmt;
use std::sync::Arc;
use std::time::SystemTime;

/// Log severity level.
///
/// The ordering matches increasing severity, which allows direct comparisons
/// such as `record.level() >= LogLevel::Warning`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[repr(u8)]
pub enum LogLevel {
    Trace = 0,
    Debug = 1,
    Info = 2,
    Warning = 3,
    Error = 4,
    Fatal = 5,
}

impl fmt::Display for LogLevel {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let label = match self {
            Self::Trace => "TRACE",
            Self::Debug => "DEBUG",
            Self::Info => "INFO",
            Self::Warning => "WARNING",
            Self::Error => "ERROR",
            Self::Fatal => "FATAL",
        };
        f.write_str(label)
    }
}

/// Log record interface.
///
/// Used to collect log history or send logs to external services.
pub trait LogRecord: fmt::Debug + Send + Sync {
    fn timestamp(&self) -> SystemTime;
    fn level(&self) -> LogLevel;
    fn module(&self) -> &str;
    fn message(&self) -> &str;
    fn error(&self) -> Option<&str>;
    fn stack_trace(&self) -> Option<&str>;
}

/// Default log record implementation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DefaultLogRecord {
    pub timestamp: SystemTime,
    pub level: LogLevel,
    pub module: String,
    pub message: String,
    pub error: Option<String>,
    pub stack_trace: Option<String>,
}

impl DefaultLogRecord {
    pub fn new(
        timestamp: SystemTime,
        level: LogLevel,
        module: impl Into<String>,
        message: impl Into<String>,
    ) -> Self {
        Self {
            timestamp,
            level,
            module: module.into(),
            message: message.into(),
            error: None,
            stack_trace: None,
        }
    }

    pub fn with_error(mut self, error: impl Into<String>) -> Self {
        self.error = Some(error.into());
        self
    }

    pub fn with_stack_trace(mut self, stack_trace: impl Into<String>) -> Self {
        self.stack_trace = Some(stack_trace.into());
        self
    }
}

impl LogRecord for DefaultLogRecord {
    fn timestamp(&self) -> SystemTime {
        self.timestamp
    }

    fn level(&self) -> LogLevel {
        self.level
    }

    fn module(&self) -> &str {
        &self.module
    }

    fn message(&self) -> &str {
        &self.message
    }

    fn error(&self) -> Option<&str> {
        self.error.as_deref()
    }

    fn stack_trace(&self) -> Option<&str> {
        self.stack_trace.as_deref()
    }
}

impl fmt::Display for DefaultLogRecord {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if let Some(error) = self.error() {
            write!(
                f,
                "[{}] [{}] {} - Error: {}",
                self.level(),
                self.module(),
                self.message(),
                error
            )
        } else {
            write!(
                f,
                "[{}] [{}] {}",
                self.level(),
                self.module(),
                self.message()
            )
        }
    }
}

/// Shared log record handle for output handlers.
pub type SharedLogRecord = Arc<dyn LogRecord>;

/// Log output interface.
///
/// Implement to customize log output (files, network, and so on).
pub trait LogOutputHandler {
    /// Output a log.
    fn output(&mut self, record: SharedLogRecord);

    /// Output logs in batch.
    fn output_batch(&mut self, records: Vec<SharedLogRecord>) {
        for record in records {
            self.output(record);
        }
    }

    /// Close the output.
    fn close(&mut self);
}

/// In-memory log collector.
///
/// Keeps recent log records in memory for debugging and diagnostics.
#[derive(Debug)]
pub struct MemoryLogCollector {
    pub max_records: usize,
    records: Vec<SharedLogRecord>,
}

impl MemoryLogCollector {
    pub const DEFAULT_MAX_RECORDS: usize = 1000;

    pub fn new(max_records: usize) -> Self {
        Self {
            max_records,
            records: Vec::new(),
        }
    }

    /// Get all log records.
    pub fn records(&self) -> &[SharedLogRecord] {
        &self.records
    }

    /// Get the most recent n records.
    pub fn get_recent(&self, count: usize) -> Vec<SharedLogRecord> {
        if count == 0 {
            return Vec::new();
        }
        if count >= self.records.len() {
            return self.records.clone();
        }
        self.records[self.records.len() - count..].to_vec()
    }

    /// Filter records by level.
    pub fn filter_by_level(&self, min_level: LogLevel) -> Vec<SharedLogRecord> {
        self.records
            .iter()
            .filter(|record| record.level() >= min_level)
            .cloned()
            .collect()
    }

    /// Filter records by module.
    pub fn filter_by_module(&self, module: &str) -> Vec<SharedLogRecord> {
        self.records
            .iter()
            .filter(|record| record.module() == module)
            .cloned()
            .collect()
    }

    /// Clear records.
    pub fn clear(&mut self) {
        self.records.clear();
    }

    /// Removes oldest records when the buffer exceeds capacity.
    ///
    /// Uses a single `Vec::drain` call so trimming shifts list contents once.
    fn trim_excess(&mut self) {
        if self.max_records == 0 {
            self.records.clear();
            return;
        }
        let excess = self.records.len().saturating_sub(self.max_records);
        if excess > 0 {
            self.records.drain(0..excess);
        }
    }
}

impl Default for MemoryLogCollector {
    fn default() -> Self {
        Self::new(Self::DEFAULT_MAX_RECORDS)
    }
}

impl LogOutputHandler for MemoryLogCollector {
    fn output(&mut self, record: SharedLogRecord) {
        self.records.push(record);
        self.trim_excess();
    }

    fn output_batch(&mut self, records: Vec<SharedLogRecord>) {
        self.records.extend(records);
        self.trim_excess();
    }

    fn close(&mut self) {
        // The in-memory collector needs no special close handling.
    }
}
