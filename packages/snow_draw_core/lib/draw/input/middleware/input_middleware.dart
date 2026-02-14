import 'dart:async';

import 'package:meta/meta.dart';

import '../../models/draw_state.dart';
import '../../services/log/log_service.dart';
import '../input_event.dart';

/// Middleware context.
///
/// Provides context information required by middleware.
@immutable
class MiddlewareContext {
  const MiddlewareContext({
    required this.state,
    this.data = const {},
    this.log,
  });

  /// Current state.
  final DrawState state;

  final ModuleLogger? log;

  /// Custom data (for passing data between middleware).
  final Map<String, dynamic> data;

  /// Set data.
  MiddlewareContext setData(String key, dynamic value) {
    final newData = Map<String, dynamic>.from(data);
    newData[key] = value;
    return MiddlewareContext(state: state, data: newData, log: log);
  }

  /// Get data.
  T? getData<T>(String key) => data[key] as T?;

  /// Check whether data exists.
  bool hasData(String key) => data.containsKey(key);

  /// Create a copy.
  MiddlewareContext copyWith({
    DrawState? state,
    Map<String, dynamic>? data,
    ModuleLogger? log,
  }) => MiddlewareContext(
    state: state ?? this.state,
    data: data ?? this.data,
    log: log ?? this.log,
  );
}

/// Input middleware interface.
///
/// Middleware processes events before they reach plugins, such as:
/// - Coordinate transforms
/// - Event filtering
/// - Gesture recognition
/// - Logging
/// - Performance monitoring
/// - Event transformation
abstract interface class InputMiddleware {
  /// Middleware name (for debugging).
  String get name;

  /// Process an event.
  ///
  /// Args:
  /// - event: input event
  /// - context: middleware context
  /// - next: function to call the next middleware
  ///
  /// Returns:
  /// - The processed event (original, modified, or null)
  /// - Null indicates the event is intercepted and processing stops
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  );
}

/// Function type for the next middleware.
typedef NextMiddleware = Future<InputEvent?> Function(InputEvent event);

/// Base class for input middleware.
///
/// Provides default implementations and helpers.
abstract class InputMiddlewareBase implements InputMiddleware {
  const InputMiddlewareBase({required String name}) : _name = name;
  final String _name;

  @override
  String get name => _name;

  /// Helper: continue to the next middleware.
  @protected
  Future<InputEvent?> continueWith(InputEvent event, NextMiddleware next) =>
      next(event);

  /// Helper: intercept the event (stop processing).
  @protected
  Future<InputEvent?> intercept() async => null;
}

/// Simple middleware: implement transform only.
abstract class SimpleMiddleware extends InputMiddlewareBase {
  const SimpleMiddleware({required super.name});

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async {
    final transformed = await transform(event, context);
    if (transformed == null) {
      return null; // Intercept.
    }
    return next(transformed);
  }

  /// Transform the event.
  ///
  /// Returning null intercepts the event.
  Future<InputEvent?> transform(InputEvent event, MiddlewareContext context);
}

/// Conditional middleware: process based on a condition.
abstract class ConditionalMiddleware extends InputMiddlewareBase {
  const ConditionalMiddleware({required super.name});

  @override
  Future<InputEvent?> process(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  ) async {
    if (await shouldProcess(event, context)) {
      return processEvent(event, context, next);
    }
    return next(event);
  }

  /// Decide whether to process this event.
  Future<bool> shouldProcess(InputEvent event, MiddlewareContext context);

  /// Process the event.
  Future<InputEvent?> processEvent(
    InputEvent event,
    MiddlewareContext context,
    NextMiddleware next,
  );
}

/// Input pipeline.
///
/// Executes the middleware chain in order to handle input events.
class InputPipeline {
  InputPipeline({required List<InputMiddleware> middlewares})
    : middlewares = List<InputMiddleware>.unmodifiable(middlewares);

  final List<InputMiddleware> middlewares;

  /// Execute the pipeline.
  ///
  /// Returns the processed event. A null return means the event was
  /// intercepted.
  Future<InputEvent?> execute(InputEvent event, MiddlewareContext context) {
    if (middlewares.isEmpty) {
      return Future<InputEvent?>.value(event);
    }

    Future<InputEvent?> executeNext(
      InputEvent eventToProcess,
      int middlewareIndex,
    ) async {
      if (middlewareIndex >= middlewares.length) {
        return eventToProcess;
      }

      final middleware = middlewares[middlewareIndex];
      var nextCalled = false;
      var middlewareCompleted = false;
      var nextSettled = false;
      var nextObserved = false;
      InputEvent? nextInputEvent;
      Future<InputEvent?>? nextFuture;

      Future<InputEvent?> guardedNext(InputEvent nextEvent) {
        if (middlewareCompleted) {
          throw StateError(
            'Input middleware "${middleware.name}" called next() '
            'after completion',
          );
        }
        if (nextCalled) {
          throw StateError(
            'Input middleware "${middleware.name}" called next() '
            'more than once',
          );
        }

        nextCalled = true;
        nextInputEvent = nextEvent;
        final downstreamCompleter = Completer<InputEvent?>();
        unawaited(() async {
          try {
            final downstreamEvent = await Future<InputEvent?>.microtask(
              () => executeNext(nextEvent, middlewareIndex + 1),
            );
            if (!downstreamCompleter.isCompleted) {
              downstreamCompleter.complete(downstreamEvent);
            }
          } on Object catch (error, stackTrace) {
            if (!downstreamCompleter.isCompleted) {
              downstreamCompleter.completeError(error, stackTrace);
            }
          }
        }());
        final downstreamFuture = downstreamCompleter.future.whenComplete(
          () => nextSettled = true,
        );
        nextFuture = downstreamFuture;

        return _ObservedFuture<InputEvent?>(
          downstreamFuture,
          onObserved: () => nextObserved = true,
        );
      }

      try {
        final result = await middleware.process(
          eventToProcess,
          context,
          guardedNext,
        );
        middlewareCompleted = true;

        if (nextCalled && (!nextObserved || !nextSettled)) {
          await _awaitDownstream(
            context: context,
            middleware: middleware,
            fallbackEvent: nextInputEvent ?? eventToProcess,
            downstreamFuture: nextFuture,
          );

          _logMiddlewareFailure(
            context: context,
            middleware: middleware,
            event: eventToProcess,
            error: !nextObserved
                ? StateError(
                    'Input middleware "${middleware.name}" called next() '
                    'without awaiting or returning it. '
                    'Return or await next() to keep input order.',
                  )
                : StateError(
                    'Input middleware "${middleware.name}" completed '
                    'before next() finished. '
                    'Return or await next() to keep input order.',
                  ),
            stackTrace: StackTrace.current,
          );
          return null;
        }

        return result;
      } on Object catch (error, stackTrace) {
        middlewareCompleted = true;
        if (nextCalled) {
          await _awaitDownstream(
            context: context,
            middleware: middleware,
            fallbackEvent: nextInputEvent ?? eventToProcess,
            downstreamFuture: nextFuture,
          );
        }

        _logMiddlewareFailure(
          context: context,
          middleware: middleware,
          event: eventToProcess,
          error: error,
          stackTrace: stackTrace,
        );
        return null;
      }
    }

    return executeNext(event, 0);
  }

  /// Add middleware.
  InputPipeline addMiddleware(InputMiddleware middleware) =>
      InputPipeline(middlewares: [...middlewares, middleware]);

  /// Prepend middleware.
  InputPipeline prependMiddleware(InputMiddleware middleware) =>
      InputPipeline(middlewares: [middleware, ...middlewares]);

  /// Remove middleware.
  InputPipeline removeMiddleware(String name) => InputPipeline(
    middlewares: middlewares.where((m) => m.name != name).toList(),
  );

  /// Create an empty pipeline.
  static final empty = InputPipeline(middlewares: const []);

  Future<void> _awaitDownstream({
    required MiddlewareContext context,
    required InputMiddleware middleware,
    required InputEvent fallbackEvent,
    required Future<InputEvent?>? downstreamFuture,
  }) async {
    if (downstreamFuture == null) {
      return;
    }

    try {
      await downstreamFuture;
    } on Object catch (error, stackTrace) {
      _logMiddlewareFailure(
        context: context,
        middleware: middleware,
        event: fallbackEvent,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _logMiddlewareFailure({
    required MiddlewareContext context,
    required InputMiddleware middleware,
    required InputEvent event,
    required Object error,
    required StackTrace stackTrace,
  }) {
    (context.log ?? LogService.fallback.input).error(
      'Input middleware failed',
      error,
      stackTrace,
      {'middleware': middleware.name, 'event': event.runtimeType.toString()},
    );
  }
}

class _ObservedFuture<T> implements Future<T> {
  _ObservedFuture(this._delegate, {required void Function() onObserved})
    : _onObserved = onObserved;

  final Future<T> _delegate;
  final void Function() _onObserved;
  var _didObserve = false;

  void _markObserved() {
    if (_didObserve) {
      return;
    }
    _didObserve = true;
    _onObserved();
  }

  @override
  Stream<T> asStream() {
    _markObserved();
    return _delegate.asStream();
  }

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    _markObserved();
    return _delegate.catchError(onError, test: test);
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    _markObserved();
    return _delegate.then<R>(onValue, onError: onError);
  }

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) {
    _markObserved();
    return _delegate.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) {
    _markObserved();
    return _delegate.whenComplete(action);
  }
}
