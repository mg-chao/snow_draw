import 'package:meta/meta.dart';

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
@immutable
class EditStateReducer {
  const EditStateReducer({
    required this.editSessionService,
    required this.sessionIdGenerator,
  });
  final EditSessionService editSessionService;
  final EditSessionIdGenerator sessionIdGenerator;

  /// Try to handle edit-related actions.
  ///
  /// Returns null if the action is not an edit action.
  InteractionTransition? reduce({
    required DrawState state,
    required DrawAction action,
    required InteractionReducerDeps context,
  }) => switch (action) {
    final StartEdit a => _reduceStartEdit(
      action: a,
      state: state,
      context: context,
    ),
    final UpdateEdit a => _reduceUpdateEdit(action: a, state: state),
    FinishEdit _ => _reduceFinishEdit(state: state),
    CancelEdit _ => _reduceCancelEdit(state: state),
    _ => null,
  };

  InteractionTransition _reduceStartEdit({
    required StartEdit action,
    required DrawState state,
    required InteractionReducerDeps context,
  }) {
    var currentState = state;

    if (currentState.application.isEditing) {
      final cancel = editSessionService.cancel(state: currentState);
      currentState = cancel.state;
    }

    final start = editSessionService.start(
      state: currentState,
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
  }) {
    final update = editSessionService.update(
      state: state,
      currentPosition: action.currentPosition,
      modifiers: action.modifiers,
    );
    return InteractionTransition(nextState: update.state);
  }

  InteractionTransition _reduceFinishEdit({required DrawState state}) {
    final finish = editSessionService.finish(state: state);
    return InteractionTransition(nextState: finish.state);
  }

  InteractionTransition _reduceCancelEdit({required DrawState state}) {
    final cancel = editSessionService.cancel(state: state);
    return InteractionTransition(nextState: cancel.state);
  }

  EditOperationParams _injectParams(
    EditOperationParams params,
    DrawConfig config,
  ) => switch (params) {
    final RotateOperationParams p => RotateOperationParams(
      startRotationAngle: p.startRotationAngle,
      rotationSnapAngle:
          p.rotationSnapAngle ?? ConfigDefaults.rotationSnapAngle,
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
}
