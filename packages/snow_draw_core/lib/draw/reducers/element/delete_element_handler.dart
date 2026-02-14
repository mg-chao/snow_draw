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
  if (action.elementIds.isEmpty) {
    return state;
  }

  final document = state.domain.document;
  final deleteIds = <String>{};
  for (final id in action.elementIds) {
    if (document.getElementById(id) != null) {
      deleteIds.add(id);
    }
  }
  if (deleteIds.isEmpty) {
    return state;
  }

  _expandDeleteIdsForBoundSerialText(
    elements: document.elements,
    deleteIds: deleteIds,
  );

  final updatedElements = <String, ElementState>{};
  for (final element in document.elements) {
    if (deleteIds.contains(element.id)) {
      continue;
    }

    final serialUpdate = _resolveSerialUnbindUpdate(
      element: element,
      deleteIds: deleteIds,
    );
    if (serialUpdate != null) {
      updatedElements[element.id] = serialUpdate;
      continue;
    }

    final arrowUpdate = _resolveArrowUnbindUpdate(
      element: element,
      deleteIds: deleteIds,
    );
    if (arrowUpdate != null) {
      updatedElements[element.id] = arrowUpdate;
    }
  }

  var removedAny = false;
  final newElements = <ElementState>[];
  for (final element in document.elements) {
    if (deleteIds.contains(element.id)) {
      removedAny = true;
      continue;
    }
    final updated = updatedElements[element.id];
    newElements.add(updated ?? element);
  }

  if (!removedAny && updatedElements.isEmpty) {
    return state;
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
  if (deleteIds.isEmpty) {
    return;
  }

  final serialBindings = <String, List<String>>{};
  for (final element in elements) {
    final data = element.data;
    if (data is! SerialNumberData) {
      continue;
    }
    final boundId = data.textElementId;
    if (boundId == null) {
      continue;
    }
    serialBindings.putIfAbsent(element.id, () => <String>[]).add(boundId);
  }

  final pending = ListQueue<String>.from(deleteIds);
  while (pending.isNotEmpty) {
    final id = pending.removeFirst();
    final boundIds = serialBindings[id];
    if (boundIds == null) {
      continue;
    }
    for (final boundId in boundIds) {
      if (deleteIds.add(boundId)) {
        pending.add(boundId);
      }
    }
  }
}

ElementState? _resolveSerialUnbindUpdate({
  required ElementState element,
  required Set<String> deleteIds,
}) {
  final data = element.data;
  if (data is! SerialNumberData) {
    return null;
  }
  final boundId = data.textElementId;
  if (boundId == null || !deleteIds.contains(boundId)) {
    return null;
  }
  return element.copyWith(data: data.copyWith(textElementId: null));
}

ElementState? _resolveArrowUnbindUpdate({
  required ElementState element,
  required Set<String> deleteIds,
}) {
  final data = element.data;
  if (data is! ArrowLikeData) {
    return null;
  }

  final startBinding = data.startBinding;
  final endBinding = data.endBinding;
  final clearStart =
      startBinding != null && deleteIds.contains(startBinding.elementId);
  final clearEnd =
      endBinding != null && deleteIds.contains(endBinding.elementId);
  if (!clearStart && !clearEnd) {
    return null;
  }

  final nextData = data.copyWith(
    startBinding: clearStart ? null : startBinding,
    endBinding: clearEnd ? null : endBinding,
    startIsSpecial: clearStart ? null : data.startIsSpecial,
    endIsSpecial: clearEnd ? null : data.endIsSpecial,
  );
  return element.copyWith(data: nextData);
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
      data: nextData,
    );
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
