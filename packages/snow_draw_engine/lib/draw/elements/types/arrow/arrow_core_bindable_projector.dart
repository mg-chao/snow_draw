import '../../../models/element_state.dart';
import 'arrow_core.dart' as core;
import 'arrow_core_bindable_candidates.dart';
import 'arrow_core_bridge.dart';

/// Projects [elements] into ordered arrow-core bindable candidates.
///
/// This helper keeps bindable projection logic consistent across creation,
/// preview, edit, and reducer flows.
ArrowCoreBindableCandidates projectArrowCoreBindableCandidates({
  required Iterable<ElementState> elements,
  Map<String, core.BindableState>? bindablesById,
}) {
  final seenIds = <String>{};
  final projectedElements = <ElementState>[];
  final projectedBindables = <core.BindableState>[];

  for (final element in elements) {
    if (!seenIds.add(element.id)) {
      continue;
    }

    final bindable = bindablesById == null
        ? toCoreBindableState(element)
        : bindablesById[element.id];
    if (bindable == null) {
      continue;
    }

    projectedElements.add(element);
    projectedBindables.add(bindable);
  }

  if (projectedBindables.isEmpty) {
    return ArrowCoreBindableCandidates.empty;
  }

  return ArrowCoreBindableCandidates(
    elements: List<ElementState>.unmodifiable(projectedElements),
    bindables: List<core.BindableState>.unmodifiable(projectedBindables),
  );
}
