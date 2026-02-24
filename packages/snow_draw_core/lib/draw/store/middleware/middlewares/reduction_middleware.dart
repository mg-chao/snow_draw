import '../../../reducers/interaction/interaction_state_machine.dart';
import '../middleware_base.dart';
import '../middleware_context.dart';

/// Reduction middleware that executes the InteractionStateMachine.
///
/// This is the core middleware that transforms state based on actions.
class ReductionMiddleware extends MiddlewareBase {
  const ReductionMiddleware();

  @override
  String get name => 'Reduction';

  @override
  int get priority => 500;

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) {
    final transition = interactionStateMachine.reduce(
      state: context.currentState,
      action: context.action,
      context: context.drawContext,
      editSessionService: context.editSessionService,
      sessionIdGenerator: context.sessionIdGenerator,
    );

    return next(context.withCurrentState(transition.nextState));
  }
}
