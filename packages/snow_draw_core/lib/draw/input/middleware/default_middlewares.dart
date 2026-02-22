import '../../services/log/log_service.dart';
import '../input_event.dart';
import 'input_middleware.dart';

final ModuleLogger _inputFallbackLog = LogService.fallback.input;
const _slowEventThreshold = Duration(milliseconds: 16);

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
    final eventType = event.runtimeType.toString();

    if (verbose) {
      log.trace('Input event', {
        'type': eventType,
        'position': event.position,
        'modifiers': event.modifiers.toString(),
        'isEditing': context.state.application.isEditing,
        'isCreating': context.state.application.isCreating,
        'hasSelection': context.state.domain.hasSelection,
      });
    } else {
      log.debug('Input event', {'type': eventType});
    }

    final result = await next(event);

    if (verbose && result != null) {
      log.debug('Input event processed', {'type': eventType});
    }

    return result;
  }
}

/// Event filter middleware.
///
/// Filters events based on a predicate.
class EventFilterMiddleware extends InputMiddlewareBase {
  const EventFilterMiddleware({required this.predicate})
    : super(name: 'EventFilter');

  final bool Function(InputEvent event, MiddlewareContext context) predicate;

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async {
    if (!predicate(event, context)) {
      return null;
    }
    return next(event);
  }
}

/// Throttle middleware.
///
/// Limits event handling frequency (mostly for PointerMove).
class ThrottleMiddleware extends InputMiddlewareBase {
  ThrottleMiddleware({required this.duration, Set<Type>? throttledEventTypes})
    : _throttledEventTypes = throttledEventTypes ?? {PointerMoveInputEvent},
      super(name: 'Throttle');
  final Duration duration;
  final Map<Type, DateTime> _lastProcessTimes = {};
  final Set<Type> _throttledEventTypes;

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async {
    final eventType = event.runtimeType;
    if (!_throttledEventTypes.contains(eventType)) {
      return next(event);
    }

    final now = DateTime.now();
    final lastTime = _lastProcessTimes[eventType];

    if (lastTime != null && now.difference(lastTime) < duration) {
      return null;
    }

    _lastProcessTimes[eventType] = now;
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
    final duration = stopwatch.elapsed;
    final eventType = event.runtimeType.toString();

    onMeasure?.call(eventType, duration);
    if (onMeasure == null && duration > _slowEventThreshold) {
      (context.log ?? _inputFallbackLog).warning('Slow input event', {
        'type': eventType,
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
    final position = event.position;
    if (!position.x.isFinite || !position.y.isFinite) {
      (context.log ?? _inputFallbackLog).warning('Invalid input position', {
        'position': position,
      });
      return null;
    }

    return next(event);
  }
}
