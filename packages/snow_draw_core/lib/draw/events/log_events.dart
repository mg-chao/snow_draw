import 'package:logger/logger.dart';
import 'package:meta/meta.dart';

import 'event_bus.dart';

/// Base class for log events.
///
/// Used to publish logs via the EventBus and support UI subscriptions.
@immutable
abstract class LogEvent extends DrawEvent {
  const LogEvent();

  /// Log level.
  Level get level;

  /// Log module.
  String get module;

  /// Log message.
  String get message;

  /// Log timestamp.
  DateTime get timestamp;
}

/// General log event.
@immutable
class GeneralLogEvent extends LogEvent {
  const GeneralLogEvent({
    required this.level,
    required this.module,
    required this.message,
    required this.timestamp,
    this.data,
  });
  @override
  final Level level;
  @override
  final String module;
  @override
  final String message;
  @override
  final DateTime timestamp;

  /// Additional data.
  final Map<String, dynamic>? data;

  @override
  String toString() =>
      'LogEvent(level: $level, module: $module, message: $message)';
}

/// Error log event.
@immutable
class ErrorLogEvent extends LogEvent {
  const ErrorLogEvent({
    required this.module,
    required this.message,
    required this.timestamp,
    required this.error,
    this.stackTrace,
    this.level = Level.error,
  });
  @override
  final Level level;
  @override
  final String module;
  @override
  final String message;
  @override
  final DateTime timestamp;

  /// Error object.
  final Object error;

  /// Stack trace.
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'ErrorLogEvent(module: $module, message: $message, error: $error)';
}

/// Performance log event.
@immutable
class PerformanceLogEvent extends LogEvent {
  const PerformanceLogEvent({
    required this.module,
    required this.message,
    required this.timestamp,
    required this.operation,
    required this.duration,
    this.success = true,
  });
  @override
  final String module;
  @override
  final String message;
  @override
  final DateTime timestamp;

  /// Operation name.
  final String operation;

  /// Execution duration.
  final Duration duration;

  /// Whether the operation succeeded.
  final bool success;

  @override
  Level get level => Level.debug;

  @override
  String toString() =>
      'PerformanceLogEvent('
      'operation: $operation, '
      'duration: ${duration.inMilliseconds}ms, '
      'success: $success)';
}

/// Pipeline execution log event.
@immutable
class PipelineLogEvent extends LogEvent {
  const PipelineLogEvent({
    required this.message,
    required this.timestamp,
    required this.actionType,
    this.stage,
    this.duration,
    this.hasError = false,
    this.stateChanged = false,
  });
  @override
  final String message;
  @override
  final DateTime timestamp;

  /// Action type.
  final String actionType;

  /// Pipeline stage.
  final String? stage;

  /// Execution duration.
  final Duration? duration;

  /// Whether there is an error.
  final bool hasError;

  /// Whether state changed.
  final bool stateChanged;

  @override
  Level get level => hasError ? Level.error : Level.debug;

  @override
  String get module => 'Pipeline';

  @override
  String toString() =>
      'PipelineLogEvent('
      'action: $actionType, '
      'stage: $stage, '
      'duration: ${duration?.inMilliseconds}ms)';
}
