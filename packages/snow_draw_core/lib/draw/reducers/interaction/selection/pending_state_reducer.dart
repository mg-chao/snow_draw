import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../models/draw_state.dart';
import '../../../models/interaction_state.dart';

/// Reducer for pending select/move states.
///
/// Handles: SetDragPending, ClearDragPending
@immutable
class PendingStateReducer {
  const PendingStateReducer();

  /// Try to handle pending-state actions.
  ///
  /// Returns null if the action is not a pending-state operation.
  DrawState? reduce(DrawState state, DrawAction action) => switch (action) {
    final SetDragPending a => _setDragPending(state, a),
    ClearDragPending _ => _clearDragPending(state),
    _ => null,
  };

  DrawState _setDragPending(DrawState state, SetDragPending action) =>
      state.copyWith(
        application: state.application.copyWith(
          interaction: DragPendingState(
            pointerDownPosition: action.pointerDownPosition,
            intent: action.intent,
          ),
        ),
      );

  DrawState _clearDragPending(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is DragPendingState) {
      return state.copyWith(application: state.application.toIdle());
    }
    return state;
  }
}
