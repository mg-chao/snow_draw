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

/// Edit session started event.
@immutable
class EditSessionStartedEvent extends EditEvent {
  const EditSessionStartedEvent({
    required this.sessionId,
    required this.operationId,
  });
  final EditSessionId sessionId;
  final EditOperationId operationId;

  @override
  String toString() =>
      'EditSessionStarted(session: $sessionId, operation: $operationId)';
}

/// Edit session updated event.
@immutable
class EditSessionUpdatedEvent extends EditEvent {
  const EditSessionUpdatedEvent({
    required this.sessionId,
    required this.operationId,
  });
  final EditSessionId sessionId;
  final EditOperationId operationId;

  @override
  String toString() =>
      'EditSessionUpdated(session: $sessionId, operation: $operationId)';
}

/// Edit session finished event.
@immutable
class EditSessionFinishedEvent extends EditEvent {
  const EditSessionFinishedEvent({
    required this.sessionId,
    required this.operationId,
  });
  final EditSessionId sessionId;
  final EditOperationId operationId;

  @override
  String toString() =>
      'EditSessionFinished(session: $sessionId, operation: $operationId)';
}

/// Edit session cancelled event.
@immutable
class EditSessionCancelledEvent extends EditEvent {
  const EditSessionCancelledEvent({
    required this.sessionId,
    required this.operationId,
    required this.reason,
  });
  final EditSessionId sessionId;
  final EditOperationId operationId;
  final EditCancelReason reason;

  @override
  String toString() =>
      'EditSessionCancelled(session: $sessionId, reason: $reason)';
}


