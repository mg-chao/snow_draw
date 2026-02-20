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
    SetDragPending(:final pointerDownPosition, :final intent) =>
      _setDragPending(
        state,
        DragPendingState(
          pointerDownPosition: pointerDownPosition,
          intent: intent,
        ),
      ),
    ClearDragPending _ => _clearDragPending(state),
    _ => null,
  };

  DrawState _setDragPending(DrawState state, DragPendingState pending) {
    if (state.application.interaction == pending) {
      return state;
    }

    return state.copyWith(
      application: state.application.copyWith(interaction: pending),
    );
  }

  DrawState _clearDragPending(DrawState state) =>
      state.application.interaction is DragPendingState
      ? state.copyWith(application: state.application.toIdle())
      : state;
}
