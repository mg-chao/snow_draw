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
    context.eventBus?.emit(
      ValidationFailedEvent(
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
  final reindexed = _reindexElements(reordered);

  return state.copyWith(
    domain: state.domain.copyWith(
      document: state.domain.document.copyWith(elements: reindexed),
    ),
  );
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
  final selected = elements.where((e) => idSet.contains(e.id)).toList();
  if (selected.isEmpty) {
    context.log.store.warning('Z-index change failed: elements not found', {
      'action': action.runtimeType.toString(),
      'elementIds': action.elementIds,
      'operation': action.operation.name,
    });
    return state;
  }

  late final List<ElementState> reordered;

  switch (action.operation) {
    case ZIndexOperation.bringToFront:
      reordered = [
        ...elements.where((e) => !idSet.contains(e.id)),
        ...elements.where((e) => idSet.contains(e.id)),
      ];
    case ZIndexOperation.sendToBack:
      reordered = [
        ...elements.where((e) => idSet.contains(e.id)),
        ...elements.where((e) => !idSet.contains(e.id)),
      ];
    case ZIndexOperation.bringForward:
      reordered = [...elements];
      for (var i = reordered.length - 2; i >= 0; i--) {
        final current = reordered[i];
        final next = reordered[i + 1];
        if (idSet.contains(current.id) && !idSet.contains(next.id)) {
          reordered[i] = next;
          reordered[i + 1] = current;
        }
      }
    case ZIndexOperation.sendBackward:
      reordered = [...elements];
      for (var i = 1; i < reordered.length; i++) {
        final current = reordered[i];
        final previous = reordered[i - 1];
        if (idSet.contains(current.id) && !idSet.contains(previous.id)) {
          reordered[i] = previous;
          reordered[i - 1] = current;
        }
      }
  }

  if (_hasSameOrder(elements, reordered)) {
    return _reindexDocumentIfNeeded(state, elements);
  }

  final reindexed = _reindexElements(reordered);
  return state.copyWith(
    domain: state.domain.copyWith(
      document: state.domain.document.copyWith(elements: reindexed),
    ),
  );
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
  if (identical(before, after)) {
    return true;
  }
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
) {
  final reindexed = _reindexElements(elements);
  if (identical(reindexed, elements)) {
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
