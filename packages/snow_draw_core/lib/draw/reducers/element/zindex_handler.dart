import 'dart:math';

import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../events/error_events.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../services/element_index_service.dart';

DrawState handleChangeZIndex(
  DrawState state,
  ChangeElementZIndex action,
  ElementReducerDeps context,
) {
  final target = ElementIndexService(
    state.domain.document.elements,
  )[action.elementId];
  if (target == null) {
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

  final elements = [...state.domain.document.elements]
    ..removeWhere((e) => e.id == target.id);

  switch (action.operation) {
    case ZIndexOperation.bringToFront:
      elements.add(target);
    case ZIndexOperation.sendToBack:
      elements.insert(0, target);
    case ZIndexOperation.bringForward:
      final idx = min(elements.length, target.zIndex + 1);
      elements.insert(idx, target);
    case ZIndexOperation.sendBackward:
      final idx = max(0, target.zIndex - 1);
      elements.insert(idx, target);
  }

  final reindexed = <ElementState>[];
  for (var i = 0; i < elements.length; i++) {
    reindexed.add(elements[i].copyWith(zIndex: i));
  }

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
  final elements = [...state.domain.document.elements];
  final selected = elements.where((e) => idSet.contains(e.id)).toList();
  if (selected.isEmpty) {
    context.log.store.warning('Z-index change failed: elements not found', {
      'action': action.runtimeType.toString(),
      'elementIds': action.elementIds,
      'operation': action.operation.name,
    });
    return state;
  }

  List<ElementState> reordered;

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

  final reindexed = <ElementState>[];
  for (var i = 0; i < reordered.length; i++) {
    reindexed.add(reordered[i].copyWith(zIndex: i));
  }

  return state.copyWith(
    domain: state.domain.copyWith(
      document: state.domain.document.copyWith(elements: reindexed),
    ),
  );
}
