import 'package:meta/meta.dart';
import 'middleware_context.dart';

/// Callback that advances middleware execution to the next step.
typedef NextFunction =
    Future<DispatchContext> Function(DispatchContext context);

/// Middleware contract for the dispatch pipeline.
@immutable
abstract interface class Middleware {
  /// Executes middleware logic for [context].
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next);

  /// Priority used for middleware ordering (higher runs first).
  ///
  /// Override to change ordering in the pipeline.
  int get priority => 0;

  /// Human-readable middleware name for logs and debugging.
  String get name => runtimeType.toString();
}

/// Base middleware that provides default optional behavior.
abstract class MiddlewareBase implements Middleware {
  const MiddlewareBase();

  @override
  int get priority => 0;

  @override
  String get name => runtimeType.toString();
}
