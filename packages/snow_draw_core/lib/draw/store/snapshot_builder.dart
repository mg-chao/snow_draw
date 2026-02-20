import 'package:meta/meta.dart';

import '../actions/draw_actions.dart';
import '../models/draw_state.dart';
import '../models/element_state.dart';
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
    final document = state.domain.document;
    final elementMap = document.elementMap;
    final elementsById = <String, ElementState>{};
    for (final id in changes.allElementIds) {
      final element = elementMap[id];
      if (element == null) {
        continue;
      }
      elementsById[id] = element;
    }

    return IncrementalSnapshot(
      elementsById: elementsById,
      globalElements: document.globalElements,
      selection: includeSelection
          ? state.domain.selection
          : const SelectionState(),
      includeSelection: includeSelection,
      order: changes.orderChanged
          ? document.elements.map((element) => element.id).toList()
          : null,
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

  DrawState _stateBeforeAction(DrawAction _, DrawState current) => current;
}
