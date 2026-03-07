import 'adapters.dart';
import 'arrow_order_core.dart';
import 'arrow_types.dart';

bool _arraysEqual(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

List<String> _applyBindablePatchToIds(
  List<String> boundArrowIds,
  BindablePatch patch,
) {
  var next = List<String>.from(boundArrowIds);

  if (patch.removeBoundArrowId != null) {
    next = next
        .where((arrowId) => arrowId != patch.removeBoundArrowId)
        .toList(growable: false);
  }

  if (patch.addBoundArrowId != null && !next.contains(patch.addBoundArrowId)) {
    next = <String>[...next, patch.addBoundArrowId!];
  }

  return next;
}

ArrowBindingState applyArrowBindingStatePatch(
  ArrowBindingState arrow,
  ArrowBindingStatePatch patch,
) => ArrowBindingState(
  id: arrow.id,
  startBinding: patch.containsKey('startBinding')
      ? patch['startBinding'] as FixedPointBinding?
      : arrow.startBinding,
  endBinding: patch.containsKey('endBinding')
      ? patch['endBinding'] as FixedPointBinding?
      : arrow.endBinding,
);

List<ArrowBindingState> applyArrowBindingStatePatches(
  List<ArrowBindingState> arrows,
  List<ArrowBindingStatePatch> patches,
) {
  if (patches.isEmpty || arrows.isEmpty) {
    return arrows;
  }

  final patchById = <String, ArrowBindingStatePatch>{
    for (final patch in patches)
      if (patch['id'] is String) patch['id'] as String: patch,
  };

  return arrows
      .map((arrow) {
        final patch = patchById[arrow.id];
        return patch != null
            ? applyArrowBindingStatePatch(arrow, patch)
            : arrow;
      })
      .toList(growable: false);
}

BindableRelationState applyBindableRelationPatch(
  BindableRelationState bindable,
  BindableRelationPatch patch,
) => BindableRelationState(
  id: bindable.id,
  boundArrowIds: List<String>.from(patch.boundArrowIds),
);

List<BindableRelationState> applyBindableRelationPatches(
  List<BindableRelationState> bindables,
  List<BindableRelationPatch> patches,
) {
  if (patches.isEmpty) {
    return bindables;
  }

  final next = List<BindableRelationState>.from(bindables);
  final indexById = <String, int>{
    for (var index = 0; index < next.length; index += 1) next[index].id: index,
  };

  for (final patch in patches) {
    final normalized = BindableRelationState(
      id: patch.id,
      boundArrowIds: List<String>.from(patch.boundArrowIds),
    );
    final index = indexById[patch.id];
    if (index == null) {
      indexById[patch.id] = next.length;
      next.add(normalized);
    } else {
      next[index] = normalized;
    }
  }

  return next;
}

List<BindableRelationPatch> reduceBindablePatchesToRelationPatches(
  List<BindableRelationState> bindables,
  List<BindablePatch> patches,
) {
  if (patches.isEmpty) {
    return <BindableRelationPatch>[];
  }

  final originalById = <String, List<String>>{
    for (final bindable in bindables)
      bindable.id: List<String>.from(bindable.boundArrowIds),
  };
  final nextById = <String, List<String>>{};

  for (final patch in patches) {
    final current = nextById[patch.id] ?? originalById[patch.id] ?? <String>[];
    nextById[patch.id] = _applyBindablePatchToIds(current, patch);
  }

  final relationPatches = <BindableRelationPatch>[];
  for (final entry in nextById.entries) {
    final id = entry.key;
    final boundArrowIds = entry.value;
    final previous = originalById[id] ?? <String>[];
    if (!_arraysEqual(previous, boundArrowIds)) {
      relationPatches.add(
        BindableRelationPatch(
          id: id,
          boundArrowIds: List<String>.from(boundArrowIds),
        ),
      );
    }
  }

  return relationPatches;
}

Map<String, List<String>> _toAnchorLookup(AnchorElementIdsLookupInput? input) {
  if (input == null) {
    return <String, List<String>>{};
  }
  if (input is Map<String, List<String>>) {
    return input;
  }
  if (input is Map) {
    final result = <String, List<String>>{};
    input.forEach((key, value) {
      if (key is String && value is List) {
        result[key] = value.cast<String>();
      }
    });
    return result;
  }
  return <String, List<String>>{};
}

ReduceArrowEngineEventsToOrderResult reduceArrowEngineEventsToOrder(
  ReduceArrowEngineEventsToOrderInput input,
) {
  final reorderOperations = <ReorderArrowAboveElementsResult>[];
  final bindingBrokenEvents = <BindingBrokenEvent>[];
  final anchorLookup = _toAnchorLookup(input.anchorElementIdsByBindableId);

  var orderedElementIds = List<String>.from(input.orderedElementIds);

  for (final event in input.events) {
    if (event is BindingBrokenEvent) {
      bindingBrokenEvents.add(event);
      continue;
    }

    if (event is ReorderArrowEvent) {
      final anchorElementIds =
          anchorLookup[event.bindableId] ?? <String>[event.bindableId];
      final reorder = reorderArrowAboveElements(
        ReorderArrowAboveElementsInput(
          orderedElementIds: orderedElementIds,
          arrowId: event.arrowId,
          anchorElementIds: anchorElementIds,
        ),
      );
      if (reorder.moved) {
        orderedElementIds = reorder.orderedElementIds;
        reorderOperations.add(reorder);
      }
    }
  }

  return ReduceArrowEngineEventsToOrderResult(
    orderedElementIds: orderedElementIds,
    moved: reorderOperations.isNotEmpty,
    reorderOperations: reorderOperations,
    bindingBrokenEvents: bindingBrokenEvents,
  );
}

ApplyEngineResultValue applyEngineResult(ApplyEngineResultInput input) {
  final arrow = applyArrowPatch(input.arrow, input.result.arrowPatch);
  final relationPatches = reduceBindablePatchesToRelationPatches(
    input.bindables,
    input.result.bindablePatches,
  );
  final bindables = applyBindableRelationPatches(
    input.bindables,
    relationPatches,
  );

  if (input.orderedElementIds == null) {
    return ApplyEngineResultValue(
      arrow: arrow,
      bindables: bindables,
      relationPatches: relationPatches,
    );
  }

  final orderResult = reduceArrowEngineEventsToOrder(
    ReduceArrowEngineEventsToOrderInput(
      orderedElementIds: input.orderedElementIds!,
      events: input.result.events,
      anchorElementIdsByBindableId: input.anchorElementIdsByBindableId,
    ),
  );

  return ApplyEngineResultValue(
    arrow: arrow,
    bindables: bindables,
    relationPatches: relationPatches,
    orderedElementIds: orderResult.orderedElementIds,
    orderChanged: orderResult.moved,
    reorderOperations: orderResult.reorderOperations,
    bindingBrokenEvents: orderResult.bindingBrokenEvents,
  );
}
