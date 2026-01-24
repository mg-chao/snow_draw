import 'package:meta/meta.dart';
import 'middleware_context.dart';

/// Next function type - calls the next middleware in the chain
typedef NextFunction =
    Future<DispatchContext> Function(DispatchContext context);

/// Modern middleware interface (ASP.NET Core style)
///
/// A middleware is a component that:
/// 1. Receives a context and a next function
/// 2. Can inspect/modify the context
/// 3. Decides whether to call next(context) to continue the chain
/// 4. Can handle errors and implement recovery logic
///
/// Example:
/// ```dart
/// class ExampleMiddleware extends MiddlewareBase {
///   @override
///   Future<DispatchContext> invoke(
///     DispatchContext context,
///     NextFunction next,
///   ) async {
///     print('Before: ${context.action}');
///     final updated = await next(context);
///     print('After: ${updated.currentState}');
///     return updated;
///   }
/// }
/// ```
@immutable
abstract interface class Middleware {
  /// Execute this middleware.
  ///
  /// Call [next] to pass control to the next middleware.
  /// Don't call [next] to short-circuit the pipeline.
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next);

  /// Optional: Check if this middleware should execute
  ///
  /// Return false to skip this middleware entirely.
  /// This enables conditional middleware execution.
  bool shouldExecute(DispatchContext context) => true;

  /// Optional: Priority for ordering (higher = earlier)
  ///
  /// Middlewares are sorted by priority before execution.
  /// Default is 0. Use negative values for late execution.
  int get priority => 0;

  /// Optional: Name for debugging and logging
  String get name => runtimeType.toString();
}

/// Base class for middleware with common functionality
abstract class MiddlewareBase implements Middleware {
  const MiddlewareBase();

  @override
  bool shouldExecute(DispatchContext context) => true;

  @override
  int get priority => 0;

  @override
  String get name => runtimeType.toString();
}
