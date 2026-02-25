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
  /// 2. InterceptionMiddleware (priority: 900, optional)
  /// 3. ReductionMiddleware (priority: 500)
  /// 4. HistoryMiddleware (priority: 400)
  MiddlewarePipeline createDefault({
    List<ActionInterceptor> interceptors = const [],
  }) => createCustom(
    middlewares: _defaultMiddlewares(interceptors: interceptors),
  );

  /// Create a pipeline by extending the default middleware chain.
  MiddlewarePipeline extendDefault({
    List<Middleware> additionalMiddlewares = const [],
    List<ActionInterceptor> interceptors = const [],
  }) => createCustom(
    middlewares: <Middleware>[
      ..._defaultMiddlewares(interceptors: interceptors),
      ...additionalMiddlewares,
    ],
  );

  /// Create a minimal pipeline with only essential middlewares.
  MiddlewarePipeline createMinimal() =>
      createCustom(middlewares: const <Middleware>[ReductionMiddleware()]);

  /// Create a custom pipeline with specific middlewares.
  MiddlewarePipeline createCustom({required List<Middleware> middlewares}) =>
      MiddlewarePipeline(middlewares: middlewares).sortByPriority();

  List<Middleware> _defaultMiddlewares({
    required List<ActionInterceptor> interceptors,
  }) => <Middleware>[
    const ValidationMiddleware(),
    if (interceptors.isNotEmpty)
      InterceptionMiddleware(interceptors: interceptors),
    const ReductionMiddleware(),
    const HistoryMiddleware(),
  ];
}

const middlewarePipelineFactory = MiddlewarePipelineFactory();
