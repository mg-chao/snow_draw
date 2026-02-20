import 'package:meta/meta.dart';

import '../edit/core/edit_cancel_reason.dart';
import '../models/edit_session_id.dart';
import '../types/edit_operation_id.dart';
import 'event_bus.dart';

/// Base class for edit events.
@immutable
abstract class EditEvent extends DrawEvent {
  const EditEvent();
}

@immutable
abstract class _EditSessionEvent extends EditEvent {
  const _EditSessionEvent({required this.sessionId, required this.operationId});

  final EditSessionId sessionId;
  final EditOperationId operationId;

  String get eventName;

  @override
  String toString() =>
      '$eventName(session: $sessionId, operation: $operationId)';
}

/// Edit session started event.
@immutable
class EditSessionStartedEvent extends _EditSessionEvent {
  const EditSessionStartedEvent({
    required super.sessionId,
    required super.operationId,
  });

  @override
  String get eventName => 'EditSessionStarted';
}

/// Edit session updated event.
@immutable
class EditSessionUpdatedEvent extends _EditSessionEvent {
  const EditSessionUpdatedEvent({
    required super.sessionId,
    required super.operationId,
  });

  @override
  String get eventName => 'EditSessionUpdated';
}

/// Edit session finished event.
@immutable
class EditSessionFinishedEvent extends _EditSessionEvent {
  const EditSessionFinishedEvent({
    required super.sessionId,
    required super.operationId,
  });

  @override
  String get eventName => 'EditSessionFinished';
}

/// Edit session cancelled event.
@immutable
class EditSessionCancelledEvent extends _EditSessionEvent {
  const EditSessionCancelledEvent({
    required super.sessionId,
    required super.operationId,
    required this.reason,
  });

  final EditCancelReason reason;

  @override
  String get eventName => 'EditSessionCancelled';

  @override
  String toString() =>
      'EditSessionCancelled(session: $sessionId, reason: $reason)';
}
