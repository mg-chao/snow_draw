import 'package:meta/meta.dart';

import 'recordable.dart';

/// Metadata for history entries.
@immutable
class HistoryMetadata {
  HistoryMetadata({
    required this.description,
    required this.recordType,
    Set<String> affectedElementIds = const <String>{},
    DateTime? timestamp,
    Map<String, dynamic>? extra,
  }) : affectedElementIds = Set<String>.unmodifiable(affectedElementIds),
       timestamp = timestamp ?? DateTime.now(),
       extra = extra == null ? null : Map<String, dynamic>.unmodifiable(extra);

  factory HistoryMetadata.forEdit({
    required String operationType,
    required Set<String> elementIds,
    Map<String, dynamic>? extra,
  }) {
    final elementCount = elementIds.length;

    return HistoryMetadata(
      description:
          '$operationType $elementCount element${elementCount == 1 ? '' : 's'}',
      recordType: HistoryRecordType.edit,
      affectedElementIds: elementIds,
      extra: extra,
    );
  }

  factory HistoryMetadata.forMove(Set<String> elementIds) =>
      HistoryMetadata.forEdit(operationType: 'Move', elementIds: elementIds);

  factory HistoryMetadata.forResize(Set<String> elementIds) =>
      HistoryMetadata.forEdit(operationType: 'Resize', elementIds: elementIds);

  factory HistoryMetadata.forRotate(Set<String> elementIds) =>
      HistoryMetadata.forEdit(operationType: 'Rotate', elementIds: elementIds);
  final String description;
  final HistoryRecordType recordType;
  final Set<String> affectedElementIds;
  final DateTime timestamp;
  final Map<String, dynamic>? extra;

  @override
  String toString() =>
      'HistoryMetadata($description, ${affectedElementIds.length} elements)';
}
