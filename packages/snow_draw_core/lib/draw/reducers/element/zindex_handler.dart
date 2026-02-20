import 'dart:math';

import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../events/error_events.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';

DrawState handleChangeZIndex(
  DrawState state,
  ChangeElementZIndex action,
  ElementReducerDeps context,
) {
  final elements = state.domain.document.elements;
  final currentIndex = elements.indexWhere((e) => e.id == action.elementId);
  if (currentIndex == -1) {
    context.log.store.warning('Z-index change failed: element not found', {
      'action': action.runtimeType.toString(),
      'elementId': action.elementId,
      'operation': action.operation.name,
    });
    context.eventBus?.emitLazy(
      () => ValidationFailedEvent(
        action: action.runtimeType.toString(),
        reason: 'Element not found',
        details: {
          'elementId': action.elementId,
          'operation': action.operation.name,
        },
      ),
    );
    return state;
  }

  final destinationIndex = _resolveSingleDestinationIndex(
    operation: action.operation,
    currentIndex: currentIndex,
    length: elements.length,
  );
  if (destinationIndex == currentIndex) {
    return _reindexDocumentIfNeeded(state, elements);
  }

  final reordered = [...elements];
  final target = reordered.removeAt(currentIndex);
  reordered.insert(destinationIndex, target);
  return _reindexAndApply(state, source: elements, reordered: reordered);
}

DrawState handleChangeZIndexBatch(
  DrawState state,
  ChangeElementsZIndex action,
  ElementReducerDeps context,
) {
  if (action.elementIds.isEmpty) {
    return state;
  }

  final idSet = action.elementIds.toSet();
  final elements = state.domain.document.elements;
  final hasSelected = elements.any((element) => idSet.contains(element.id));
  if (!hasSelected) {
    context.log.store.warning('Z-index change failed: elements not found', {
      'action': action.runtimeType.toString(),
      'elementIds': action.elementIds,
      'operation': action.operation.name,
    });
    return state;
  }

  final reordered = switch (action.operation) {
    ZIndexOperation.bringToFront => _reorderBySelectionPartition(
      elements: elements,
      idSet: idSet,
      selectedFirst: false,
    ),
    ZIndexOperation.sendToBack => _reorderBySelectionPartition(
      elements: elements,
      idSet: idSet,
      selectedFirst: true,
    ),
    ZIndexOperation.bringForward => _moveSelectionForward(elements, idSet),
    ZIndexOperation.sendBackward => _moveSelectionBackward(elements, idSet),
  };

  if (_hasSameOrder(elements, reordered)) {
    return _reindexDocumentIfNeeded(state, elements);
  }

  return _reindexAndApply(state, source: elements, reordered: reordered);
}

({List<ElementState> selected, List<ElementState> unselected})
_partitionElementsBySelection(List<ElementState> elements, Set<String> idSet) {
  final selected = <ElementState>[];
  final unselected = <ElementState>[];
  for (final element in elements) {
    if (idSet.contains(element.id)) {
      selected.add(element);
    } else {
      unselected.add(element);
    }
  }
  return (selected: selected, unselected: unselected);
}

List<ElementState> _reorderBySelectionPartition({
  required List<ElementState> elements,
  required Set<String> idSet,
  required bool selectedFirst,
}) {
  final partition = _partitionElementsBySelection(elements, idSet);
  return selectedFirst
      ? [...partition.selected, ...partition.unselected]
      : [...partition.unselected, ...partition.selected];
}

List<ElementState> _moveSelectionForward(
  List<ElementState> elements,
  Set<String> idSet,
) {
  final reordered = [...elements];
  for (var i = reordered.length - 2; i >= 0; i--) {
    final current = reordered[i];
    final next = reordered[i + 1];
    if (idSet.contains(current.id) && !idSet.contains(next.id)) {
      reordered[i] = next;
      reordered[i + 1] = current;
    }
  }
  return reordered;
}

List<ElementState> _moveSelectionBackward(
  List<ElementState> elements,
  Set<String> idSet,
) {
  final reordered = [...elements];
  for (var i = 1; i < reordered.length; i++) {
    final current = reordered[i];
    final previous = reordered[i - 1];
    if (idSet.contains(current.id) && !idSet.contains(previous.id)) {
      reordered[i] = previous;
      reordered[i - 1] = current;
    }
  }
  return reordered;
}

int _resolveSingleDestinationIndex({
  required ZIndexOperation operation,
  required int currentIndex,
  required int length,
}) {
  final lastIndex = length - 1;
  return switch (operation) {
    ZIndexOperation.bringToFront => lastIndex,
    ZIndexOperation.sendToBack => 0,
    ZIndexOperation.bringForward => min(lastIndex, currentIndex + 1),
    ZIndexOperation.sendBackward => max(0, currentIndex - 1),
  };
}

bool _hasSameOrder(List<ElementState> before, List<ElementState> after) {
  if (before.length != after.length) {
    return false;
  }
  for (var i = 0; i < before.length; i++) {
    if (before[i].id != after[i].id) {
      return false;
    }
  }
  return true;
}

DrawState _reindexDocumentIfNeeded(
  DrawState state,
  List<ElementState> elements,
) => _reindexAndApply(state, source: elements, reordered: elements);

DrawState _reindexAndApply(
  DrawState state, {
  required List<ElementState> source,
  required List<ElementState> reordered,
}) {
  final reindexed = _reindexElements(reordered);
  if (identical(reindexed, source)) {
    return state;
  }
  return state.copyWith(
    domain: state.domain.copyWith(
      document: state.domain.document.copyWith(elements: reindexed),
    ),
  );
}

List<ElementState> _reindexElements(List<ElementState> elements) {
  var hasAnyZIndexChange = false;
  final reindexed = <ElementState>[];
  for (var i = 0; i < elements.length; i++) {
    final element = elements[i];
    if (element.zIndex == i) {
      reindexed.add(element);
      continue;
    }
    hasAnyZIndexChange = true;
    reindexed.add(element.copyWith(zIndex: i));
  }
  return hasAnyZIndexChange ? reindexed : elements;
}
