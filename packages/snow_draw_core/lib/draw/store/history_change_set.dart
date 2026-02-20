import 'package:meta/meta.dart';

@immutable
class HistoryChangeSet {
  HistoryChangeSet({
    Set<String>? modifiedIds,
    Set<String>? addedIds,
    Set<String>? removedIds,
    this.orderChanged = false,
    this.globalElementsChanged = false,
    this.selectionChanged = false,
    this.reindexZIndices = false,
  }) : modifiedIds = _freezeIds(modifiedIds),
       addedIds = _freezeIds(addedIds),
       removedIds = _freezeIds(removedIds),
       allElementIds = Set<String>.unmodifiable({
         ...?modifiedIds,
         ...?addedIds,
         ...?removedIds,
       });
  final Set<String> modifiedIds;
  final Set<String> addedIds;
  final Set<String> removedIds;
  final Set<String> allElementIds;
  final bool orderChanged;
  final bool globalElementsChanged;
  final bool selectionChanged;
  final bool reindexZIndices;

  bool get hasElementChanges => allElementIds.isNotEmpty;

  int get elementChangeCount => allElementIds.length;

  bool get isSingleElementChange => allElementIds.length == 1;

  @override
  String toString() =>
      'HistoryChangeSet(modified: ${modifiedIds.length}, '
      'added: ${addedIds.length}, '
      'removed: ${removedIds.length}, '
      'orderChanged: $orderChanged, '
      'globalElementsChanged: $globalElementsChanged, '
      'selectionChanged: $selectionChanged, '
      'reindexZIndices: $reindexZIndices)';
}

Set<String> _freezeIds(Set<String>? ids) => ids == null || ids.isEmpty
    ? const <String>{}
    : Set<String>.unmodifiable(ids);
