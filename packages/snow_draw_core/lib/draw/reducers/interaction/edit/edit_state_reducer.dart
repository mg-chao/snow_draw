import '../../../actions/draw_actions.dart';
import '../../../config/draw_config.dart';
import '../../../core/dependency_interfaces.dart';
import '../../../edit/core/edit_operation_params.dart';
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
  required InteractionReducerDeps context,
  required EditSessionService editSessionService,
  required EditSessionIdGenerator sessionIdGenerator,
}) => switch (action) {
  final StartEdit a => _reduceStartEdit(
    action: a,
    state: state,
    context: context,
    editSessionService: editSessionService,
    sessionIdGenerator: sessionIdGenerator,
  ),
  final UpdateEdit a => _reduceUpdateEdit(
    action: a,
    state: state,
    editSessionService: editSessionService,
  ),
  FinishEdit _ => _reduceFinishEdit(
    state: state,
    editSessionService: editSessionService,
  ),
  CancelEdit _ => _reduceCancelEdit(
    state: state,
    editSessionService: editSessionService,
  ),
  _ => null,
};

InteractionTransition _reduceStartEdit({
  required StartEdit action,
  required DrawState state,
  required InteractionReducerDeps context,
  required EditSessionService editSessionService,
  required EditSessionIdGenerator sessionIdGenerator,
}) {
  final start = editSessionService.start(
    state: state,
    operationId: action.operationId,
    position: action.position,
    params: _injectParams(action.params, context.config),
    sessionId: sessionIdGenerator(),
  );
  return InteractionTransition(nextState: start.state);
}

InteractionTransition _reduceUpdateEdit({
  required UpdateEdit action,
  required DrawState state,
  required EditSessionService editSessionService,
}) {
  final update = editSessionService.update(
    state: state,
    currentPosition: action.currentPosition,
    modifiers: action.modifiers,
  );
  return InteractionTransition(nextState: update.state);
}

InteractionTransition _reduceFinishEdit({
  required DrawState state,
  required EditSessionService editSessionService,
}) {
  final finish = editSessionService.finish(state: state);
  return InteractionTransition(nextState: finish.state);
}

InteractionTransition _reduceCancelEdit({
  required DrawState state,
  required EditSessionService editSessionService,
}) {
  final cancel = editSessionService.cancel(state: state);
  return InteractionTransition(nextState: cancel.state);
}

EditOperationParams _injectParams(
  EditOperationParams params,
  DrawConfig config,
) => switch (params) {
  final RotateOperationParams p => RotateOperationParams(
    startRotationAngle: p.startRotationAngle,
    rotationSnapAngle: p.rotationSnapAngle ?? ConfigDefaults.rotationSnapAngle,
    initialSelectionBounds: p.initialSelectionBounds,
  ),
  final ResizeOperationParams p => ResizeOperationParams(
    resizeMode: p.resizeMode,
    handleOffset: p.handleOffset,
    selectionPadding: p.selectionPadding ?? config.selection.padding,
    initialSelectionBounds: p.initialSelectionBounds,
  ),
  _ => params,
};
