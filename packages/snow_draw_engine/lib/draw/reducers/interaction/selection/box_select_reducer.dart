import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../models/draw_state.dart';
import '../../../models/interaction_state.dart';
import '../../core/reducer_utils.dart';

/// Reducer for box selection operations.
///
/// Handles: StartBoxSelect, UpdateBoxSelect, FinishBoxSelect, CancelBoxSelect.
@immutable
class BoxSelectReducer {
  const BoxSelectReducer();

  /// Try to handle box selection actions.
  ///
  /// Returns null if the action is not a box selection operation.
  DrawState? reduce(DrawState state, DrawAction action) => switch (action) {
    final StartBoxSelect a => _startBoxSelect(state, a),
    final UpdateBoxSelect a => _updateBoxSelect(state, a),
    FinishBoxSelect _ => _finishBoxSelect(state),
    CancelBoxSelect _ => _cancelBoxSelect(state),
    _ => null,
  };

  DrawState _startBoxSelect(DrawState state, StartBoxSelect action) {
    final nextState = applySelectionChange(state, const <String>{});
    return nextState.copyWith(
      application: nextState.application.copyWith(
        interaction: BoxSelectingState(
          startPosition: action.startPosition,
          currentPosition: action.startPosition,
        ),
      ),
    );
  }

  DrawState _updateBoxSelect(DrawState state, UpdateBoxSelect action) =>
      switch (state.application.interaction) {
        final BoxSelectingState interaction
            when interaction.currentPosition == action.currentPosition =>
          state,
        final BoxSelectingState interaction => state.copyWith(
          application: state.application.copyWith(
            interaction: interaction.copyWith(
              currentPosition: action.currentPosition,
            ),
          ),
        ),
        _ => state,
      };

  DrawState _finishBoxSelect(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is! BoxSelectingState) {
      return state;
    }

    final selectedIds = <String>{};
    state.domain.document.visitElementsInRect(interaction.bounds, (element) {
      selectedIds.add(element.id);
      return true;
    });
    final next = state.copyWith(application: state.application.toIdle());
    return applySelectionChange(next, selectedIds);
  }

  DrawState _cancelBoxSelect(DrawState state) {
    if (state.application.interaction is! BoxSelectingState) {
      return state;
    }
    return state.copyWith(application: state.application.toIdle());
  }
}
