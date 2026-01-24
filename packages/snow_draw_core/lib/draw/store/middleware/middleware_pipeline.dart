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
  const MiddlewarePipeline({
    required this.middlewares,
    this.errorHandler = const ErrorHandler(),
  });
  final List<Middleware> middlewares;
  final ErrorHandler errorHandler;

  /// Execute the pipeline with the given initial context.
  ///
  /// Returns the final context after all middlewares have executed.
  Future<DispatchContext> execute(DispatchContext initialContext) {
    Future<DispatchContext> executeNext(
      DispatchContext context,
      int index,
    ) async {
      if (context.shouldStop || context.hasError) {
        return context;
      }

      if (index >= middlewares.length) {
        return context;
      }

      final middleware = middlewares[index];
      if (!middleware.shouldExecute(context)) {
        return executeNext(context, index + 1);
      }

      try {
        return await middleware.invoke(
          context,
          (nextContext) => executeNext(nextContext, index + 1),
        );
      } on Object catch (error, stackTrace) {
        switch (errorHandler.handle(error, stackTrace)) {
          case RecoveryAction.skip:
            final skipped = context.withMetadata(
              'skipped_${middleware.name}',
              true,
            );
            return executeNext(skipped, index + 1);
          case RecoveryAction.stop:
            return context.withError(
              error,
              stackTrace,
              source: middleware.name,
            );
          case RecoveryAction.propagate:
            Error.throwWithStackTrace(error, stackTrace);
        }
      }
    }

    return executeNext(initialContext, 0);
  }

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

  /// Create a new pipeline with middlewares sorted by priority.
  MiddlewarePipeline sortByPriority() {
    final sorted = [...middlewares]
      ..sort((a, b) => b.priority.compareTo(a.priority));
    return MiddlewarePipeline(middlewares: sorted, errorHandler: errorHandler);
  }

  /// Get the number of middlewares.
  int get length => middlewares.length;

  /// Check if pipeline is empty.
  bool get isEmpty => middlewares.isEmpty;

  /// Check if pipeline is not empty.
  bool get isNotEmpty => middlewares.isNotEmpty;
}
