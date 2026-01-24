import 'package:meta/meta.dart';

/// Error context information for debugging and tracking.
@immutable
class ErrorContext {
  ErrorContext({
    required this.operationName,
    this.metadata = const {},
    DateTime? timestamp,
    this.stackTrace,
  }) : timestamp = timestamp ?? DateTime.now();
  final String operationName;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;
  final StackTrace? stackTrace;

  ErrorContext copyWith({
    String? operationName,
    Map<String, dynamic>? additionalMetadata,
    DateTime? timestamp,
    StackTrace? stackTrace,
  }) => ErrorContext(
    operationName: operationName ?? this.operationName,
    metadata: additionalMetadata != null
        ? {...metadata, ...additionalMetadata}
        : metadata,
    timestamp: timestamp ?? this.timestamp,
    stackTrace: stackTrace ?? this.stackTrace,
  );

  @override
  String toString() {
    final buffer = StringBuffer()
      ..writeln('ErrorContext:')
      ..writeln('  Operation: $operationName')
      ..writeln('  Timestamp: $timestamp');

    if (metadata.isNotEmpty) {
      buffer.writeln('  Metadata:');
      metadata.forEach((key, value) {
        buffer.writeln('    $key: $value');
      });
    }

    return buffer.toString();
  }
}
