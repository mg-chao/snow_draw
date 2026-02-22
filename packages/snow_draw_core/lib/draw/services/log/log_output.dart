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
    final errorText = error == null ? '' : ' - Error: $error';
    return '[$level] [$module] $message$errorText';
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
  MemoryLogCollector({this.maxRecords = 1000})
    : assert(maxRecords >= 0, 'maxRecords must be non-negative');
  final int maxRecords;
  final List<LogRecord> _records = [];

  /// Get all log records.
  List<LogRecord> get records => List.unmodifiable(_records);

  /// Get the most recent n records.
  List<LogRecord> getRecent(int count) {
    if (count <= 0) {
      return const [];
    }
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
    _trimExcess();
  }

  /// Removes oldest records when the buffer exceeds capacity.
  ///
  /// Uses a single [List.removeRange] call so trimming shifts list contents
  /// once instead of repeatedly calling `removeAt(0)`.
  void _trimExcess() {
    final excess = _records.length - maxRecords;
    if (excess <= 0) {
      return;
    }
    _records.removeRange(0, excess);
  }

  @override
  void outputBatch(List<LogRecord> records) {
    _records.addAll(records);
    _trimExcess();
  }

  @override
  void close() {
    // The in-memory collector needs no special close handling.
  }
}
