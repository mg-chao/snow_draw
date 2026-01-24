import 'package:meta/meta.dart';

import '../actions/draw_actions.dart';
import '../models/draw_state.dart';
import '../models/element_state.dart';
import '../models/interaction_state.dart';
import '../models/selection_state.dart';
import 'history_change_set.dart';
import 'snapshot.dart';

/// Builds snapshots for undo/redo.
@immutable
class SnapshotBuilder {
  const SnapshotBuilder();

  PersistentSnapshot buildSnapshotFromState({
    required DrawState state,
    required bool includeSelection,
  }) => PersistentSnapshot.fromState(state, includeSelection: includeSelection);

  PersistentSnapshot buildSnapshotBeforeAction({
    required DrawState currentState,
    required DrawAction action,
    required bool includeSelection,
  }) {
    final snapshotState = _stateBeforeAction(action, currentState);
    return PersistentSnapshot.fromState(
      snapshotState,
      includeSelection: includeSelection,
    );
  }

  IncrementalSnapshot buildIncrementalSnapshotFromState({
    required DrawState state,
    required HistoryChangeSet changes,
    required bool includeSelection,
  }) {
    final elementsById = <String, ElementState>{};
    if (changes.hasElementChanges) {
      final elementMap = state.domain.document.elementMap;
      for (final id in changes.allElementIds) {
        final element = elementMap[id];
        if (element != null) {
          elementsById[id] = element;
        }
      }
    }

    final order = changes.orderChanged
        ? state.domain.document.elements.map((e) => e.id).toList()
        : null;

    return IncrementalSnapshot(
      elementsById: elementsById,
      selection: includeSelection
          ? state.domain.selection
          : const SelectionState(),
      includeSelection: includeSelection,
      order: order,
    );
  }

  IncrementalSnapshot buildIncrementalSnapshotBeforeAction({
    required DrawState currentState,
    required DrawAction action,
    required HistoryChangeSet changes,
    required bool includeSelection,
  }) {
    final snapshotState = _stateBeforeAction(action, currentState);
    return buildIncrementalSnapshotFromState(
      state: snapshotState,
      changes: changes,
      includeSelection: includeSelection,
    );
  }

  DrawState _stateBeforeAction(DrawAction action, DrawState current) {
    if (action is FinishCreateElement) {
      final interaction = current.application.interaction;
      if (interaction is CreatingState) {
        final creatingId = interaction.elementId;
        if (current.domain.document.getElementById(creatingId) == null) {
          return current;
        }
        final elementsBefore = current.domain.document.elements
            .where((e) => e.id != creatingId)
            .toList();
        return current.copyWith(
          domain: current.domain.copyWith(
            document: current.domain.document.copyWith(
              elements: elementsBefore,
            ),
          ),
        );
      }
      return current;
    }

    return current;
  }
}
