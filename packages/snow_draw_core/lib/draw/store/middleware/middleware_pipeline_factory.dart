import 'error_handling.dart';
import 'middleware_base.dart';
import 'middleware_pipeline.dart';
import 'middlewares/history_middleware.dart';
import 'middlewares/interception_middleware.dart';
import 'middlewares/reduction_middleware.dart';
import 'middlewares/validation_middleware.dart';

/// Factory for creating middleware pipelines.
class MiddlewarePipelineFactory {
  const MiddlewarePipelineFactory();

  /// Create the standard middleware pipeline with all middlewares.
  ///
  /// The middlewares are executed in priority order:
  /// 1. ValidationMiddleware (priority: 1000)
  /// 2. InterceptionMiddleware (priority: 900)
  /// 3. ReductionMiddleware (priority: 500)
  /// 4. HistoryMiddleware (priority: 400)
  MiddlewarePipeline createDefault({
    List<ActionInterceptor> interceptors = const [],
    ErrorHandler? errorHandler,
  }) {
    final middlewares = <Middleware>[
      ValidationMiddleware(),
      if (interceptors.isNotEmpty)
        InterceptionMiddleware(interceptors: interceptors),
      const ReductionMiddleware(),
      const HistoryMiddleware(),
    ];

    return MiddlewarePipeline(
      middlewares: middlewares,
      errorHandler: errorHandler ?? const ErrorHandler(),
    ).sortByPriority();
  }

  /// Create a pipeline by extending the default middleware chain.
  MiddlewarePipeline extendDefault({
    List<Middleware> additionalMiddlewares = const [],
    List<ActionInterceptor> interceptors = const [],
    ErrorHandler? errorHandler,
  }) {
    final basePipeline = createDefault(
      interceptors: interceptors,
      errorHandler: errorHandler,
    );

    if (additionalMiddlewares.isEmpty) {
      return basePipeline;
    }

    return MiddlewarePipeline(
      middlewares: [...basePipeline.middlewares, ...additionalMiddlewares],
      errorHandler: basePipeline.errorHandler,
    ).sortByPriority();
  }

  /// Create a minimal pipeline with only essential middlewares.
  MiddlewarePipeline createMinimal({ErrorHandler? errorHandler}) =>
      MiddlewarePipeline(
        middlewares: const [ReductionMiddleware()],
        errorHandler: errorHandler ?? const ErrorHandler(),
      );

  /// Create a custom pipeline with specific middlewares.
  MiddlewarePipeline createCustom({
    required List<Middleware> middlewares,
    ErrorHandler? errorHandler,
  }) => MiddlewarePipeline(
    middlewares: middlewares,
    errorHandler: errorHandler ?? const ErrorHandler(),
  ).sortByPriority();
}

const middlewarePipelineFactory = MiddlewarePipelineFactory();
