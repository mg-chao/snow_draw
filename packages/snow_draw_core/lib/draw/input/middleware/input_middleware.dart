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
    return _executeAtIndex(event: event, context: context, middlewareIndex: 0);
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

  Future<InputEvent?> _executeAtIndex({
    required InputEvent event,
    required MiddlewareContext context,
    required int middlewareIndex,
  }) async {
    if (middlewareIndex >= middlewares.length) {
      return event;
    }

    final middleware = middlewares[middlewareIndex];
    var nextCalled = false;

    Future<InputEvent?> guardedNext(InputEvent nextEvent) {
      if (nextCalled) {
        throw StateError(
          'Input middleware "${middleware.name}" called next() more than once',
        );
      }
      nextCalled = true;
      final completer = Completer<InputEvent?>();
      unawaited(() async {
        try {
          completer.complete(
            await _executeAtIndex(
              event: nextEvent,
              context: context,
              middlewareIndex: middlewareIndex + 1,
            ),
          );
        } on Object catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      }());
      return completer.future;
    }

    try {
      return await middleware.process(event, context, guardedNext);
    } on Object catch (error, stackTrace) {
      _logMiddlewareFailure(
        context: context,
        middleware: middleware,
        event: event,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
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
