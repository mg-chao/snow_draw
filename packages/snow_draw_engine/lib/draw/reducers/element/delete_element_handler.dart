import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../actions/draw_actions.dart';
import '../../core/draw_context.dart';
import '../../elements/core/element_data.dart';
import '../../elements/types/arrow/arrow_core_bridge.dart';
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
}) {
  final deletedElementsById = <String, ElementState>{
    for (final element in elements)
      if (deleteIds.contains(element.id)) element.id: element,
  };
  final retained = <ElementState>[
    for (final element in elements)
      if (!deleteIds.contains(element.id))
        _applyDeleteElementUpdates(element: element, deleteIds: deleteIds),
  ];
  return _syncArrowBindingsAfterDeletion(
    elements: retained,
    deletedIds: deleteIds,
    deletedElementsById: deletedElementsById,
  );
}

ElementState _applyDeleteElementUpdates({
  required ElementState element,
  required Set<String> deleteIds,
}) {
  if (!isElementDependentOnIds(
    element: element,
    targetIds: deleteIds,
    includeArrowBindings: false,
  )) {
    return element;
  }
  return clearElementDependenciesForIds(
    element: element,
    targetIds: deleteIds,
    includeArrowBindings: false,
  );
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

  final syncedElements = _syncArrowBindingsAfterDuplication(
    elements: duplicatedElements,
    idMap: idMap,
  );
  return (elements: syncedElements, selectedIds: duplicatedSelectedIds);
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

List<ElementState> _syncArrowBindingsAfterDeletion({
  required List<ElementState> elements,
  required Set<String> deletedIds,
  required Map<String, ElementState> deletedElementsById,
}) {
  if (elements.isEmpty || deletedIds.isEmpty) {
    return elements;
  }

  final arrows = <core.ArrowState>[];
  final elementByArrowId = <String, (ElementState, ArrowLikeData)>{};
  for (final element in elements) {
    final data = element.data;
    if (data is! ArrowLikeData) {
      continue;
    }
    if (data.startBinding == null && data.endBinding == null) {
      continue;
    }
    arrows.add(toCoreArrowState(element: element, data: data));
    elementByArrowId[element.id] = (element, data);
  }
  if (arrows.isEmpty) {
    return elements;
  }

  final deletedArrowIds = <String>[
    for (final element in deletedElementsById.values)
      if (element.data is ArrowLikeData) element.id,
  ];
  final deletedBindableIds = <String>[
    for (final element in deletedElementsById.values)
      if (isArrowBindableElement(element)) element.id,
  ];

  final syncResult = core.syncBindingsAfterDeletion(<String, dynamic>{
    'arrows': arrows,
    'bindables': collectCoreBindableRelations(elements),
    'geometryBindables': collectCoreBindables(elements),
    'deletedArrowIds': deletedArrowIds,
    'deletedBindableIds': deletedBindableIds,
    'context': core.defaultEngineContext,
  });
  if (syncResult.arrowPatches.isEmpty) {
    return elements;
  }

  final patchedById = <String, ElementState>{};
  for (final arrowPatch in syncResult.arrowPatches) {
    final source = elementByArrowId[arrowPatch.id];
    if (source == null) {
      continue;
    }
    final (element, data) = source;
    final patched = applyCoreArrowPatchToElement(
      element: element,
      data: data,
      patch: arrowPatch.patch,
    );
    if (patched != element) {
      patchedById[patched.id] = patched;
    }
  }
  if (patchedById.isEmpty) {
    return elements;
  }

  return <ElementState>[
    for (final element in elements) patchedById[element.id] ?? element,
  ];
}

List<ElementState> _syncArrowBindingsAfterDuplication({
  required List<ElementState> elements,
  required Map<String, String> idMap,
}) {
  if (elements.isEmpty || idMap.isEmpty) {
    return elements;
  }

  final elementsById = {for (final element in elements) element.id: element};
  final bindableIdMap = <String, String>{};
  final arrowIdMap = <String, String>{};
  for (final entry in idMap.entries) {
    final duplicate = elementsById[entry.value];
    if (duplicate == null) {
      continue;
    }
    if (isArrowBindableElement(duplicate)) {
      bindableIdMap[entry.key] = entry.value;
      bindableIdMap[entry.value] = entry.value;
    }
    if (duplicate.data is ArrowLikeData) {
      arrowIdMap[entry.key] = entry.value;
      arrowIdMap[entry.value] = entry.value;
    }
  }

  final arrows = <core.ArrowState>[];
  final elementByArrowId = <String, (ElementState, ArrowLikeData)>{};
  for (final element in elements) {
    final data = element.data;
    if (data is! ArrowLikeData) {
      continue;
    }
    arrows.add(toCoreArrowState(element: element, data: data));
    elementByArrowId[element.id] = (element, data);
  }
  if (arrows.isEmpty) {
    return elements;
  }

  final syncResult = core.syncBindingsAfterDuplication(<String, dynamic>{
    'arrows': arrows,
    'bindables': collectCoreBindableRelations(elements),
    'bindableIdMap': bindableIdMap,
    'arrowIdMap': arrowIdMap,
    'geometryBindables': collectCoreBindables(elements),
    'context': core.defaultEngineContext,
  });
  if (syncResult.arrowPatches.isEmpty) {
    return elements;
  }

  final patchedById = <String, ElementState>{};
  for (final arrowPatch in syncResult.arrowPatches) {
    final source = elementByArrowId[arrowPatch.id];
    if (source == null) {
      continue;
    }
    final (element, data) = source;
    final patched = applyCoreArrowPatchToElement(
      element: element,
      data: data,
      patch: arrowPatch.patch,
    );
    if (patched != element) {
      patchedById[patched.id] = patched;
    }
  }
  if (patchedById.isEmpty) {
    return elements;
  }

  return <ElementState>[
    for (final element in elements) patchedById[element.id] ?? element,
  ];
}
