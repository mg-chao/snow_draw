import '../models/element_state.dart';

/// Filters [elements] to visible elements, optionally excluding ids.
List<ElementState> resolveVisibleElements(
  Iterable<ElementState> elements, {
  Set<String> excludedIds = const {},
}) => [
  for (final element in elements)
    if (element.opacity > 0 && !excludedIds.contains(element.id)) element,
];
