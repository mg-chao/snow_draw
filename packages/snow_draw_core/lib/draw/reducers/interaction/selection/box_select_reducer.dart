import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../models/draw_state.dart';
import '../../../models/interaction_state.dart';
import '../../../utils/selection_calculator.dart';
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
    final nextState = applySelectionChange(state, const {});
    final nextApplication = nextState.application.copyWith(
      interaction: BoxSelectingState(
        startPosition: action.startPosition,
        currentPosition: action.startPosition,
      ),
    );
    return nextState.copyWith(application: nextApplication);
  }

  DrawState _updateBoxSelect(DrawState state, UpdateBoxSelect action) {
    final interaction = state.application.interaction;
    if (interaction is! BoxSelectingState) {
      return state;
    }
    if (interaction.currentPosition == action.currentPosition) {
      return state;
    }
    return state.copyWith(
      application: state.application.copyWith(
        interaction: interaction.copyWith(
          currentPosition: action.currentPosition,
        ),
      ),
    );
  }

  DrawState _finishBoxSelect(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is! BoxSelectingState) {
      return state;
    }

    final bounds = interaction.bounds;
    final selectedIds = <String>{};

    final document = state.domain.document;
    final candidates = document.getElementsInRect(bounds);
    for (final element in candidates) {
      final aabb = SelectionCalculator.computeElementWorldAabb(element);
      // Only select elements that are completely within the selection bounds.
      if (bounds.minX <= aabb.minX &&
          bounds.maxX >= aabb.maxX &&
          bounds.minY <= aabb.minY &&
          bounds.maxY >= aabb.maxY) {
        selectedIds.add(element.id);
      }
    }

    final next = state.copyWith(
      application: state.application.copyWith(interaction: const IdleState()),
    );
    return applySelectionChange(next, selectedIds);
  }

  DrawState _cancelBoxSelect(DrawState state) {
    if (state.application.interaction is! BoxSelectingState) {
      return state;
    }
    return state.copyWith(application: state.application.toIdle());
  }
}
