import 'package:meta/meta.dart';

@immutable
class HistoryChangeSet {
  HistoryChangeSet({
    Set<String>? modifiedIds,
    Set<String>? addedIds,
    Set<String>? removedIds,
    this.orderChanged = false,
    this.selectionChanged = false,
  }) : modifiedIds = Set<String>.unmodifiable(modifiedIds ?? const {}),
       addedIds = Set<String>.unmodifiable(addedIds ?? const {}),
       removedIds = Set<String>.unmodifiable(removedIds ?? const {});
  final Set<String> modifiedIds;
  final Set<String> addedIds;
  final Set<String> removedIds;
  final bool orderChanged;
  final bool selectionChanged;

  bool get hasElementChanges =>
      modifiedIds.isNotEmpty || addedIds.isNotEmpty || removedIds.isNotEmpty;

  Set<String> get allElementIds => {...modifiedIds, ...addedIds, ...removedIds};

  int get elementChangeCount => allElementIds.length;

  bool get isSingleElementChange => elementChangeCount == 1;

  @override
  String toString() =>
      'HistoryChangeSet(modified: ${modifiedIds.length}, '
      'added: ${addedIds.length}, '
      'removed: ${removedIds.length}, '
      'orderChanged: $orderChanged, '
      'selectionChanged: $selectionChanged)';
}
