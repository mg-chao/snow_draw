import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../models/draw_state.dart';
import '../../../models/interaction_state.dart';

/// Reducer for pending select/move states.
///
/// Handles: SetPendingSelect, ClearPendingSelect, SetPendingMove,
/// ClearPendingMove.
@immutable
class PendingStateReducer {
  const PendingStateReducer();

  /// Try to handle pending-state actions.
  ///
  /// Returns null if the action is not a pending-state operation.
  DrawState? reduce(DrawState state, DrawAction action) => switch (action) {
    final SetPendingSelect a => _setPendingSelect(state, a),
    ClearPendingSelect _ => _clearPendingSelect(state),
    final SetPendingMove a => _setPendingMove(state, a),
    ClearPendingMove _ => _clearPendingMove(state),
    _ => null,
  };

  DrawState _setPendingSelect(DrawState state, SetPendingSelect action) =>
      state.copyWith(
        application: state.application.copyWith(
          interaction: PendingSelectState(
            pendingSelect: PendingSelectInfo(
              elementId: action.elementId,
              addToSelection: action.addToSelection,
              pointerDownPosition: action.pointerDownPosition,
            ),
          ),
        ),
      );

  DrawState _clearPendingSelect(DrawState state) {
    if (state.application.interaction is PendingSelectState) {
      return state.copyWith(application: state.application.toIdle());
    }
    return state;
  }

  DrawState _setPendingMove(DrawState state, SetPendingMove action) =>
      state.copyWith(
        application: state.application.copyWith(
          interaction: PendingMoveState(
            pointerDownPosition: action.pointerDownPosition,
          ),
        ),
      );

  DrawState _clearPendingMove(DrawState state) {
    if (state.application.interaction is PendingMoveState) {
      return state.copyWith(application: state.application.toIdle());
    }
    return state;
  }
}
