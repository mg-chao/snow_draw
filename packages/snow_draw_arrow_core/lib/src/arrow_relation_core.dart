class BoundRelationEntry {
  const BoundRelationEntry({required this.id, required this.type});

  final String id;
  final String type;
}

List<TEntry>? _normalizeRelationEntries<TEntry extends BoundRelationEntry>(
  List<TEntry>? entries,
) => entries;

bool areBoundRelationEntriesEqual<TEntry extends BoundRelationEntry>(
  List<TEntry>? left,
  List<TEntry>? right,
) {
  final normalizedLeft = _normalizeRelationEntries(left);
  final normalizedRight = _normalizeRelationEntries(right);

  if (identical(normalizedLeft, normalizedRight)) {
    return true;
  }
  if (normalizedLeft == null || normalizedRight == null) {
    return false;
  }
  if (normalizedLeft.length != normalizedRight.length) {
    return false;
  }

  for (var index = 0; index < normalizedLeft.length; index += 1) {
    final leftEntry = normalizedLeft[index];
    final rightEntry = normalizedRight[index];
    if (leftEntry.id != rightEntry.id || leftEntry.type != rightEntry.type) {
      return false;
    }
  }

  return true;
}

List<TEntry>? mergeBoundRelationEntries<TEntry extends BoundRelationEntry>({
  required List<TEntry>? entries,
  required String targetType,
  required List<String> targetIds,
}) {
  final normalized = entries ?? <TEntry>[];
  final preserved = normalized
      .where((entry) => entry.type != targetType)
      .toList();
  final next = <TEntry>[
    ...preserved,
    ...targetIds.map(
      (id) => BoundRelationEntry(id: id, type: targetType) as TEntry,
    ),
  ];

  return next.isNotEmpty ? next : null;
}

List<TEntry>?
mergeArrowBoundRelationEntries<TEntry extends BoundRelationEntry>({
  required List<TEntry>? entries,
  required List<String> boundArrowIds,
}) => mergeBoundRelationEntries<TEntry>(
  entries: entries,
  targetType: 'arrow',
  targetIds: boundArrowIds,
);
