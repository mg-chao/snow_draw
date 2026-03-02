#![allow(dead_code)]

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fmt;

/// Log module identifiers used to categorize and filter output.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum LogModule {
    /// State management.
    Store,
    /// Middleware pipeline.
    Pipeline,
    /// Edit operations.
    Edit,
    /// Element operations.
    Element,
    /// Input handling.
    Input,
    /// History/undo redo.
    History,
    /// Rendering.
    Render,
    /// Services.
    Service,
    /// Configuration.
    Config,
    /// General/uncategorized.
    General,
}

impl LogModule {
    /// Human-readable module label used in formatted log output.
    pub const fn display_name(self) -> &'static str {
        match self {
            Self::Store => "Store",
            Self::Pipeline => "Pipeline",
            Self::Edit => "Edit",
            Self::Element => "Element",
            Self::Input => "Input",
            Self::History => "History",
            Self::Render => "Render",
            Self::Service => "Service",
            Self::Config => "Config",
            Self::General => "General",
        }
    }
}

impl fmt::Display for LogModule {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.display_name())
    }
}

/// Log severity level.
///
/// The variant order mirrors Dart `logger` level indexes, which allows direct
/// ordinal comparisons for filtering (`level >= effective_level`).
#[derive(
    Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize,
)]
pub enum Level {
    All,
    Trace,
    #[default]
    Debug,
    Info,
    Warning,
    Error,
    Fatal,
    Off,
}

impl fmt::Display for Level {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let text = match self {
            Self::All => "all",
            Self::Trace => "trace",
            Self::Debug => "debug",
            Self::Info => "info",
            Self::Warning => "warning",
            Self::Error => "error",
            Self::Fatal => "fatal",
            Self::Off => "off",
        };
        f.write_str(text)
    }
}

/// Log configuration.
///
/// Supports filtering by module and severity.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LogConfig {
    /// Global minimum log level.
    pub min_level: Level,

    /// Whether logging is enabled.
    pub enabled: bool,

    /// Whether to include timestamps in logs.
    pub include_timestamp: bool,

    /// Whether to include module names in logs.
    pub include_module_name: bool,

    /// Whether to include stack traces in logs.
    pub include_stack_trace: bool,

    /// Method count for stack traces.
    pub stack_trace_method_count: usize,

    /// Per-module log level overrides.
    pub module_levels: BTreeMap<LogModule, Level>,

    /// Set of disabled modules.
    pub disabled_modules: BTreeSet<LogModule>,

    /// Whether to enable colored output (console only).
    pub color_output: bool,

    /// Whether to output emoji.
    pub emoji_output: bool,

    /// Whether verbose output is enabled.
    pub verbose: bool,
}

impl LogConfig {
    /// Default stack trace method count.
    pub const DEFAULT_STACK_TRACE_METHOD_COUNT: usize = 3;

    #[allow(clippy::too_many_arguments)]
    pub fn new(
        min_level: Level,
        enabled: bool,
        include_timestamp: bool,
        include_module_name: bool,
        include_stack_trace: bool,
        stack_trace_method_count: usize,
        module_levels: BTreeMap<LogModule, Level>,
        disabled_modules: BTreeSet<LogModule>,
        color_output: bool,
        emoji_output: bool,
        verbose: bool,
    ) -> Self {
        Self {
            min_level,
            enabled,
            include_timestamp,
            include_module_name,
            include_stack_trace,
            stack_trace_method_count,
            module_levels,
            disabled_modules,
            color_output,
            emoji_output,
            verbose,
        }
    }

    /// Default development profile.
    pub fn development() -> Self {
        Self::default().copy_with(
            None,
            None,
            None,
            None,
            Some(true),
            None,
            None,
            None,
            None,
            None,
            Some(true),
        )
    }

    /// Default production profile.
    pub fn production() -> Self {
        Self::default().copy_with(
            Some(Level::Warning),
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            Some(false),
            None,
        )
    }

    /// Default test profile.
    pub fn test() -> Self {
        Self::silent()
    }

    /// Silent profile (fully disabled).
    pub fn silent() -> Self {
        Self::default().copy_with(
            None,
            Some(false),
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
        )
    }

    /// Returns whether a message should be logged for `module` at `level`.
    pub fn should_log(&self, module: LogModule, level: Level) -> bool {
        self.enabled
            && !self.disabled_modules.contains(&module)
            && level >= self.get_effective_level(module)
    }

    /// Returns the effective level for a module.
    pub fn get_effective_level(&self, module: LogModule) -> Level {
        self.module_levels
            .get(&module)
            .copied()
            .unwrap_or(self.min_level)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn copy_with(
        &self,
        min_level: Option<Level>,
        enabled: Option<bool>,
        include_timestamp: Option<bool>,
        include_module_name: Option<bool>,
        include_stack_trace: Option<bool>,
        stack_trace_method_count: Option<usize>,
        module_levels: Option<BTreeMap<LogModule, Level>>,
        disabled_modules: Option<BTreeSet<LogModule>>,
        color_output: Option<bool>,
        emoji_output: Option<bool>,
        verbose: Option<bool>,
    ) -> Self {
        if min_level.is_none()
            && enabled.is_none()
            && include_timestamp.is_none()
            && include_module_name.is_none()
            && include_stack_trace.is_none()
            && stack_trace_method_count.is_none()
            && module_levels.is_none()
            && disabled_modules.is_none()
            && color_output.is_none()
            && emoji_output.is_none()
            && verbose.is_none()
        {
            return self.clone();
        }

        let next = Self::new(
            min_level.unwrap_or(self.min_level),
            enabled.unwrap_or(self.enabled),
            include_timestamp.unwrap_or(self.include_timestamp),
            include_module_name.unwrap_or(self.include_module_name),
            include_stack_trace.unwrap_or(self.include_stack_trace),
            stack_trace_method_count.unwrap_or(self.stack_trace_method_count),
            module_levels.unwrap_or_else(|| self.module_levels.clone()),
            disabled_modules.unwrap_or_else(|| self.disabled_modules.clone()),
            color_output.unwrap_or(self.color_output),
            emoji_output.unwrap_or(self.emoji_output),
            verbose.unwrap_or(self.verbose),
        );

        if next == *self {
            self.clone()
        } else {
            next
        }
    }

    /// Enables a specific module.
    pub fn enable_module(&self, module: LogModule) -> Self {
        if !self.disabled_modules.contains(&module) {
            return self.clone();
        }

        let mut disabled_modules = self.disabled_modules.clone();
        disabled_modules.remove(&module);

        self.copy_with(
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            Some(disabled_modules),
            None,
            None,
            None,
        )
    }

    /// Disables a specific module.
    pub fn disable_module(&self, module: LogModule) -> Self {
        if self.disabled_modules.contains(&module) {
            return self.clone();
        }

        let mut disabled_modules = self.disabled_modules.clone();
        disabled_modules.insert(module);

        self.copy_with(
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            Some(disabled_modules),
            None,
            None,
            None,
        )
    }

    /// Sets the level for a module.
    pub fn with_module_level(&self, module: LogModule, level: Level) -> Self {
        if self.module_levels.get(&module).copied() == Some(level) {
            return self.clone();
        }

        let mut module_levels = self.module_levels.clone();
        module_levels.insert(module, level);

        self.copy_with(
            None,
            None,
            None,
            None,
            None,
            None,
            Some(module_levels),
            None,
            None,
            None,
            None,
        )
    }
}

impl Default for LogConfig {
    fn default() -> Self {
        Self::new(
            Level::Debug,
            true,
            true,
            true,
            false,
            Self::DEFAULT_STACK_TRACE_METHOD_COUNT,
            BTreeMap::new(),
            BTreeSet::new(),
            true,
            true,
            false,
        )
    }
}

impl fmt::Display for LogConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "LogConfig(min_level: {}, enabled: {}, include_timestamp: {}, include_module_name: {}, include_stack_trace: {}, stack_trace_method_count: {}, module_levels: {}, disabled_modules: {}, color_output: {}, emoji_output: {}, verbose: {})",
            self.min_level,
            self.enabled,
            self.include_timestamp,
            self.include_module_name,
            self.include_stack_trace,
            self.stack_trace_method_count,
            self.module_levels.len(),
            self.disabled_modules.len(),
            self.color_output,
            self.emoji_output,
            self.verbose
        )
    }
}
