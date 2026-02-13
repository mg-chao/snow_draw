import 'dart:async';

import 'package:logger/logger.dart';

/// Log record interface.
///
/// Used to collect log history or send logs to external services.
abstract class LogRecord {
  DateTime get timestamp;
  Level get level;
  String get module;
  String get message;
  Object? get error;
  StackTrace? get stackTrace;
}

/// Default log record implementation.
class DefaultLogRecord implements LogRecord {
  const DefaultLogRecord({
    required this.timestamp,
    required this.level,
    required this.module,
    required this.message,
    this.error,
    this.stackTrace,
  });
  @override
  final DateTime timestamp;
  @override
  final Level level;
  @override
  final String module;
  @override
  final String message;
  @override
  final Object? error;
  @override
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write('[$level] [$module] $message')
      ..write(error == null ? '' : ' - Error: $error');
    return buffer.toString();
  }
}

/// Log output interface.
///
/// Implement to customize log output (files, network, and so on).
abstract interface class LogOutputHandler {
  /// Output a log.
  void output(LogRecord record);

  /// Output logs in batch.
  void outputBatch(List<LogRecord> records) {
    for (final record in records) {
      output(record);
    }
  }

  /// Close the output.
  void close();
}

/// In-memory log collector.
///
/// Keeps recent log records in memory for debugging and diagnostics.
class MemoryLogCollector implements LogOutputHandler {
  MemoryLogCollector({this.maxRecords = 1000});
  final int maxRecords;
  final List<LogRecord> _records = [];

  /// Get all log records.
  List<LogRecord> get records => List.unmodifiable(_records);

  /// Get the most recent n records.
  List<LogRecord> getRecent(int count) {
    if (count >= _records.length) {
      return records;
    }
    return _records.sublist(_records.length - count);
  }

  /// Filter records by level.
  List<LogRecord> filterByLevel(Level minLevel) =>
      _records.where((r) => r.level.index >= minLevel.index).toList();

  /// Filter records by module.
  List<LogRecord> filterByModule(String module) =>
      _records.where((r) => r.module == module).toList();

  /// Clear records.
  void clear() {
    _records.clear();
  }

  @override
  void output(LogRecord record) {
    _records.add(record);
    if (_records.length > maxRecords) {
      _trimExcess();
    }
  }

  /// Removes oldest records when the buffer exceeds capacity.
  ///
  /// Uses [removeRange] for O(1) bulk removal instead of repeated
  /// [removeAt(0)] which is O(n) per call.
  void _trimExcess() {
    final excess = _records.length - maxRecords;
    if (excess > 0) {
      _records.removeRange(0, excess);
    }
  }

  @override
  void outputBatch(List<LogRecord> records) {
    for (final record in records) {
      output(record);
    }
  }

  @override
  void close() {
    // The in-memory collector needs no special close handling.
  }
}

/// Log stream output.
///
/// Publishes logs as a stream for UI display or other subscribers.
class StreamLogOutput implements LogOutputHandler {
  final _controller = StreamController<LogRecord>.broadcast();

  /// Log stream.
  Stream<LogRecord> get stream => _controller.stream;

  @override
  void output(LogRecord record) {
    if (!_controller.isClosed) {
      _controller.add(record);
    }
  }

  @override
  void outputBatch(List<LogRecord> records) {
    for (final record in records) {
      output(record);
    }
  }

  @override
  void close() {
    unawaited(_controller.close());
  }
}

/// Composite log output.
///
/// Sends logs to multiple output handlers.
class CompositeLogOutput implements LogOutputHandler {
  CompositeLogOutput(this.handlers);
  final List<LogOutputHandler> handlers;

  @override
  void output(LogRecord record) {
    for (final handler in handlers) {
      try {
        handler.output(record);
      } on Object catch (_) {
        // Ignore one handler's error to keep others working.
      }
    }
  }

  @override
  void outputBatch(List<LogRecord> records) {
    for (final handler in handlers) {
      try {
        handler.outputBatch(records);
      } on Object catch (_) {
        // Ignore a handler error.
      }
    }
  }

  @override
  void close() {
    for (final handler in handlers) {
      try {
        handler.close();
      } on Object catch (_) {
        // Ignore close errors.
      }
    }
  }
}
