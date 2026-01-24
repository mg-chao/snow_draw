import '../../../reducers/interaction/interaction_state_machine.dart';
import '../middleware_base.dart';
import '../middleware_context.dart';

/// Reduction middleware that executes the InteractionStateMachine.
///
/// This is the core middleware that transforms state based on actions.
/// It handles:
/// - Conflict-driven cancellation
/// - Edit operations
/// - Other state transitions
///
/// This middleware is essential and should always be included in the pipeline.
class ReductionMiddleware extends MiddlewareBase {
  const ReductionMiddleware();

  @override
  String get name => 'Reduction';

  @override
  int get priority => 500; // Medium priority - core logic

  @override
  Future<DispatchContext> invoke(DispatchContext context, NextFunction next) {
    // Execute the state machine to get the next state
    final transition = interactionStateMachine.reduce(
      state: context.currentState,
      action: context.action,
      context: context.drawContext,
      editSessionService: context.editSessionService,
      sessionIdGenerator: context.sessionIdGenerator,
      historyAvailability: context.historyAvailability,
    );

    // Update context with new state and events
    final updatedContext = context
        .withCurrentState(transition.nextState)
        .withEvents(transition.events);

    // Continue to next middleware
    return next(updatedContext);
  }
}
