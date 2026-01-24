import '../../core/app_error.dart';

/// Error thrown when history recording fails.
class HistoryRecordingError extends AppErrorBase {
  const HistoryRecordingError({required this.action, this.cause});
  final String action;
  @override
  final Object? cause;

  @override
  ErrorSeverity get severity => ErrorSeverity.degradable;

  @override
  String toString() => 'HistoryRecordingError(action: $action, cause: $cause)';
}
