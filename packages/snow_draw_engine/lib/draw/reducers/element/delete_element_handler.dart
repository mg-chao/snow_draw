import '../../actions/draw_actions.dart';
import '../../core/draw_context.dart';
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
  DrawContext _,
) {
  final document = state.domain.document;
  final deleteIds = _resolveDeleteIds(
    elements: document.elements,
    elementIndex: document.elementMap,
    requestedIds: action.elementIds,
  );
  if (deleteIds.isEmpty) {
    return state;
  }

  final nextElements = _buildElementsAfterDeletion(
    elements: document.elements,
    deleteIds: deleteIds,
  );
  final newSelectedIds = _nextSelectionAfterDeletion(
    selectedIds: state.domain.selection.selectedIds,
    deletedIds: deleteIds,
  );

  final next = state.copyWith(
    domain: state.domain.copyWith(
      document: document.copyWith(elements: nextElements),
    ),
  );
  return applySelectionChange(next, newSelectedIds);
}

Set<String> _resolveDeleteIds({
  required List<ElementState> elements,
  required Map<String, ElementState> elementIndex,
  required Iterable<String> requestedIds,
}) => expandSerialNumberBoundTextIds(
  elements: elements,
  seedIds: requestedIds.where(elementIndex.containsKey),
);

List<ElementState> _buildElementsAfterDeletion({
  required List<ElementState> elements,
  required Set<String> deleteIds,
}) => [
  for (final element in elements)
    if (!deleteIds.contains(element.id))
      _applyDeleteElementUpdates(element: element, deleteIds: deleteIds),
];

ElementState _applyDeleteElementUpdates({
  required ElementState element,
  required Set<String> deleteIds,
}) {
  if (!isElementDependentOnIds(element: element, targetIds: deleteIds)) {
    return element;
  }
  return clearElementDependenciesForIds(element: element, targetIds: deleteIds);
}

DrawState handleDuplicateElements(
  DrawState state,
  DuplicateElements action,
  DrawContext context,
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
  final selectedIds = action.elementIds.toSet();
  final idsToDuplicate = expandSerialNumberBoundTextIds(
    elements: document.elements,
    seedIds: selectedIds.where(document.elementMap.containsKey),
  );

  final sourceElements = _elementsByIds(
    elements: document.elements,
    ids: idsToDuplicate,
  );
  if (sourceElements.isEmpty) {
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

  final idMap = {
    for (final element in sourceElements) element.id: context.idGenerator(),
  };
  final duplicated = _buildDuplicatedElements(
    sourceElements: sourceElements,
    selectedIds: selectedIds,
    idMap: idMap,
    offsetX: action.offsetX,
    offsetY: action.offsetY,
    startZIndex: resolveNextZIndex(document.elements),
  );

  final mergedElements = [...document.elements, ...duplicated.elements];
  final next = state.copyWith(
    domain: state.domain.copyWith(
      document: document.copyWith(elements: mergedElements),
    ),
  );
  return applySelectionChange(next, duplicated.selectedIds);
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

({List<ElementState> elements, Set<String> selectedIds})
_buildDuplicatedElements({
  required List<ElementState> sourceElements,
  required Set<String> selectedIds,
  required Map<String, String> idMap,
  required double offsetX,
  required double offsetY,
  required int startZIndex,
}) {
  final duplicatedElements = <ElementState>[];
  final duplicatedSelectedIds = <String>{};
  var nextZIndex = startZIndex;

  for (final element in sourceElements) {
    final newId = idMap[element.id]!;
    duplicatedElements.add(
      element.copyWith(
        id: newId,
        rect: element.rect.translate(DrawPoint(x: offsetX, y: offsetY)),
        zIndex: nextZIndex,
        data: _duplicateDataWithRemappedReferences(element.data, idMap),
      ),
    );
    nextZIndex += 1;
    if (selectedIds.contains(element.id)) {
      duplicatedSelectedIds.add(newId);
    }
  }

  return (elements: duplicatedElements, selectedIds: duplicatedSelectedIds);
}

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
  required DrawContext context,
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
