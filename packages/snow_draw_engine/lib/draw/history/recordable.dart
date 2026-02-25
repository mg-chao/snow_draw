/// Marker interface for actions that should be recorded in history.
abstract interface class Recordable {
  String get historyDescription;
  HistoryRecordType get recordType;
}

/// Categories for recorded history entries.
enum HistoryRecordType { edit, create, delete, style, selection, other }
