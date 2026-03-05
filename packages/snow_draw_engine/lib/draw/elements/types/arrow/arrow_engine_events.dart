import 'arrow_core.dart' as core;

/// Reduces arrow-core events into an updated element ordering.
///
/// Returns `null` when no ordering change is required.
List<String>? reduceArrowEngineEventsToOrderedIds({
  required List<String> orderedElementIds,
  required List<core.ArrowEngineEvent> events,
  Map<String, List<String>>? anchorElementIdsByBindableId,
}) {
  if (orderedElementIds.isEmpty || events.isEmpty) {
    return null;
  }

  final result = core.reduceArrowEngineEventsToOrder(
    core.ReduceArrowEngineEventsToOrderInput(
      orderedElementIds: orderedElementIds,
      events: events,
      anchorElementIdsByBindableId: anchorElementIdsByBindableId,
    ),
  );
  if (!result.moved ||
      _stringListEquals(result.orderedElementIds, orderedElementIds)) {
    return null;
  }

  return List<String>.unmodifiable(result.orderedElementIds);
}

bool _stringListEquals(List<String> left, List<String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}
