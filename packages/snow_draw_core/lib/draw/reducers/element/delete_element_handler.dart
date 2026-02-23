import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../elements/core/element_data.dart';
import '../../elements/types/arrow/arrow_binding.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../elements/types/serial_number/serial_number_dependencies.dart';
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
  final deleteIds = expandSerialNumberBoundTextIds(
    elements: document.elements,
    seedIds: action.elementIds.where(document.elementMap.containsKey),
  );
  if (deleteIds.isEmpty) {
    return state;
  }

  final newElements = [
    for (final element in document.elements)
      if (!deleteIds.contains(element.id))
        _applyDeleteElementUpdates(element: element, deleteIds: deleteIds),
  ];
  final newSelectedIds = _nextSelectionAfterDeletion(
    selectedIds: state.domain.selection.selectedIds,
    deletedIds: deleteIds,
  );

  final next = state.copyWith(
    domain: state.domain.copyWith(
      document: document.copyWith(elements: newElements),
    ),
  );
  return applySelectionChange(next, newSelectedIds);
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
  if (!ArrowBindingUtils.isBoundToAnyTargets(
    startBinding: startBinding,
    endBinding: endBinding,
    targetIds: deleteIds,
  )) {
    return element;
  }
  final clearStart =
      startBinding != null && deleteIds.contains(startBinding.elementId);
  final clearEnd =
      endBinding != null && deleteIds.contains(endBinding.elementId);

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
    return _reportDuplicateValidationFailure(
      state: state,
      action: action,
      context: context,
      logMessage: 'Duplicate failed: empty selection',
      reason: 'No element ids provided',
    );
  }

  final document = state.domain.document;
  final index = document.elementMap;
  final selectedIds = action.elementIds.toSet();
  final idsToDuplicate = expandSerialNumberBoundTextIds(
    elements: document.elements,
    seedIds: selectedIds.where(index.containsKey),
  );

  final elementsToDuplicate = _elementsByIds(
    elements: document.elements,
    ids: idsToDuplicate,
  );
  if (elementsToDuplicate.isEmpty) {
    return _reportDuplicateValidationFailure(
      state: state,
      action: action,
      context: context,
      logMessage: 'Duplicate failed: no elements found',
      reason: 'No valid elements to duplicate',
      details: {'elementIds': action.elementIds.toList()},
      logDetails: {'elementIds': action.elementIds.join(',')},
    );
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
    final duplicated = element.copyWith(
      id: newId,
      rect: element.rect.translate(
        DrawPoint(x: action.offsetX, y: action.offsetY),
      ),
      zIndex: nextZIndex,
      data: _duplicateDataWithRemappedReferences(element.data, idMap),
    );
    nextZIndex++;
    newElements.add(duplicated);
    if (selectedIds.contains(element.id)) {
      newSelectedIds.add(newId);
    }
  }

  final mergedElements = [...document.elements, ...newElements];
  final next = state.copyWith(
    domain: state.domain.copyWith(
      document: document.copyWith(elements: mergedElements),
    ),
  );
  return applySelectionChange(next, newSelectedIds);
}

Set<String> _nextSelectionAfterDeletion({
  required Set<String> selectedIds,
  required Set<String> deletedIds,
}) {
  if (!selectedIds.any(deletedIds.contains)) {
    return selectedIds;
  }
  return {
    for (final id in selectedIds)
      if (!deletedIds.contains(id)) id,
  };
}

List<ElementState> _elementsByIds({
  required Iterable<ElementState> elements,
  required Set<String> ids,
}) => [
  for (final element in elements)
    if (ids.contains(element.id)) element,
];

ElementData _duplicateDataWithRemappedReferences(
  ElementData data,
  Map<String, String> idMap,
) {
  if (data is SerialNumberData) {
    final textElementId = data.textElementId;
    return data.copyWith(
      textElementId: textElementId == null ? null : idMap[textElementId],
    );
  }
  if (data is ArrowLikeData) {
    return _remapArrowBindings(data, idMap);
  }
  return data;
}

DrawState _reportDuplicateValidationFailure({
  required DrawState state,
  required DuplicateElements action,
  required ElementReducerDeps context,
  required String logMessage,
  required String reason,
  Map<String, dynamic>? details,
  Map<String, dynamic>? logDetails,
}) {
  final actionName = action.runtimeType.toString();
  final metadata = {'action': actionName, ...?logDetails};
  context.log.store.warning(logMessage, metadata);
  context.eventBus?.emitLazy(
    () => ValidationFailedEvent(
      action: actionName,
      reason: reason,
      details: details ?? const <String, dynamic>{},
    ),
  );
  return state;
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

  final mappedStart = _remapBinding(startBinding, idMap);
  final mappedEnd = _remapBinding(endBinding, idMap);

  final clearStartSpecial = startBinding != null && mappedStart == null;
  final clearEndSpecial = endBinding != null && mappedEnd == null;

  return data.copyWith(
    startBinding: mappedStart,
    endBinding: mappedEnd,
    startIsSpecial: clearStartSpecial ? null : data.startIsSpecial,
    endIsSpecial: clearEndSpecial ? null : data.endIsSpecial,
  );
}

ArrowBinding? _remapBinding(ArrowBinding? binding, Map<String, String> idMap) {
  if (binding == null) {
    return null;
  }
  final targetId = idMap[binding.elementId];
  return targetId == null ? null : binding.copyWith(elementId: targetId);
}
