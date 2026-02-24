import 'package:meta/meta.dart';

import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../edit/core/edit_session_id_generator.dart';
import '../../edit/core/edit_session_service.dart';
import '../../models/draw_state.dart';
import '../camera/camera_reducer.dart';
import '../element/element_reducer.dart';
import '../selection/selection_reducer.dart';
import 'create/create_element_reducer.dart';
import 'edit/edit_state_reducer.dart';
import 'interaction_transition.dart';
import 'selection/box_select_reducer.dart';
import 'selection/pending_state_reducer.dart';
import 'text/text_edit_reducer.dart';

/// Interaction state machine - coordinates sub-reducers.
///
/// Responsibilities:
/// 1. Dispatch actions to sub-reducers in priority order
/// 2. Coordinate state transitions across subsystems
@immutable
class InteractionStateMachine {
  const InteractionStateMachine();

  /// Single entry point for all interaction actions.
  InteractionTransition reduce({
    required DrawState state,
    required DrawAction action,
    required InteractionReducerDeps context,
    required EditSessionService editSessionService,
    required EditSessionIdGenerator sessionIdGenerator,
  }) {
    // 1) Edit operations.
    final editResult = reduceEditState(
      state: state,
      action: action,
      context: context,
      editSessionService: editSessionService,
      sessionIdGenerator: sessionIdGenerator,
    );
    if (editResult != null) {
      return editResult;
    }

    // 2) Other interaction and domain reducers.
    final reduced = reduceState(state, action, context);
    if (reduced != null) {
      return InteractionTransition(nextState: reduced);
    }

    return InteractionTransition.unchanged(state);
  }

  /// Handle non-edit actions (state only).
  ///
  /// Reducers are evaluated in order and the first non-null result wins.
  DrawState? reduceState(
    DrawState state,
    DrawAction action,
    InteractionReducerDeps context,
  ) =>
      _pendingReducer.reduce(state, action) ??
      _boxSelectReducer.reduce(state, action) ??
      _createReducer.reduce(state, action, context) ??
      _textEditReducer.reduce(state, action, context) ??
      selectionReducer(state, action, context) ??
      elementReducer(state, action, context) ??
      cameraReducer(state, action);
}

const _pendingReducer = PendingStateReducer();
const _boxSelectReducer = BoxSelectReducer();
const _createReducer = CreateElementReducer();
const _textEditReducer = TextEditReducer();

const interactionStateMachine = InteractionStateMachine();
