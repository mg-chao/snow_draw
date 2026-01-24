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
  const InputPipeline({required this.middlewares});
  final List<InputMiddleware> middlewares;

  /// Execute the pipeline.
  ///
  /// Returns the processed event. A null return means the event was
  /// intercepted.
  Future<InputEvent?> execute(
    InputEvent event,
    MiddlewareContext context,
  ) async {
    if (middlewares.isEmpty) {
      return event;
    }

    var index = 0;

    Future<InputEvent?> next(InputEvent evt) async {
      if (index >= middlewares.length) {
        return evt; // All middleware has run.
      }

      final middleware = middlewares[index++];
      try {
        return await middleware.process(evt, context, next);
      } on Object catch (e, stackTrace) {
        // Middleware failed: log and stop the pipeline.
        (context.log ?? LogService.fallback.input).error(
          'Input middleware failed',
          e,
          stackTrace,
          {'middleware': middleware.name, 'event': evt.runtimeType.toString()},
        );
        return null; // Intercept the event.
      }
    }

    return next(event);
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
  static const empty = InputPipeline(middlewares: []);
}
