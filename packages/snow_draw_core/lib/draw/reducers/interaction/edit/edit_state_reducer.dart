import '../../../actions/draw_actions.dart';
import '../../../edit/core/edit_session_id_generator.dart';
import '../../../edit/core/edit_session_service.dart';
import '../../../models/draw_state.dart';
import '../interaction_transition.dart';

/// Reducer dedicated to edit operations.
///
/// Handles: StartEdit, UpdateEdit, FinishEdit, CancelEdit.
InteractionTransition? reduceEditState({
  required DrawState state,
  required DrawAction action,
  required EditSessionService editSessionService,
  required EditSessionIdGenerator sessionIdGenerator,
}) => switch (action) {
  final StartEdit a => InteractionTransition(
    nextState: editSessionService
        .start(
          state: state,
          operationId: a.operationId,
          position: a.position,
          params: a.params,
          sessionId: sessionIdGenerator(),
        )
        .state,
  ),
  final UpdateEdit a => InteractionTransition(
    nextState: editSessionService
        .update(
          state: state,
          currentPosition: a.currentPosition,
          modifiers: a.modifiers,
        )
        .state,
  ),
  FinishEdit _ => InteractionTransition(
    nextState: editSessionService.finish(state: state).state,
  ),
  CancelEdit _ => InteractionTransition(
    nextState: editSessionService.cancel(state: state).state,
  ),
  _ => null,
};
