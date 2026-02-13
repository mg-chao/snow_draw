import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'log_config.dart';
import 'log_output.dart';

/// Snow Draw logging service.
///
/// Unified logging management that supports:
/// - Modular logs (by functional area)
/// - Configurable log levels
/// - Multiple output targets (console, memory, streams, and so on)
/// - Integration with DrawContext
///
/// Usage example:
/// ```dart
/// final logService = LogService();
/// final storeLog = logService.module(LogModule.store);
///
/// storeLog.debug('Dispatching action', {'action': 'AddElement'});
/// storeLog.info('State updated');
/// storeLog.warning('Deprecated API usage');
/// storeLog.error('Failed to save', error, stackTrace);
/// ```
class LogService {
  /// Shared fallback instance for code paths without a context-provided logger.
  ///
  /// This avoids creating multiple orphan LogService instances across modules.
  /// Lazy-initialized on first access.
  static final fallback = LogService();
  LogService({
    LogConfig? config,
    Logger? logger,
    List<LogOutputHandler>? outputs,
  }) : _config =
           config ??
           (kReleaseMode ? LogConfig.production : LogConfig.development),
       _logger =
           logger ??
           Logger(
             printer: PrettyPrinter(
               methodCount: 0,
               errorMethodCount: 5,
               lineLength: 80,
               dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
             ),
             level: Level.trace,
           ) {
    if (outputs != null) {
      _outputs.addAll(outputs);
    }
  }
  LogConfig _config;
  final Logger _logger;
  final List<LogOutputHandler> _outputs = [];

  /// Module logger cache.
  final Map<LogModule, ModuleLogger> _moduleLoggers = {};

  /// Current configuration.
  LogConfig get config => _config;

  /// Update configuration.
  void updateConfig(LogConfig config) {
    _config = config;
    // Clear cache so module loggers pick up the new config.
    _moduleLoggers.clear();
  }

  /// Add an output handler.
  void addOutput(LogOutputHandler output) {
    _outputs.add(output);
  }

  /// Remove an output handler.
  void removeOutput(LogOutputHandler output) {
    _outputs.remove(output);
  }

  /// Get a module logger.
  ///
  /// Loggers are cached; the same module returns the same instance.
  ModuleLogger module(LogModule module) => _moduleLoggers.putIfAbsent(
    module,
    () => ModuleLogger(module: module, service: this),
  );

  /// Shortcut accessors.
  ModuleLogger get store => module(LogModule.store);
  ModuleLogger get pipeline => module(LogModule.pipeline);
  ModuleLogger get edit => module(LogModule.edit);
  ModuleLogger get element => module(LogModule.element);
  ModuleLogger get input => module(LogModule.input);
  ModuleLogger get history => module(LogModule.history);
  ModuleLogger get render => module(LogModule.render);
  ModuleLogger get service => module(LogModule.service);
  ModuleLogger get configLog => module(LogModule.config);
  ModuleLogger get general => module(LogModule.general);

  /// Internal logging method.
  void log(
    Level level,
    LogModule module,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
  }) {
    if (!_config.shouldLog(module, level)) {
      return;
    }

    // Build the full message.
    final fullMessage = _buildMessage(module, message, data);

    // Output to the logger.
    _logToLogger(level, fullMessage, error, stackTrace);

    // Output to other handlers.
    _outputToHandlers(level, module, message, error, stackTrace);
  }

  String _buildMessage(
    LogModule module,
    String message,
    Map<String, dynamic>? data,
  ) {
    final buffer = StringBuffer();

    if (_config.includeModuleName) {
      buffer.write('[${module.displayName}] ');
    }

    buffer.write(message);

    if (data != null && data.isNotEmpty && _config.verbose) {
      buffer
        ..write(' | ')
        ..write(data.entries.map((e) => '${e.key}=${e.value}').join(', '));
    }

    return buffer.toString();
  }

  void _logToLogger(
    Level level,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    final offThreshold = Level.off.value - 1;
    if (level.value >= offThreshold) {
      return;
    }
    if (level.value >= Level.fatal.value - 1) {
      _logger.f(message, error: error, stackTrace: stackTrace);
      return;
    }
    if (level.value >= Level.error.value) {
      _logger.e(message, error: error, stackTrace: stackTrace);
      return;
    }
    if (level.value >= Level.warning.value) {
      _logger.w(message, error: error, stackTrace: stackTrace);
      return;
    }
    if (level.value >= Level.info.value) {
      _logger.i(message, error: error, stackTrace: stackTrace);
      return;
    }
    if (level.value >= Level.debug.value) {
      _logger.d(message, error: error, stackTrace: stackTrace);
      return;
    }
    _logger.t(message, error: error, stackTrace: stackTrace);
  }

  void _outputToHandlers(
    Level level,
    LogModule module,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (_outputs.isEmpty) {
      return;
    }

    final record = DefaultLogRecord(
      timestamp: DateTime.now(),
      level: level,
      module: module.displayName,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    for (final output in _outputs) {
      try {
        output.output(record);
      } on Object catch (_) {
        // Ignore output errors to avoid crashing the app.
      }
    }
  }

  /// Close the logging service.
  void dispose() {
    for (final output in _outputs) {
      try {
        output.close();
      } on Object catch (_) {
        // Ignore close errors.
      }
    }
    _outputs.clear();
    _moduleLoggers.clear();
  }
}

/// Module logger.
///
/// Logger interface for a specific module, with module info attached.
class ModuleLogger {
  const ModuleLogger({required this.module, required this.service});
  final LogModule module;
  final LogService service;

  /// Whether logging is enabled.
  bool get isEnabled => service.config.shouldLog(module, Level.trace);

  /// Check if a specific level is enabled.
  bool isLevelEnabled(Level level) => service.config.shouldLog(module, level);

  /// Trace level logs (most detailed, for execution flow).
  void trace(String message, [Map<String, dynamic>? data]) {
    service.log(Level.trace, module, message, data: data);
  }

  /// Debug level logs (debug info).
  void debug(String message, [Map<String, dynamic>? data]) {
    service.log(Level.debug, module, message, data: data);
  }

  /// Info level logs (general info).
  void info(String message, [Map<String, dynamic>? data]) {
    service.log(Level.info, module, message, data: data);
  }

  /// Warning level logs.
  void warning(String message, [Map<String, dynamic>? data]) {
    service.log(Level.warning, module, message, data: data);
  }

  /// Error level logs.
  void error(
    String message, [
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
  ]) {
    service.log(
      Level.error,
      module,
      message,
      error: error,
      stackTrace: stackTrace,
      data: data,
    );
  }

  /// Fatal level logs.
  void fatal(
    String message, [
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
  ]) {
    service.log(
      Level.fatal,
      module,
      message,
      error: error,
      stackTrace: stackTrace,
      data: data,
    );
  }

  /// Measure operation duration.
  ///
  /// Returns the operation result and duration.
  Future<T> timed<T>(
    String operation,
    Future<T> Function() action, {
    Level level = Level.debug,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await action();
      stopwatch.stop();
      service.log(
        level,
        module,
        '$operation completed',
        data: {'duration_ms': stopwatch.elapsedMilliseconds},
      );
      return result;
    } on Object catch (e, st) {
      stopwatch.stop();
      service.log(
        Level.error,
        module,
        '$operation failed',
        error: e,
        stackTrace: st,
        data: {'duration_ms': stopwatch.elapsedMilliseconds},
      );
      rethrow;
    }
  }

  /// Measure operation duration synchronously.
  T timedSync<T>(
    String operation,
    T Function() action, {
    Level level = Level.debug,
  }) {
    final stopwatch = Stopwatch()..start();
    try {
      final result = action();
      stopwatch.stop();
      service.log(
        level,
        module,
        '$operation completed',
        data: {'duration_ms': stopwatch.elapsedMilliseconds},
      );
      return result;
    } on Object catch (e, st) {
      stopwatch.stop();
      service.log(
        Level.error,
        module,
        '$operation failed',
        error: e,
        stackTrace: st,
        data: {'duration_ms': stopwatch.elapsedMilliseconds},
      );
      rethrow;
    }
  }
}

/// No-op logging service (for tests or disabled logging).
class NoOpLogService extends LogService {
  NoOpLogService() : super(config: LogConfig.silent);

  @override
  void log(
    Level level,
    LogModule module,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
  }) {
    // Do nothing.
  }
}
