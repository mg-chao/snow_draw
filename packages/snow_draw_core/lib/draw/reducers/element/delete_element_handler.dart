import 'dart:collection';

import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../events/error_events.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../types/draw_point.dart';
import '../core/reducer_utils.dart';

DrawState handleDeleteElements(
  DrawState state,
  DeleteElements action,
  ElementReducerDeps _,
) {
  final document = state.domain.document;
  final deleteIds = action.elementIds
      .where(document.elementMap.containsKey)
      .toSet();
  if (deleteIds.isEmpty) {
    return state;
  }

  _expandDeleteIdsForBoundSerialText(
    elements: document.elements,
    deleteIds: deleteIds,
  );

  final newElements = <ElementState>[];
  for (final element in document.elements) {
    if (deleteIds.contains(element.id)) {
      continue;
    }
    newElements.add(
      _applyDeleteElementUpdates(element: element, deleteIds: deleteIds),
    );
  }

  final selection = state.domain.selection.selectedIds;
  final hasSelectionRemoval = selection.any(deleteIds.contains);
  final newSelectedIds = hasSelectionRemoval
      ? selection.where((id) => !deleteIds.contains(id)).toSet()
      : selection;

  final next = state.copyWith(
    domain: state.domain.copyWith(
      document: document.copyWith(elements: newElements),
    ),
  );
  return applySelectionChange(next, newSelectedIds);
}

void _expandDeleteIdsForBoundSerialText({
  required Iterable<ElementState> elements,
  required Set<String> deleteIds,
}) {
  final serialBindings = <String, String>{};
  for (final element in elements) {
    final data = element.data;
    if (data is SerialNumberData && data.textElementId != null) {
      serialBindings[element.id] = data.textElementId!;
    }
  }

  final pending = ListQueue<String>.from(deleteIds);
  while (pending.isNotEmpty) {
    final id = pending.removeFirst();
    final boundId = serialBindings[id];
    if (boundId == null) {
      continue;
    }
    if (deleteIds.add(boundId)) {
      pending.add(boundId);
    }
  }
}

ElementState _applyDeleteElementUpdates({
  required ElementState element,
  required Set<String> deleteIds,
}) {
  final data = element.data;
  if (data is SerialNumberData) {
    final boundId = data.textElementId;
    if (boundId == null || !deleteIds.contains(boundId)) {
      return element;
    }
    return element.copyWith(data: data.copyWith(textElementId: null));
  }

  if (data is! ArrowLikeData) {
    return element;
  }

  final startBinding = data.startBinding;
  final endBinding = data.endBinding;
  final clearStart =
      startBinding != null && deleteIds.contains(startBinding.elementId);
  final clearEnd =
      endBinding != null && deleteIds.contains(endBinding.elementId);
  if (!clearStart && !clearEnd) {
    return element;
  }

  return element.copyWith(
    data: data.copyWith(
      startBinding: clearStart ? null : startBinding,
      endBinding: clearEnd ? null : endBinding,
      startIsSpecial: clearStart ? null : data.startIsSpecial,
      endIsSpecial: clearEnd ? null : data.endIsSpecial,
    ),
  );
}

DrawState handleDuplicateElements(
  DrawState state,
  DuplicateElements action,
  ElementReducerDeps context,
) {
  if (action.elementIds.isEmpty) {
    context.log.store.warning('Duplicate failed: empty selection', {
      'action': action.runtimeType.toString(),
    });
    context.eventBus?.emitLazy(
      () => ValidationFailedEvent(
        action: action.runtimeType.toString(),
        reason: 'No element ids provided',
      ),
    );
    return state;
  }

  final index = state.domain.document.elementMap;
  final selectedIds = action.elementIds.toSet();
  final idsToDuplicate = <String>{...selectedIds};
  for (final id in selectedIds) {
    final element = index[id];
    final data = element?.data;
    if (data is SerialNumberData) {
      final boundId = data.textElementId;
      if (boundId != null && index[boundId] != null) {
        idsToDuplicate.add(boundId);
      }
    }
  }

  final elementsToDuplicate = <ElementState>[];
  for (final element in state.domain.document.elements) {
    if (idsToDuplicate.contains(element.id)) {
      elementsToDuplicate.add(element);
    }
  }
  if (elementsToDuplicate.isEmpty) {
    context.log.store.warning('Duplicate failed: no elements found', {
      'action': action.runtimeType.toString(),
      'elementIds': action.elementIds.join(','),
    });
    context.eventBus?.emitLazy(
      () => ValidationFailedEvent(
        action: action.runtimeType.toString(),
        reason: 'No valid elements to duplicate',
        details: {'elementIds': action.elementIds.toList()},
      ),
    );
    return state;
  }

  final idMap = <String, String>{};
  for (final element in elementsToDuplicate) {
    idMap[element.id] = context.idGenerator();
  }

  final newElements = <ElementState>[];
  final newSelectedIds = <String>{};
  var nextZIndex = resolveNextZIndex(state.domain.document.elements);

  for (final element in elementsToDuplicate) {
    final newId = idMap[element.id]!;
    var nextData = element.data;
    if (nextData is SerialNumberData) {
      final mapped = nextData.textElementId == null
          ? null
          : idMap[nextData.textElementId!];
      nextData = nextData.copyWith(textElementId: mapped);
    }
    if (nextData is ArrowLikeData) {
      nextData = _remapArrowBindings(nextData, idMap);
    }
    final duplicated = element.copyWith(
      id: newId,
      rect: element.rect.translate(
        DrawPoint(x: action.offsetX, y: action.offsetY),
      ),
      zIndex: nextZIndex,
      data: nextData,
    );
    nextZIndex++;
    newElements.add(duplicated);
    if (selectedIds.contains(element.id)) {
      newSelectedIds.add(newId);
    }
  }

  final mergedElements = [...state.domain.document.elements, ...newElements];
  final next = state.copyWith(
    domain: state.domain.copyWith(
      document: state.domain.document.copyWith(elements: mergedElements),
    ),
  );
  return applySelectionChange(next, newSelectedIds);
}

/// Remaps arrow/line binding element IDs to their duplicated counterparts.
///
/// If a binding target was not duplicated, the binding is cleared (set to
/// null) so the duplicated arrow does not reference the original element.
ArrowLikeData _remapArrowBindings(
  ArrowLikeData data,
  Map<String, String> idMap,
) {
  final startBinding = data.startBinding;
  final endBinding = data.endBinding;
  if (startBinding == null && endBinding == null) {
    return data;
  }

  final mappedStartId = startBinding == null
      ? null
      : idMap[startBinding.elementId];
  final mappedEndId = endBinding == null ? null : idMap[endBinding.elementId];

  final mappedStart = startBinding == null || mappedStartId == null
      ? null
      : startBinding.copyWith(elementId: mappedStartId);
  final mappedEnd = endBinding == null || mappedEndId == null
      ? null
      : endBinding.copyWith(elementId: mappedEndId);

  final clearStartSpecial = startBinding != null && mappedStart == null;
  final clearEndSpecial = endBinding != null && mappedEnd == null;

  return data.copyWith(
    startBinding: mappedStart,
    endBinding: mappedEnd,
    startIsSpecial: clearStartSpecial ? null : data.startIsSpecial,
    endIsSpecial: clearEndSpecial ? null : data.endIsSpecial,
  );
}
