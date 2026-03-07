import 'package:meta/meta.dart';

/// Error context information for debugging and tracking.
@immutable
class ErrorContext {
  ErrorContext({
    required this.operationName,
    this.metadata = const <String, dynamic>{},
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
  }) {
    final nextMetadata =
        additionalMetadata == null || additionalMetadata.isEmpty
        ? metadata
        : {...metadata, ...additionalMetadata};

    return ErrorContext(
      operationName: operationName ?? this.operationName,
      metadata: nextMetadata,
      timestamp: timestamp ?? this.timestamp,
      stackTrace: stackTrace ?? this.stackTrace,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer()
      ..writeln('ErrorContext:')
      ..writeln('  Operation: $operationName')
      ..writeln('  Timestamp: $timestamp');

    if (metadata.isEmpty) {
      return buffer.toString();
    }

    buffer.writeln('  Metadata:');
    for (final entry in metadata.entries) {
      buffer.writeln('    ${entry.key}: ${entry.value}');
    }

    return buffer.toString();
  }
}
