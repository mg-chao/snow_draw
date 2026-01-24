import 'package:logger/logger.dart';
import 'package:meta/meta.dart';

/// Log module identifiers.
///
/// Used to categorize and filter log output.
enum LogModule {
  /// State management.
  store('Store'),

  /// Middleware pipeline.
  pipeline('Pipeline'),

  /// Edit operations.
  edit('Edit'),

  /// Element operations.
  element('Element'),

  /// Input handling.
  input('Input'),

  /// History/undo redo.
  history('History'),

  /// Rendering.
  render('Render'),

  /// Services.
  service('Service'),

  /// Configuration.
  config('Config'),

  /// General/uncategorized.
  general('General');

  const LogModule(this.displayName);

  final String displayName;
}

/// Log configuration.
///
/// Supports filtering log output by module and level.
@immutable
class LogConfig {
  const LogConfig({
    this.minLevel = Level.debug,
    this.enabled = true,
    this.includeTimestamp = true,
    this.includeModuleName = true,
    this.includeStackTrace = false,
    this.stackTraceMethodCount = 3,
    this.moduleLevels = const {},
    this.disabledModules = const {},
    this.colorOutput = true,
    this.emojiOutput = true,
    this.verbose = false,
  });

  /// Global minimum log level.
  final Level minLevel;

  /// Whether logging is enabled.
  final bool enabled;

  /// Whether to include timestamps in logs.
  final bool includeTimestamp;

  /// Whether to include module names in logs.
  final bool includeModuleName;

  /// Whether to include stack traces in logs.
  final bool includeStackTrace;

  /// Method count for stack traces.
  final int stackTraceMethodCount;

  /// Per-module log level overrides.
  ///
  /// If a module is specified here, use that level instead of [minLevel].
  final Map<LogModule, Level> moduleLevels;

  /// Set of disabled modules.
  ///
  /// Logs for these modules are completely suppressed.
  final Set<LogModule> disabledModules;

  /// Whether to enable colored output (console only).
  final bool colorOutput;

  /// Whether to output emoji.
  final bool emojiOutput;

  /// Whether verbose output is enabled (for debugging).
  final bool verbose;

  /// Default development configuration.
  static const development = LogConfig(verbose: true, includeStackTrace: true);

  /// Default production configuration.
  static const production = LogConfig(
    minLevel: Level.warning,
    emojiOutput: false,
  );

  /// Default test configuration.
  static const test = LogConfig(
    minLevel: Level.warning,
    enabled: false, // Logging is disabled by default for tests.
  );

  /// Silent configuration (fully disabled).
  static const silent = LogConfig(enabled: false);

  /// Check whether a module should log at a given level.
  bool shouldLog(LogModule module, Level level) {
    if (!enabled) {
      return false;
    }
    if (disabledModules.contains(module)) {
      return false;
    }

    final effectiveLevel = moduleLevels[module] ?? minLevel;
    return level.index >= effectiveLevel.index;
  }

  /// Get the effective log level for a module.
  Level getEffectiveLevel(LogModule module) => moduleLevels[module] ?? minLevel;

  LogConfig copyWith({
    Level? minLevel,
    bool? enabled,
    bool? includeTimestamp,
    bool? includeModuleName,
    bool? includeStackTrace,
    int? stackTraceMethodCount,
    Map<LogModule, Level>? moduleLevels,
    Set<LogModule>? disabledModules,
    bool? colorOutput,
    bool? emojiOutput,
    bool? verbose,
  }) => LogConfig(
    minLevel: minLevel ?? this.minLevel,
    enabled: enabled ?? this.enabled,
    includeTimestamp: includeTimestamp ?? this.includeTimestamp,
    includeModuleName: includeModuleName ?? this.includeModuleName,
    includeStackTrace: includeStackTrace ?? this.includeStackTrace,
    stackTraceMethodCount: stackTraceMethodCount ?? this.stackTraceMethodCount,
    moduleLevels: moduleLevels ?? this.moduleLevels,
    disabledModules: disabledModules ?? this.disabledModules,
    colorOutput: colorOutput ?? this.colorOutput,
    emojiOutput: emojiOutput ?? this.emojiOutput,
    verbose: verbose ?? this.verbose,
  );

  /// Enable a specific module.
  LogConfig enableModule(LogModule module) {
    final newDisabled = Set<LogModule>.from(disabledModules)..remove(module);
    return copyWith(disabledModules: newDisabled);
  }

  /// Disable a specific module.
  LogConfig disableModule(LogModule module) {
    final newDisabled = Set<LogModule>.from(disabledModules)..add(module);
    return copyWith(disabledModules: newDisabled);
  }

  /// Set the level for a module.
  LogConfig withModuleLevel(LogModule module, Level level) {
    final newLevels = Map<LogModule, Level>.from(moduleLevels);
    newLevels[module] = level;
    return copyWith(moduleLevels: newLevels);
  }
}
