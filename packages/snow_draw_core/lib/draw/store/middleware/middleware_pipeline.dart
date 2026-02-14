import 'dart:async';

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
    return _executeFromIndex(
      context: initialContext,
      index: 0,
      pipelineMiddlewares: middlewares,
      middlewareCount: middlewares.length,
    );
  }

  Future<DispatchContext> _executeFromIndex({
    required DispatchContext context,
    required int index,
    required List<Middleware> pipelineMiddlewares,
    required int middlewareCount,
  }) async {
    var currentContext = context;
    var currentIndex = index;

    while (true) {
      if (currentContext.shouldStop || currentContext.hasError) {
        return currentContext;
      }

      if (currentIndex >= middlewareCount) {
        return currentContext;
      }

      final middleware = pipelineMiddlewares[currentIndex];

      bool shouldExecute;
      try {
        shouldExecute = middleware.shouldExecute(currentContext);
      } on Object catch (error, stackTrace) {
        final recovered = _recoverFromError(
          context: currentContext,
          middleware: middleware,
          error: error,
          stackTrace: stackTrace,
        );
        if (recovered.shouldStop || recovered.hasError) {
          return recovered;
        }
        currentContext = recovered;
        currentIndex += 1;
        continue;
      }

      if (!shouldExecute) {
        currentIndex += 1;
        continue;
      }

      var nextCalled = false;
      var middlewareCompleted = false;
      var nextSettled = false;
      var nextObserved = false;
      DispatchContext? nextInputContext;
      Future<DispatchContext>? nextFuture;
      Future<DispatchContext> guardedNext(DispatchContext nextContext) {
        if (middlewareCompleted) {
          throw StateError(
            'Middleware "${middleware.name}" called next() after completion',
          );
        }
        if (nextCalled) {
          throw StateError(
            'Middleware "${middleware.name}" called next() more than once',
          );
        }
        nextCalled = true;
        nextInputContext = nextContext;
        final downstreamFuture = _executeFromIndex(
          context: nextContext,
          index: currentIndex + 1,
          pipelineMiddlewares: pipelineMiddlewares,
          middlewareCount: middlewareCount,
        ).whenComplete(() => nextSettled = true);
        nextFuture = downstreamFuture;
        return _ObservedFuture<DispatchContext>(
          downstreamFuture,
          onObserved: () => nextObserved = true,
        );
      }

      try {
        final result = await middleware.invoke(currentContext, guardedNext);
        middlewareCompleted = true;
        if (nextCalled && (!nextObserved || !nextSettled)) {
          final downstreamContext = await _resolveDownstreamContext(
            fallbackContext: nextInputContext ?? currentContext,
            middleware: middleware,
            downstreamFuture: nextFuture,
          );
          final detachedNextError = !nextObserved
              ? StateError(
                  'Middleware "${middleware.name}" called next() without '
                  'awaiting or returning it. Return or await next() to '
                  'keep pipeline order.',
                )
              : StateError(
                  'Middleware "${middleware.name}" completed before next() '
                  'finished. Return or await next() to keep pipeline order.',
                );
          return _recoverFromError(
            context: downstreamContext,
            middleware: middleware,
            error: detachedNextError,
            stackTrace: StackTrace.current,
          );
        }
        return result;
      } on Object catch (error, stackTrace) {
        middlewareCompleted = true;
        switch (errorHandler.handle(error, stackTrace)) {
          case RecoveryAction.skip:
            if (nextCalled) {
              final downstreamContext = await _resolveDownstreamContext(
                fallbackContext: nextInputContext ?? currentContext,
                middleware: middleware,
                downstreamFuture: nextFuture,
              );
              return _markSkipped(
                context: downstreamContext,
                middleware: middleware,
              );
            }
            currentContext = _markSkipped(
              context: currentContext,
              middleware: middleware,
            );
            currentIndex += 1;
            continue;
          case RecoveryAction.stop:
            final contextForStop = nextCalled
                ? await _resolveDownstreamContext(
                    fallbackContext: nextInputContext ?? currentContext,
                    middleware: middleware,
                    downstreamFuture: nextFuture,
                  )
                : currentContext;
            return contextForStop.withError(
              error,
              stackTrace,
              source: middleware.name,
            );
          case RecoveryAction.propagate:
            Error.throwWithStackTrace(error, stackTrace);
        }
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
