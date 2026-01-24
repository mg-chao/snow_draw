import '../../services/log/log_service.dart';
import '../input_event.dart';
import 'input_middleware.dart';

final ModuleLogger _inputFallbackLog = LogService.fallback.input;

/// Logging middleware.
///
/// Records all input events for debugging.
class LoggingMiddleware extends InputMiddlewareBase {
  const LoggingMiddleware({this.verbose = false}) : super(name: 'Logging');
  final bool verbose;

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async {
    final log = context.log ?? _inputFallbackLog;
    if (verbose) {
      log.trace('Input event', {
        'type': event.runtimeType.toString(),
        'position': event.position,
        'modifiers': event.modifiers.toString(),
        'isEditing': context.state.application.isEditing,
        'isCreating': context.state.application.isCreating,
        'hasSelection': context.state.domain.hasSelection,
      });
    } else {
      log.debug('Input event', {'type': event.runtimeType.toString()});
    }

    final result = await next(event);

    if (verbose && result != null) {
      log.debug('Input event processed', {
        'type': event.runtimeType.toString(),
      });
    }

    return result;
  }
}

/// Event filter middleware.
///
/// Filters events based on a predicate.
class EventFilterMiddleware extends ConditionalMiddleware {
  const EventFilterMiddleware({required this.predicate})
    : super(name: 'EventFilter');
  final bool Function(InputEvent event, MiddlewareContext context) predicate;

  @override
  Future<bool> shouldProcess(
    InputEvent event,
    MiddlewareContext context,
  ) async => !predicate(event, context);

  @override
  Future<InputEvent?> processEvent(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async =>
      // If shouldProcess returns true, predicate failed and the event is
      // intercepted.
      null;
}

/// Throttle middleware.
///
/// Limits event handling frequency (mostly for PointerMove).
class ThrottleMiddleware extends InputMiddlewareBase {
  ThrottleMiddleware({required this.duration, Set<Type>? throttledEventTypes})
    : _throttledEventTypes = throttledEventTypes ?? {PointerMoveInputEvent},
      super(name: 'Throttle');
  final Duration duration;
  DateTime? _lastProcessTime;
  final Set<Type> _throttledEventTypes;

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async {
    // Throttle only specified event types.
    if (!_throttledEventTypes.contains(event.runtimeType)) {
      return next(event);
    }

    final now = DateTime.now();
    final lastTime = _lastProcessTime;

    if (lastTime != null && now.difference(lastTime) < duration) {
      // Skip this event.
      return event; // Return the original event without calling next.
    }

    _lastProcessTime = now;
    return next(event);
  }
}

/// Performance middleware.
///
/// Measures event processing time.
class PerformanceMiddleware extends InputMiddlewareBase {
  const PerformanceMiddleware({this.onMeasure}) : super(name: 'Performance');
  final void Function(String eventType, Duration duration)? onMeasure;

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async {
    final stopwatch = Stopwatch()..start();

    final result = await next(event);

    stopwatch.stop();
    final duration = stopwatch.elapsed;

    onMeasure?.call(event.runtimeType.toString(), duration);
    if (onMeasure == null && duration.inMilliseconds > 16) {
      // Longer than one frame, log a warning.
      (context.log ?? _inputFallbackLog).warning('Slow input event', {
        'type': event.runtimeType.toString(),
        'duration_ms': duration.inMilliseconds,
      });
    }

    return result;
  }
}

/// Event validation middleware.
///
/// Validates event data.
class ValidationMiddleware extends InputMiddlewareBase {
  const ValidationMiddleware() : super(name: 'Validation');

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async {
    // Validate the position.
    if (event.position.x.isNaN || event.position.y.isNaN) {
      (context.log ?? _inputFallbackLog).warning('Invalid input position', {
        'position': event.position,
      });
      return null; // Intercept invalid event.
    }

    if (event.position.x.isInfinite || event.position.y.isInfinite) {
      (context.log ?? _inputFallbackLog).warning('Infinite input position', {
        'position': event.position,
      });
      return null;
    }

    return next(event);
  }
}

/// State snapshot middleware.
///
/// Captures state snapshots before and after events for debugging.
class StateSnapshotMiddleware extends InputMiddlewareBase {
  const StateSnapshotMiddleware({this.onSnapshot})
    : super(name: 'StateSnapshot');
  final void Function(
    String eventType,
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  )?
  onSnapshot;

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async {
    final before = _captureState(context);

    final result = await next(event);

    final after = _captureState(context);

    onSnapshot?.call(event.runtimeType.toString(), before, after);

    return result;
  }

  Map<String, dynamic> _captureState(MiddlewareContext context) {
    final state = context.state;
    return {
      'isEditing': state.application.isEditing,
      'isCreating': state.application.isCreating,
      'isBoxSelecting': state.application.isBoxSelecting,
      'hasSelection': state.domain.hasSelection,
      'selectedCount': state.domain.selection.selectedIds.length,
    };
  }
}
