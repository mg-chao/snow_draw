import 'package:meta/meta.dart';

import 'event_bus.dart';
import 'event_payload_freezer.dart';

/// Error event.
@immutable
class ErrorEvent extends DrawEvent {
  const ErrorEvent({
    required this.message,
    required this.error,
    this.stackTrace,
  });
  final String message;
  final Object error;
  final StackTrace? stackTrace;

  @override
  String toString() => 'ErrorEvent(message: $message, error: $error)';
}

/// Validation failure event.
@immutable
class ValidationFailedEvent extends DrawEvent {
  ValidationFailedEvent({
    required this.action,
    required this.reason,
    Map<String, dynamic> details = const {},
  }) : details = freezeEventPayloadMap(details);
  final String action;
  final String reason;
  final Map<String, dynamic> details;

  @override
  String toString() =>
      'ValidationFailedEvent(action: $action, reason: $reason)';
}
