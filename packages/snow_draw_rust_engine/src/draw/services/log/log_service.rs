#![allow(dead_code)]

use std::any::Any;
use std::collections::BTreeMap;
use std::fmt;
use std::future::Future;
use std::ops::Deref;
use std::panic::{self, AssertUnwindSafe};
use std::sync::{
    Arc, Mutex, MutexGuard, OnceLock, RwLock, RwLockReadGuard, RwLockWriteGuard, Weak,
};
use std::time::{Instant, SystemTime};

use super::log_config::{Level, LogConfig, LogModule};
use super::log_output::{DefaultLogRecord, LogLevel, LogOutputHandler, SharedLogRecord};

/// Extra key/value metadata attached to log messages.
pub type LogData = BTreeMap<String, String>;

/// Shared output handler reference used by [`LogService`].
pub type SharedLogOutputHandler = Arc<Mutex<dyn LogOutputHandler + Send>>;

fn resolve_release_mode() -> bool {
    !cfg!(debug_assertions)
}

fn lock_or_recover<T: ?Sized>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    match mutex.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

fn read_or_recover<T>(lock: &RwLock<T>) -> RwLockReadGuard<'_, T> {
    match lock.read() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

fn write_or_recover<T>(lock: &RwLock<T>) -> RwLockWriteGuard<'_, T> {
    match lock.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

fn panic_payload_to_string(payload: &(dyn Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<String>() {
        return message.clone();
    }
    if let Some(message) = payload.downcast_ref::<&str>() {
        return (*message).to_owned();
    }
    "panic without message".to_owned()
}

struct LogServiceInner {
    config: RwLock<LogConfig>,
    outputs: Mutex<Vec<SharedLogOutputHandler>>,
    module_loggers: Mutex<BTreeMap<LogModule, ModuleLogger>>,
}

/// Snow Draw logging service.
///
/// Provides module-scoped logging with configurable filtering and optional
/// output handlers.
#[derive(Clone)]
pub struct LogService {
    inner: Arc<LogServiceInner>,
}

impl fmt::Debug for LogService {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let config = self.config();
        let outputs_len = lock_or_recover(&self.inner.outputs).len();
        let module_loggers_len = lock_or_recover(&self.inner.module_loggers).len();

        f.debug_struct("LogService")
            .field("config", &config)
            .field("outputs_len", &outputs_len)
            .field("module_loggers_len", &module_loggers_len)
            .finish()
    }
}

impl Default for LogService {
    fn default() -> Self {
        Self::new(None, None)
    }
}

impl LogService {
    /// Shared fallback instance for code paths without context-provided logger.
    pub fn fallback() -> &'static Self {
        static FALLBACK: OnceLock<LogService> = OnceLock::new();
        FALLBACK.get_or_init(LogService::default)
    }

    /// Creates a new logging service.
    ///
    /// If no config is provided, uses development settings when debug assertions
    /// are enabled, otherwise production settings.
    pub fn new(config: Option<LogConfig>, outputs: Option<Vec<SharedLogOutputHandler>>) -> Self {
        let resolved_config = config.unwrap_or_else(|| {
            if resolve_release_mode() {
                LogConfig::production()
            } else {
                LogConfig::development()
            }
        });

        let service = Self {
            inner: Arc::new(LogServiceInner {
                config: RwLock::new(resolved_config),
                outputs: Mutex::new(Vec::new()),
                module_loggers: Mutex::new(BTreeMap::new()),
            }),
        };

        if let Some(output_handlers) = outputs {
            for output in output_handlers {
                service.add_output(output);
            }
        }

        service
    }

    /// Returns the current configuration snapshot.
    pub fn config(&self) -> LogConfig {
        read_or_recover(&self.inner.config).clone()
    }

    /// Replaces the configuration.
    ///
    /// Module logger cache is cleared to keep behavior aligned with the Dart
    /// implementation.
    pub fn update_config(&self, config: LogConfig) {
        *write_or_recover(&self.inner.config) = config;
        lock_or_recover(&self.inner.module_loggers).clear();
    }

    /// Adds a log output handler, ignoring duplicate instances.
    pub fn add_output(&self, output: SharedLogOutputHandler) {
        let mut outputs = lock_or_recover(&self.inner.outputs);
        if outputs
            .iter()
            .any(|existing| Arc::ptr_eq(existing, &output))
        {
            return;
        }
        outputs.push(output);
    }

    /// Removes a previously added output handler.
    pub fn remove_output(&self, output: &SharedLogOutputHandler) {
        let mut outputs = lock_or_recover(&self.inner.outputs);
        outputs.retain(|existing| !Arc::ptr_eq(existing, output));
    }

    /// Returns a logger bound to a specific module.
    ///
    /// Logger instances are cached per module.
    pub fn module(&self, module: LogModule) -> ModuleLogger {
        let mut cache = lock_or_recover(&self.inner.module_loggers);
        if let Some(logger) = cache.get(&module) {
            return logger.clone();
        }

        let logger = ModuleLogger::new(module, Arc::downgrade(&self.inner));
        cache.insert(module, logger.clone());
        logger
    }

    /// Shortcut for `LogModule::Store`.
    pub fn store(&self) -> ModuleLogger {
        self.module(LogModule::Store)
    }

    /// Shortcut for `LogModule::Pipeline`.
    pub fn pipeline(&self) -> ModuleLogger {
        self.module(LogModule::Pipeline)
    }

    /// Shortcut for `LogModule::Edit`.
    pub fn edit(&self) -> ModuleLogger {
        self.module(LogModule::Edit)
    }

    /// Shortcut for `LogModule::Element`.
    pub fn element(&self) -> ModuleLogger {
        self.module(LogModule::Element)
    }

    /// Shortcut for `LogModule::Input`.
    pub fn input(&self) -> ModuleLogger {
        self.module(LogModule::Input)
    }

    /// Shortcut for `LogModule::History`.
    pub fn history(&self) -> ModuleLogger {
        self.module(LogModule::History)
    }

    /// Shortcut for `LogModule::Render`.
    pub fn render(&self) -> ModuleLogger {
        self.module(LogModule::Render)
    }

    /// Shortcut for `LogModule::Service`.
    pub fn service(&self) -> ModuleLogger {
        self.module(LogModule::Service)
    }

    /// Shortcut for `LogModule::Config`.
    pub fn config_log(&self) -> ModuleLogger {
        self.module(LogModule::Config)
    }

    /// Shortcut for `LogModule::General`.
    pub fn general(&self) -> ModuleLogger {
        self.module(LogModule::General)
    }

    /// Core logging entry point.
    pub fn log(
        &self,
        level: Level,
        module: LogModule,
        message: &str,
        error: Option<&str>,
        stack_trace: Option<&str>,
        data: Option<&LogData>,
    ) {
        let config = self.config();
        if !config.should_log(module, level) {
            return;
        }

        let full_message = Self::build_message(&config, module, message, data);
        self.log_to_logger(level, module, &full_message, error, stack_trace);
        self.output_to_handlers(level, module, message, error, stack_trace);
    }

    fn build_message(
        config: &LogConfig,
        module: LogModule,
        message: &str,
        data: Option<&LogData>,
    ) -> String {
        let mut output = String::new();

        if config.include_module_name {
            output.push('[');
            output.push_str(module.display_name());
            output.push_str("] ");
        }

        output.push_str(message);

        if config.verbose {
            if let Some(data) = data {
                if !data.is_empty() {
                    output.push_str(" | ");
                    let joined = data
                        .iter()
                        .map(|(key, value)| format!("{key}={value}"))
                        .collect::<Vec<_>>()
                        .join(", ");
                    output.push_str(&joined);
                }
            }
        }

        output
    }

    fn log_to_logger(
        &self,
        level: Level,
        module: LogModule,
        message: &str,
        error: Option<&str>,
        stack_trace: Option<&str>,
    ) {
        let Some(normalized_level) = Self::normalize_level(level) else {
            return;
        };

        let log_level = match normalized_level {
            Level::Trace => log::Level::Trace,
            Level::Debug => log::Level::Debug,
            Level::Info => log::Level::Info,
            Level::Warning => log::Level::Warn,
            Level::Error | Level::Fatal => log::Level::Error,
            Level::All | Level::Off => return,
        };

        let mut rendered = message.to_owned();
        if let Some(err) = error {
            rendered.push_str(" | error=");
            rendered.push_str(err);
        }
        if let Some(stack) = stack_trace {
            rendered.push_str(" | stack_trace=");
            rendered.push_str(stack);
        }

        log::log!(target: module.display_name(), log_level, "{}", rendered);
    }

    fn normalize_level(level: Level) -> Option<Level> {
        if level < Level::Trace {
            return Some(Level::Trace);
        }
        if level > Level::Fatal {
            return None;
        }
        if level > Level::Error {
            return Some(Level::Fatal);
        }
        Some(level)
    }

    fn output_to_handlers(
        &self,
        level: Level,
        module: LogModule,
        message: &str,
        error: Option<&str>,
        stack_trace: Option<&str>,
    ) {
        let output_level = match level {
            Level::All | Level::Trace => LogLevel::Trace,
            Level::Debug => LogLevel::Debug,
            Level::Info => LogLevel::Info,
            Level::Warning => LogLevel::Warning,
            Level::Error => LogLevel::Error,
            Level::Fatal => LogLevel::Fatal,
            Level::Off => return,
        };

        let outputs = {
            let guard = lock_or_recover(&self.inner.outputs);
            if guard.is_empty() {
                return;
            }
            guard.clone()
        };

        let mut record = DefaultLogRecord::new(
            SystemTime::now(),
            output_level,
            module.display_name(),
            message,
        );

        if let Some(err) = error {
            record = record.with_error(err.to_owned());
        }
        if let Some(stack) = stack_trace {
            record = record.with_stack_trace(stack.to_owned());
        }

        let shared_record: SharedLogRecord = Arc::new(record);
        for output in outputs {
            let record_ref = Arc::clone(&shared_record);
            let _ = panic::catch_unwind(AssertUnwindSafe(|| {
                let mut handler = lock_or_recover(output.as_ref());
                handler.output(record_ref);
            }));
        }
    }

    /// Closes outputs and clears cached resources.
    pub fn dispose(&self) {
        let outputs = {
            let mut guard = lock_or_recover(&self.inner.outputs);
            let snapshot = guard.clone();
            guard.clear();
            snapshot
        };

        for output in outputs {
            let _ = panic::catch_unwind(AssertUnwindSafe(|| {
                let mut handler = lock_or_recover(output.as_ref());
                handler.close();
            }));
        }

        lock_or_recover(&self.inner.module_loggers).clear();
    }
}

/// Module-bound logger wrapper.
#[derive(Clone)]
pub struct ModuleLogger {
    module: LogModule,
    service: Weak<LogServiceInner>,
}

impl fmt::Debug for ModuleLogger {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ModuleLogger")
            .field("module", &self.module)
            .field("service_attached", &self.service.strong_count().gt(&0))
            .finish()
    }
}

impl ModuleLogger {
    const fn new(module: LogModule, service: Weak<LogServiceInner>) -> Self {
        Self { module, service }
    }

    /// Whether module logging is enabled at trace level.
    pub fn is_enabled(&self) -> bool {
        self.is_level_enabled(Level::Trace)
    }

    /// Checks whether a given level is currently enabled.
    pub fn is_level_enabled(&self, level: Level) -> bool {
        self.with_service(|service| service.config().should_log(self.module, level))
            .unwrap_or(false)
    }

    /// Logs a trace message.
    pub fn trace(&self, message: &str, data: Option<&LogData>) {
        self.log(Level::Trace, message, None, None, data);
    }

    /// Logs a debug message.
    pub fn debug(&self, message: &str, data: Option<&LogData>) {
        self.log(Level::Debug, message, None, None, data);
    }

    /// Logs an info message.
    pub fn info(&self, message: &str, data: Option<&LogData>) {
        self.log(Level::Info, message, None, None, data);
    }

    /// Logs a warning message.
    pub fn warning(&self, message: &str, data: Option<&LogData>) {
        self.log(Level::Warning, message, None, None, data);
    }

    /// Logs an error message.
    pub fn error(
        &self,
        message: &str,
        error: Option<&str>,
        stack_trace: Option<&str>,
        data: Option<&LogData>,
    ) {
        self.log(Level::Error, message, error, stack_trace, data);
    }

    /// Logs a fatal message.
    pub fn fatal(
        &self,
        message: &str,
        error: Option<&str>,
        stack_trace: Option<&str>,
        data: Option<&LogData>,
    ) {
        self.log(Level::Fatal, message, error, stack_trace, data);
    }

    /// Measures asynchronous operation duration.
    ///
    /// Returns the original operation result.
    pub async fn timed<T, E, F, Fut>(
        &self,
        operation: &str,
        action: F,
        level: Level,
    ) -> Result<T, E>
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = Result<T, E>>,
        E: fmt::Display,
    {
        let started = Instant::now();
        let result = action().await;
        let duration_ms = started.elapsed().as_millis();

        let mut data = LogData::new();
        data.insert("duration_ms".to_owned(), duration_ms.to_string());

        match result {
            Ok(value) => {
                let message = format!("{operation} completed");
                self.log(level, &message, None, None, Some(&data));
                Ok(value)
            }
            Err(error) => {
                let message = format!("{operation} failed");
                let error_text = error.to_string();
                self.log(
                    Level::Error,
                    &message,
                    Some(error_text.as_str()),
                    None,
                    Some(&data),
                );
                Err(error)
            }
        }
    }

    /// Measures synchronous operation duration.
    ///
    /// If the operation panics, logs the failure and resumes unwinding.
    pub fn timed_sync<T, F>(&self, operation: &str, action: F, level: Level) -> T
    where
        F: FnOnce() -> T + panic::UnwindSafe,
    {
        let started = Instant::now();
        let outcome = panic::catch_unwind(AssertUnwindSafe(action));
        let duration_ms = started.elapsed().as_millis();

        let mut data = LogData::new();
        data.insert("duration_ms".to_owned(), duration_ms.to_string());

        match outcome {
            Ok(value) => {
                let message = format!("{operation} completed");
                self.log(level, &message, None, None, Some(&data));
                value
            }
            Err(payload) => {
                let message = format!("{operation} failed");
                let panic_message = panic_payload_to_string(payload.as_ref());
                self.log(
                    Level::Error,
                    &message,
                    Some(panic_message.as_str()),
                    None,
                    Some(&data),
                );
                panic::resume_unwind(payload);
            }
        }
    }

    fn log(
        &self,
        level: Level,
        message: &str,
        error: Option<&str>,
        stack_trace: Option<&str>,
        data: Option<&LogData>,
    ) {
        let _ = self.with_service(|service| {
            service.log(level, self.module, message, error, stack_trace, data);
        });
    }

    fn with_service<R>(&self, f: impl FnOnce(&LogService) -> R) -> Option<R> {
        let inner = self.service.upgrade()?;
        let service = LogService { inner };
        Some(f(&service))
    }
}

/// No-op logging service variant.
///
/// This uses a silent configuration and exposes the same API through `Deref`.
#[derive(Clone, Debug)]
pub struct NoOpLogService {
    service: LogService,
}

impl NoOpLogService {
    pub fn new() -> Self {
        Self {
            service: LogService::new(Some(LogConfig::silent()), None),
        }
    }

    pub fn as_service(&self) -> &LogService {
        &self.service
    }

    pub fn into_service(self) -> LogService {
        self.service
    }
}

impl Default for NoOpLogService {
    fn default() -> Self {
        Self::new()
    }
}

impl Deref for NoOpLogService {
    type Target = LogService;

    fn deref(&self) -> &Self::Target {
        &self.service
    }
}
