import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../edit/apply/edit_apply.dart';
import '../../elements/types/arrow/arrow_binding_resolver.dart';
import '../../elements/types/arrow/arrow_core_bridge.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';

/// Result of resolving arrow bindings for changed bindables.
@immutable
final class ArrowBindingResolutionUpdate {
  const ArrowBindingResolutionUpdate({
    this.updatedElements = const <String, ElementState>{},
    this.orderedElementIds,
  });

  static const empty = ArrowBindingResolutionUpdate();

  final Map<String, ElementState> updatedElements;
  final List<String>? orderedElementIds;
}

/// Resolves arrow binding updates for bindables that changed geometry.
///
/// The resolver operates over the current document state plus
/// [overlayUpdates], allowing callers to pass in pending element replacements
/// before they are committed.
ArrowBindingResolutionUpdate resolveArrowBindingsForChangedBindables({
  required DrawState state,
  required Set<String> changedBindableIds,
  required Map<String, ElementState> overlayUpdates,
  required bool isBindingEnabled,
}) {
  if (changedBindableIds.isEmpty) {
    return ArrowBindingResolutionUpdate.empty;
  }

  final resolution = ArrowBindingResolver.instance.resolve(
    baseElements: state.domain.document.elementMap,
    updatedElements: overlayUpdates,
    changedElementIds: changedBindableIds,
    orderedElementIds: state.domain.document.elements
        .map((element) => element.id)
        .toList(growable: false),
    engineContext: buildCoreEngineContext(
      zoom: state.application.view.camera.zoom,
      isBindingEnabled: isBindingEnabled,
    ),
  );

  if (resolution.updatedElements.isEmpty &&
      resolution.orderedElementIds == null) {
    return ArrowBindingResolutionUpdate.empty;
  }

  return ArrowBindingResolutionUpdate(
    updatedElements: resolution.updatedElements,
    orderedElementIds: resolution.orderedElementIds,
  );
}

/// Applies [replacementsById] and optional [orderedElementIds] to [elements].
List<ElementState> applyElementReplacementsAndOrder({
  required List<ElementState> elements,
  required Map<String, ElementState> replacementsById,
  required List<String>? orderedElementIds,
}) {
  final replaced = EditApply.replaceElementsById(
    elements: elements,
    replacementsById: replacementsById,
  );
  return EditApply.reorderElementsByIdOrder(
    elements: replaced,
    orderedElementIds: orderedElementIds,
  );
}

/// Synchronizes arrow endpoint bindings after deleting elements.
List<ElementState> syncArrowBindingsAfterDeletion({
  required List<ElementState> elements,
  required Set<String> deletedIds,
  required Map<String, ElementState> deletedElementsById,
  core.EngineContext engineContext = core.defaultEngineContext,
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
    'context': engineContext,
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

/// Synchronizes arrow bindings for duplicated element snapshots.
List<ElementState> syncArrowBindingsAfterDuplication({
  required List<ElementState> elements,
  required Map<String, String> idMap,
  core.EngineContext engineContext = core.defaultEngineContext,
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
    'context': engineContext,
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
