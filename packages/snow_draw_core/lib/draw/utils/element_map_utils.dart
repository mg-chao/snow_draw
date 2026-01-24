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
) {
  final next = Map<String, ElementState>.from(elementMap);
  next[element.id] = element;
  return next;
}

Map<String, ElementState> updateElements(
  Map<String, ElementState> elementMap,
  Iterable<ElementState> elements,
) {
  if (elements.isEmpty) {
    return elementMap;
  }
  final next = Map<String, ElementState>.from(elementMap);
  for (final element in elements) {
    next[element.id] = element;
  }
  return next;
}

Map<String, ElementState> removeElement(
  Map<String, ElementState> elementMap,
  String elementId,
) {
  if (!elementMap.containsKey(elementId)) {
    return elementMap;
  }
  final next = Map<String, ElementState>.from(elementMap)..remove(elementId);
  return next;
}

Map<String, ElementState> removeElements(
  Map<String, ElementState> elementMap,
  Iterable<String> elementIds,
) {
  final ids = elementIds is Set<String> ? elementIds : elementIds.toSet();
  if (ids.isEmpty) {
    return elementMap;
  }

  final next = Map<String, ElementState>.from(elementMap);
  for (final id in ids) {
    next.remove(id);
  }
  return next;
}
