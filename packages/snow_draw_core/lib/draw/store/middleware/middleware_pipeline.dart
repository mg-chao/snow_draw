import 'package:meta/meta.dart';

import 'error_handling.dart';
import 'middleware_base.dart';
import 'middleware_context.dart';

/// Main middleware pipeline orchestrator.
///
/// Executes middlewares in sequence with:
/// - Conditional execution (via shouldExecute)
/// - Basic error handling
@immutable
class MiddlewarePipeline {
  MiddlewarePipeline({
    required List<Middleware> middlewares,
    this.errorHandler = const ErrorHandler(),
  }) : middlewares = List<Middleware>.unmodifiable(middlewares);
  final List<Middleware> middlewares;
  final ErrorHandler errorHandler;

  /// Execute the pipeline with the given initial context.
  ///
  /// Returns the final context after all middlewares have executed.
  Future<DispatchContext> execute(DispatchContext initialContext) {
    if (initialContext.shouldStop ||
        initialContext.hasError ||
        middlewares.isEmpty) {
      return Future<DispatchContext>.value(initialContext);
    }
    return _executeFromIndex(context: initialContext, index: 0);
  }

  Future<DispatchContext> _executeFromIndex({
    required DispatchContext context,
    required int index,
  }) async {
    if (index >= middlewares.length || context.shouldStop || context.hasError) {
      return context;
    }

    final middleware = middlewares[index];

    bool shouldExecute;
    try {
      shouldExecute = middleware.shouldExecute(context);
    } on Object catch (error, stackTrace) {
      final recovered = _recoverFromError(
        context: context,
        middleware: middleware,
        error: error,
        stackTrace: stackTrace,
      );
      if (recovered.shouldStop || recovered.hasError) {
        return recovered;
      }
      return _executeFromIndex(context: recovered, index: index + 1);
    }

    if (!shouldExecute) {
      return _executeFromIndex(context: context, index: index + 1);
    }

    return _invokeMiddleware(
      context: context,
      index: index,
      middleware: middleware,
    );
  }

  Future<DispatchContext> _invokeMiddleware({
    required DispatchContext context,
    required int index,
    required Middleware middleware,
  }) async {
    var nextCalled = false;
    DispatchContext? nextInputContext;
    Future<DispatchContext>? downstreamFuture;

    Future<DispatchContext> guardedNext(DispatchContext nextContext) {
      if (nextCalled) {
        throw StateError(
          'Middleware "${middleware.name}" called next() more than once',
        );
      }
      nextCalled = true;
      nextInputContext = nextContext;
      final future = _executeFromIndex(context: nextContext, index: index + 1);
      downstreamFuture = future;
      return future;
    }

    try {
      return await middleware.invoke(context, guardedNext);
    } on Object catch (error, stackTrace) {
      final recovery = errorHandler.handle(error, stackTrace);
      final downstreamContext = await _resolveDownstreamContext(
        fallbackContext: nextInputContext ?? context,
        middleware: middleware,
        downstreamFuture: downstreamFuture,
      );

      switch (recovery) {
        case RecoveryAction.skip:
          final skipped = _markSkipped(
            context: downstreamContext,
            middleware: middleware,
          );
          return (nextCalled || skipped.shouldStop || skipped.hasError)
              ? skipped
              : _executeFromIndex(context: skipped, index: index + 1);
        case RecoveryAction.stop:
          return downstreamContext.withError(
            error,
            stackTrace,
            source: middleware.name,
          );
        case RecoveryAction.propagate:
          Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  Future<DispatchContext> _resolveDownstreamContext({
    required DispatchContext fallbackContext,
    required Middleware middleware,
    required Future<DispatchContext>? downstreamFuture,
  }) async {
    if (downstreamFuture == null) {
      return fallbackContext;
    }

    try {
      return await downstreamFuture;
    } on Object catch (error, stackTrace) {
      return _recoverFromError(
        context: fallbackContext,
        middleware: middleware,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  DispatchContext _recoverFromError({
    required DispatchContext context,
    required Middleware middleware,
    required Object error,
    required StackTrace stackTrace,
  }) {
    switch (errorHandler.handle(error, stackTrace)) {
      case RecoveryAction.skip:
        return _markSkipped(context: context, middleware: middleware);
      case RecoveryAction.stop:
        return context.withError(error, stackTrace, source: middleware.name);
      case RecoveryAction.propagate:
        Error.throwWithStackTrace(error, stackTrace);
    }
  }

  DispatchContext _markSkipped({
    required DispatchContext context,
    required Middleware middleware,
  }) => context.withMetadata('skipped_${middleware.name}', true);

  /// Create a new pipeline with an additional middleware.
  MiddlewarePipeline addMiddleware(Middleware middleware) => MiddlewarePipeline(
    middlewares: [...middlewares, middleware],
    errorHandler: errorHandler,
  );

  /// Create a new pipeline with a middleware prepended.
  MiddlewarePipeline prependMiddleware(Middleware middleware) =>
      MiddlewarePipeline(
        middlewares: [middleware, ...middlewares],
        errorHandler: errorHandler,
      );

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
    return MiddlewarePipeline(middlewares: sorted, errorHandler: errorHandler);
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
