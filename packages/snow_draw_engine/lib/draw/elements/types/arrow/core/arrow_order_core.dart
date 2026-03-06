import 'arrow_hit_test.dart';
import 'arrow_types.dart';

ReorderArrowAboveElementsResult _createUnchangedResult(
  List<String> orderedElementIds,
) => ReorderArrowAboveElementsResult(
  orderedElementIds: orderedElementIds,
  moved: false,
  fromIndex: -1,
  toIndex: -1,
);

ReorderArrowAboveHoveredBindableResult _createHoveredUnchangedResult(
  List<String> orderedElementIds, {
  String? hoveredBindableId,
  List<String> anchorElementIds = const <String>[],
}) => ReorderArrowAboveHoveredBindableResult(
  orderedElementIds: orderedElementIds,
  moved: false,
  fromIndex: -1,
  toIndex: -1,
  hoveredBindableId: hoveredBindableId,
  anchorElementIds: anchorElementIds,
);

Map<String, List<String>> _toAnchorLookup(AnchorElementIdsLookupInput? input) {
  if (input == null) {
    return <String, List<String>>{};
  }
  if (input is Map<String, List<String>>) {
    return input;
  }
  if (input is Map) {
    return input.map<String, List<String>>(
      (key, value) => MapEntry(key as String, (value as List).cast<String>()),
    );
  }
  return <String, List<String>>{};
}

ReorderArrowAboveElementsResult reorderArrowAboveElements(
  ReorderArrowAboveElementsInput input,
) {
  if (input.orderedElementIds.isEmpty || input.anchorElementIds.isEmpty) {
    return _createUnchangedResult(input.orderedElementIds);
  }

  final fromIndex = input.orderedElementIds.indexOf(input.arrowId);
  if (fromIndex == -1) {
    return _createUnchangedResult(input.orderedElementIds);
  }

  final anchorIdSet = input.anchorElementIds.toSet();
  final toIndex = input.orderedElementIds.indexWhere(anchorIdSet.contains);
  if (toIndex == -1 || fromIndex >= toIndex) {
    return _createUnchangedResult(input.orderedElementIds);
  }

  final nextOrderedElementIds = List<String>.from(input.orderedElementIds);
  final arrow = nextOrderedElementIds.removeAt(fromIndex);
  nextOrderedElementIds.insert(toIndex, arrow);

  return ReorderArrowAboveElementsResult(
    orderedElementIds: nextOrderedElementIds,
    moved: true,
    fromIndex: fromIndex,
    toIndex: toIndex,
  );
}

ReorderArrowAboveHoveredBindableResult reorderArrowAboveHoveredBindable(
  ReorderArrowAboveHoveredBindableInput input,
) {
  String? hoveredBindableId;
  if (input.hoveredBindableId != null && input.hoveredBindableId!.isNotEmpty) {
    hoveredBindableId = input.hoveredBindableId;
  } else if (input.point != null && input.bindables != null) {
    hoveredBindableId = getHoveredBindable(
      input.point!,
      input.bindables!,
      input.tolerance ?? 0,
    )?.id;
  }

  if (hoveredBindableId == null) {
    return _createHoveredUnchangedResult(input.orderedElementIds);
  }

  final anchorLookup = _toAnchorLookup(input.anchorElementIdsByBindableId);
  final anchorElementIds =
      anchorLookup[hoveredBindableId] ?? <String>[hoveredBindableId];

  final reorder = reorderArrowAboveElements(
    ReorderArrowAboveElementsInput(
      orderedElementIds: input.orderedElementIds,
      arrowId: input.arrowId,
      anchorElementIds: anchorElementIds,
    ),
  );

  return ReorderArrowAboveHoveredBindableResult(
    orderedElementIds: reorder.orderedElementIds,
    moved: reorder.moved,
    fromIndex: reorder.fromIndex,
    toIndex: reorder.toIndex,
    hoveredBindableId: hoveredBindableId,
    anchorElementIds: anchorElementIds,
  );
}
