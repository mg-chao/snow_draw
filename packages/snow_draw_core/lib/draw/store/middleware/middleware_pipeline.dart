import 'package:meta/meta.dart';

import 'middleware_base.dart';
import 'middleware_context.dart';

/// Main middleware pipeline orchestrator.
///
/// Executes middlewares in sequence with basic error handling.
@immutable
class MiddlewarePipeline {
  MiddlewarePipeline({required List<Middleware> middlewares})
    : middlewares = List<Middleware>.unmodifiable(middlewares);
  final List<Middleware> middlewares;

  /// Execute the pipeline with the given initial context.
  ///
  /// Returns the final context after all middlewares have executed.
  Future<DispatchContext> execute(DispatchContext initialContext) {
    if (middlewares.isEmpty || initialContext.isTerminal) {
      return Future<DispatchContext>.value(initialContext);
    }
    return _executeFromIndex(initialContext, 0);
  }

  Future<DispatchContext> _executeFromIndex(
    DispatchContext context,
    int index,
  ) async {
    if (index >= middlewares.length || context.isTerminal) {
      return context;
    }

    final middleware = middlewares[index];
    return _invokeMiddleware(context, index, middleware);
  }

  Future<DispatchContext> _invokeMiddleware(
    DispatchContext context,
    int index,
    Middleware middleware,
  ) async {
    var nextCalled = false;
    DispatchContext? downstreamContext;

    Future<DispatchContext> guardedNext(DispatchContext nextContext) async {
      if (nextCalled) {
        throw StateError(
          'Middleware "${middleware.name}" called next() more than once',
        );
      }
      nextCalled = true;
      downstreamContext = await _executeFromIndex(nextContext, index + 1);
      return downstreamContext!;
    }

    try {
      return await middleware.invoke(context, guardedNext);
    } on Object catch (error, stackTrace) {
      final baseContext = downstreamContext ?? context;
      return baseContext.withError(error, stackTrace, source: middleware.name);
    }
  }

  /// Create a new pipeline with an additional middleware.
  MiddlewarePipeline addMiddleware(Middleware middleware) =>
      MiddlewarePipeline(middlewares: [...middlewares, middleware]);

  /// Create a new pipeline with a middleware prepended.
  MiddlewarePipeline prependMiddleware(Middleware middleware) =>
      MiddlewarePipeline(middlewares: [middleware, ...middlewares]);

  /// Create a pipeline with middlewares sorted by priority.
  ///
  /// Returns this instance when middlewares are already sorted.
  MiddlewarePipeline sortByPriority() {
    if (_isSortedByPriority()) {
      return this;
    }

    final indexedMiddlewares = middlewares.indexed.toList()
      ..sort((left, right) {
        final byPriority = right.$2.priority.compareTo(left.$2.priority);
        if (byPriority != 0) {
          return byPriority;
        }
        return left.$1.compareTo(right.$1);
      });
    final sorted = [for (final entry in indexedMiddlewares) entry.$2];
    return MiddlewarePipeline(middlewares: sorted);
  }

  bool _isSortedByPriority() {
    if (middlewares.length < 2) {
      return true;
    }

    var previousPriority = middlewares.first.priority;
    for (var i = 1; i < middlewares.length; i++) {
      final currentPriority = middlewares[i].priority;
      if (previousPriority < currentPriority) {
        return false;
      }
      previousPriority = currentPriority;
    }
    return true;
  }

  /// Get the number of middlewares.
  int get length => middlewares.length;

  /// Check if pipeline is empty.
  bool get isEmpty => middlewares.isEmpty;

  /// Check if pipeline is not empty.
  bool get isNotEmpty => middlewares.isNotEmpty;
}
