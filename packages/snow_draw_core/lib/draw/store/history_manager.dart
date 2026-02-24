import 'package:meta/meta.dart';

import '../actions/history_coalescing.dart';
import '../history/history_metadata.dart';
import '../models/draw_state.dart';
import '../services/log/log_service.dart';
import 'history_delta.dart';
import 'snapshot.dart';

/// Immutable snapshot entry used by [HistoryManagerSnapshot].
@immutable
class HistorySnapshotEntry {
  const HistorySnapshotEntry({
    required this.id,
    required this.delta,
    required this.recordedAt,
    this.metadata,
    this.coalescing,
  });

  final int id;
  final HistoryDelta delta;
  final DateTime recordedAt;
  final HistoryMetadata? metadata;
  final HistoryCoalescing? coalescing;

  HistorySnapshotEntry copyWith({
    HistoryDelta? delta,
    DateTime? recordedAt,
    Object? metadata = _unset,
    Object? coalescing = _unset,
  }) => HistorySnapshotEntry(
    id: id,
    delta: delta ?? this.delta,
    recordedAt: recordedAt ?? this.recordedAt,
    metadata: identical(metadata, _unset)
        ? this.metadata
        : metadata as HistoryMetadata?,
    coalescing: identical(coalescing, _unset)
        ? this.coalescing
        : coalescing as HistoryCoalescing?,
  );
}

/// Serializable-free history state snapshot.
@immutable
class HistoryManagerSnapshot {
  HistoryManagerSnapshot({
    required Iterable<HistorySnapshotEntry> entries,
    required this.cursor,
    required this.nextEntryId,
  }) : entries = List<HistorySnapshotEntry>.unmodifiable(entries);

  final List<HistorySnapshotEntry> entries;
  final int cursor;
  final int nextEntryId;

  HistoryManagerSnapshot copyWith({
    Iterable<HistorySnapshotEntry>? entries,
    int? cursor,
    int? nextEntryId,
  }) => HistoryManagerSnapshot(
    entries: entries ?? this.entries,
    cursor: cursor ?? this.cursor,
    nextEntryId: nextEntryId ?? this.nextEntryId,
  );
}

/// Manages undo/redo history as a linear sequence of deltas.
class HistoryManager {
  HistoryManager({this.maxHistoryLength = 50, LogService? logService})
    : _log = logService?.history {
    if (maxHistoryLength < 1) {
      throw ArgumentError.value(
        maxHistoryLength,
        'maxHistoryLength',
        'must be greater than or equal to 1',
      );
    }
  }

  final int maxHistoryLength;
  final ModuleLogger? _log;

  final _entries = <HistorySnapshotEntry>[];
  var _cursor = -1;
  var _nextEntryId = 0;

  bool get canUndo => _cursor >= 0;
  bool get canRedo => _cursor < _entries.length - 1;

  int get undoLength => _cursor + 1;
  int get redoLength => _entries.length - _cursor - 1;

  List<String> get undoDescriptions => <String>[
    for (var index = 0; index <= _cursor; index++)
      _entries[index].metadata?.description ?? '',
  ];

  List<String> get redoDescriptions => <String>[
    for (var index = _cursor + 1; index < _entries.length; index++)
      _entries[index].metadata?.description ?? '',
  ];

  bool record(
    HistorySnapshot before,
    HistorySnapshot after, {
    HistoryMetadata? metadata,
    HistoryCoalescing? coalescing,
    DrawState? currentState,
    DateTime? recordedAt,
  }) {
    final now = recordedAt ?? DateTime.now();

    if (coalescing != null && currentState != null) {
      final coalesced = _tryCoalesceCurrentRecord(
        after: after,
        metadata: metadata,
        coalescing: coalescing,
        currentState: currentState,
        includeSelection: before.includeSelection,
        recordedAt: now,
      );
      if (coalesced != null) {
        return coalesced;
      }
    }

    final delta = HistoryDelta.fromSnapshots(before, after);
    if (!delta.hasChanges) {
      _log?.trace('History record skipped (no changes)', {
        'description': metadata?.description,
      });
      return false;
    }

    _dropRedoEntries();

    final entry = HistorySnapshotEntry(
      id: _nextEntryId++,
      delta: delta,
      metadata: metadata,
      coalescing: coalescing,
      recordedAt: now,
    );
    _entries.add(entry);
    _cursor = _entries.length - 1;

    _log?.trace('History record', {
      'entryId': entry.id,
      'description': metadata?.description,
      'changedElements':
          delta.beforeElements.length + delta.afterElements.length,
      'orderChanged': delta.orderBefore != null,
      'selectionChanged': delta.selectionChanged,
    });

    _pruneIfNeeded();
    return true;
  }

  bool? _tryCoalesceCurrentRecord({
    required HistorySnapshot after,
    required HistoryMetadata? metadata,
    required HistoryCoalescing coalescing,
    required DrawState currentState,
    required bool includeSelection,
    required DateTime recordedAt,
  }) {
    if (!_canCoalesceCurrent(coalescing: coalescing, recordedAt: recordedAt)) {
      return null;
    }

    final currentEntry = _entries[_cursor];
    final parentState = _resolveCurrentParentState(
      currentState: currentState,
      currentDelta: currentEntry.delta,
    );
    if (parentState == null) {
      return null;
    }

    final mergedDelta = _buildCoalescedDelta(
      parentState: parentState,
      afterSnapshot: after,
      includeSelection: includeSelection,
    );

    if (!mergedDelta.hasChanges) {
      _entries.removeAt(_cursor);
      _cursor -= 1;
      _log?.trace('History coalesced and removed empty entry', {
        'coalescingKey': coalescing.key,
      });
      return false;
    }

    _entries[_cursor] = currentEntry.copyWith(
      delta: mergedDelta,
      metadata: metadata,
      coalescing: coalescing,
      recordedAt: recordedAt,
    );

    _log?.trace('History coalesced into current entry', {
      'entryId': currentEntry.id,
      'coalescingKey': coalescing.key,
      'description': metadata?.description,
    });
    return true;
  }

  HistoryDelta _buildCoalescedDelta({
    required DrawState parentState,
    required HistorySnapshot afterSnapshot,
    required bool includeSelection,
  }) {
    final mergedBefore = _snapshotForCoalescedState(
      state: parentState,
      includeSelection: includeSelection,
    );
    return HistoryDelta.fromSnapshots(mergedBefore, afterSnapshot);
  }

  HistorySnapshot _snapshotForCoalescedState({
    required DrawState state,
    required bool includeSelection,
  }) => PersistentSnapshot.fromState(state, includeSelection: includeSelection);

  bool _canCoalesceCurrent({
    required HistoryCoalescing coalescing,
    required DateTime recordedAt,
  }) {
    if (_entries.isEmpty || _cursor != _entries.length - 1) {
      return false;
    }
    final active = _entries[_cursor].coalescing;
    if (active == null || active.key != coalescing.key) {
      return false;
    }
    final expiresAt = _entries[_cursor].recordedAt.add(coalescing.window);
    return !recordedAt.isAfter(expiresAt);
  }

  DrawState? _resolveCurrentParentState({
    required DrawState currentState,
    required HistoryDelta currentDelta,
  }) {
    try {
      return currentDelta.applyBackward(currentState);
    } on Object catch (error) {
      _log?.warning('History coalescing anchor resolution failed', {
        'cursor': _cursor,
        'error': error.toString(),
      });
      return null;
    }
  }

  DrawState? undo(DrawState currentState) {
    if (!canUndo) {
      _log?.trace('History undo skipped', {'reason': 'empty'});
      return null;
    }

    final entry = _entries[_cursor];
    final restoredState = entry.delta.applyBackward(currentState);
    _cursor -= 1;
    _log?.trace('History undo', {'entryId': entry.id});
    return restoredState;
  }

  DrawState? redo(DrawState currentState) {
    if (!canRedo) {
      _log?.trace('History redo skipped', {'reason': 'empty'});
      return null;
    }

    final targetIndex = _cursor + 1;
    final entry = _entries[targetIndex];
    final restoredState = entry.delta.applyForward(currentState);
    _cursor = targetIndex;
    _log?.trace('History redo', {'entryId': entry.id});
    return restoredState;
  }

  void clear() {
    _log?.trace('History cleared', {
      'undoLength': undoLength,
      'redoLength': redoLength,
    });
    _entries.clear();
    _cursor = -1;
    _nextEntryId = 0;
  }

  HistoryManagerSnapshot snapshot() => HistoryManagerSnapshot(
    entries: _entries,
    cursor: _cursor,
    nextEntryId: _nextEntryId,
  );

  void restore(HistoryManagerSnapshot snapshot) {
    _entries
      ..clear()
      ..addAll(snapshot.entries);

    _cursor = _clampCursor(snapshot.cursor, _entries.length);
    _nextEntryId = _resolveNextEntryId(
      requestedNextEntryId: snapshot.nextEntryId,
      minNextEntryId: _nextEntryIdFromEntries(_entries),
    );
  }

  void _dropRedoEntries() {
    if (!canRedo) {
      return;
    }
    final removeStart = _cursor + 1;
    final removedCount = _entries.length - removeStart;
    _entries.removeRange(removeStart, _entries.length);
    _log?.trace('History redo entries discarded', {
      'removedCount': removedCount,
    });
  }

  void _pruneIfNeeded() {
    final overflow = _entries.length - maxHistoryLength;
    if (overflow <= 0) {
      return;
    }

    _entries.removeRange(0, overflow);
    _cursor -= overflow;
    if (_cursor < -1) {
      _cursor = -1;
    }

    _log?.debug('History pruned', {
      'overflow': overflow,
      'maxHistoryLength': maxHistoryLength,
    });
  }
}

const _unset = Object();

int _resolveNextEntryId({
  required int requestedNextEntryId,
  required int minNextEntryId,
}) => requestedNextEntryId < minNextEntryId
    ? minNextEntryId
    : requestedNextEntryId;

int _nextEntryIdFromEntries(List<HistorySnapshotEntry> entries) {
  if (entries.isEmpty) {
    return 0;
  }

  var maxId = entries.first.id;
  for (var index = 1; index < entries.length; index++) {
    final id = entries[index].id;
    if (id > maxId) {
      maxId = id;
    }
  }
  return maxId + 1;
}

int _clampCursor(int cursor, int entryCount) {
  if (entryCount == 0) {
    return -1;
  }
  if (cursor < -1) {
    return -1;
  }
  if (cursor >= entryCount) {
    return entryCount - 1;
  }
  return cursor;
}
