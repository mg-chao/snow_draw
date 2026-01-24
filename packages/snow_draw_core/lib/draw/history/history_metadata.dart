import 'package:meta/meta.dart';

import 'recordable.dart';

/// Metadata for history entries.
@immutable
class HistoryMetadata {
  HistoryMetadata({
    required this.description,
    required this.recordType,
    this.affectedElementIds = const {},
    DateTime? timestamp,
    this.extra,
  }) : timestamp = timestamp ?? DateTime.now();

  factory HistoryMetadata.forEdit({
    required String operationType,
    required Set<String> elementIds,
    Map<String, dynamic>? extra,
  }) {
    final count = elementIds.length;
    final description = count == 1
        ? '$operationType 1 element'
        : '$operationType $count elements';

    return HistoryMetadata(
      description: description,
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
