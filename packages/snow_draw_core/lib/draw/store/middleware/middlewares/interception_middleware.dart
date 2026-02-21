import '../../../actions/draw_actions.dart';
import '../../../models/draw_state.dart';
import '../middleware_base.dart';
import '../middleware_context.dart';

/// Interception middleware that allows blocking actions before they're
/// processed.
///
/// Interceptors can examine the action and state, and decide whether
/// to allow the action to proceed.
///
/// Example:
/// ```dart
/// class MyInterceptor {
///   bool call(DrawState state, DrawAction action) {
///     // Block certain actions based on state
///     return true;
///   }
/// }
///
/// final middleware = InterceptionMiddleware(
///   interceptors: [MyInterceptor()],
/// );
/// ```
class InterceptionMiddleware extends MiddlewareBase {
  const InterceptionMiddleware({this.interceptors = const []});
  final List<ActionInterceptor> interceptors;

  @override
  String get name => 'Interception';

  @override
  int get priority => 900; // High priority - intercept early

  @override
  bool shouldExecute(DispatchContext context) => interceptors.isNotEmpty;

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) {
    for (final interceptor in interceptors) {
      if (!interceptor(context.currentState, context.action)) {
        // Block the action - don't call next(context)
        return Future<DispatchContext>.value(
          context.withStop('Action blocked by ${interceptor.runtimeType}'),
        );
      }
    }

    // All interceptors passed, continue
    return next(context);
  }
}

/// Action interceptor callback.
typedef ActionInterceptor = bool Function(DrawState state, DrawAction action);
