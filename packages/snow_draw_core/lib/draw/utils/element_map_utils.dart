import '../models/element_state.dart';

/// Utilities for working with the `id -> element` map in DrawState.
///
/// All methods are pure (do not mutate the input map).
Map<String, ElementState> rebuildElementMap(Iterable<ElementState> elements) =>
    {for (final element in elements) element.id: element};

Map<String, ElementState> mergeFromList(Iterable<ElementState> elements) =>
    rebuildElementMap(elements);

Map<String, ElementState> updateElement(
  Map<String, ElementState> elementMap,
  ElementState element,
) => {...elementMap, element.id: element};

Map<String, ElementState> updateElements(
  Map<String, ElementState> elementMap,
  Iterable<ElementState> elements,
) {
  if (elements.isEmpty) {
    return elementMap;
  }
  return {...elementMap, for (final element in elements) element.id: element};
}

Map<String, ElementState> removeElement(
  Map<String, ElementState> elementMap,
  String elementId,
) {
  if (!elementMap.containsKey(elementId)) {
    return elementMap;
  }
  return Map<String, ElementState>.from(elementMap)..remove(elementId);
}

Map<String, ElementState> removeElements(
  Map<String, ElementState> elementMap,
  Iterable<String> elementIds,
) {
  if (elementIds.isEmpty) {
    return elementMap;
  }

  final next = Map<String, ElementState>.from(elementMap);
  for (final id in elementIds.toSet()) {
    next.remove(id);
  }
  return next;
}
