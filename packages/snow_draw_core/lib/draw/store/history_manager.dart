import '../actions/history_coalescing.dart';
import '../config/draw_config.dart';
import '../elements/core/element_registry_interface.dart';
import '../history/history_metadata.dart';
import '../history/recordable.dart';
import '../models/draw_state.dart';
import '../models/element_state.dart';
import '../models/global_elements_state.dart';
import '../models/selection_state.dart';
import '../services/log/log_service.dart';
import '../types/draw_color.dart';
import '../types/draw_rect.dart';
import 'history_delta.dart';
import 'snapshot.dart';

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

  final _entries = <_HistoryEntry>[];
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

    final entry = _HistoryEntry(
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
    final currentDelta = currentEntry.delta;
    final parentState = _resolveCurrentParentState(
      currentState: currentState,
      currentDelta: currentDelta,
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

    currentEntry
      ..delta = mergedDelta
      ..metadata = metadata
      ..coalescing = coalescing
      ..recordedAt = recordedAt;

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

  HistoryManagerSnapshot snapshot() => HistoryManagerSnapshot._(
    entries: _cloneEntries(_entries),
    cursor: _cursor,
    nextEntryId: _nextEntryId,
  );

  void restore(HistoryManagerSnapshot snapshot) {
    _entries
      ..clear()
      ..addAll(_cloneEntries(snapshot._entries));

    _cursor = _clampCursor(snapshot._cursor, _entries.length);
    _nextEntryId = _resolveNextEntryId(
      requestedNextEntryId: snapshot._nextEntryId,
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

class _HistoryEntry {
  _HistoryEntry({
    required this.id,
    required this.delta,
    required this.metadata,
    required this.coalescing,
    required this.recordedAt,
  });

  final int id;
  HistoryDelta delta;
  HistoryMetadata? metadata;
  HistoryCoalescing? coalescing;
  DateTime recordedAt;

  _HistoryEntry copy() => _HistoryEntry(
    id: id,
    delta: delta,
    metadata: metadata,
    coalescing: coalescing,
    recordedAt: recordedAt,
  );
}

class HistoryManagerSnapshot {
  const HistoryManagerSnapshot._({
    required List<_HistoryEntry> entries,
    required int cursor,
    required int nextEntryId,
  }) : _entries = entries,
       _cursor = cursor,
       _nextEntryId = nextEntryId;

  final List<_HistoryEntry> _entries;
  final int _cursor;
  final int _nextEntryId;

  Map<String, dynamic> toJson() => _historySnapshotCodec.encode(this);

  static HistoryManagerSnapshot fromJson(
    Map<String, dynamic> json, {
    required ElementRegistry elementRegistry,
  }) => _historySnapshotCodec.decode(json, elementRegistry);
}

class _HistorySnapshotCodec {
  static const _version = 2;

  Map<String, dynamic> encode(HistoryManagerSnapshot snapshot) => {
    'version': _version,
    'cursor': snapshot._cursor,
    'nextEntryId': snapshot._nextEntryId,
    'entries': [for (final entry in snapshot._entries) _encodeEntry(entry)],
  };

  HistoryManagerSnapshot decode(
    Map<String, dynamic> json,
    ElementRegistry elementRegistry,
  ) {
    final version = json['version'];
    if (version != _version) {
      throw StateError('Unsupported history snapshot version: $version');
    }

    final entries = _decodeEntries(json['entries'], elementRegistry);

    final cursor = _clampCursor(
      json['cursor'] as int? ?? entries.length - 1,
      entries.length,
    );
    final nextEntryId = _resolveNextEntryId(
      requestedNextEntryId: json['nextEntryId'] as int?,
      minNextEntryId: _nextEntryIdFromEntries(entries),
    );

    return HistoryManagerSnapshot._(
      entries: entries,
      cursor: cursor,
      nextEntryId: nextEntryId,
    );
  }

  List<_HistoryEntry> _decodeEntries(
    Object? raw,
    ElementRegistry elementRegistry,
  ) {
    if (raw is! List) {
      throw StateError('History snapshot entries must be a list');
    }

    final entries = <_HistoryEntry>[];
    final seenIds = <int>{};
    for (final rawEntry in raw) {
      if (rawEntry is! Map) {
        throw StateError('History snapshot contains an invalid entry');
      }

      final entry = _asJsonMap(rawEntry, context: 'entry');
      final id = _readInt(entry, 'id');
      if (!seenIds.add(id)) {
        throw StateError('Duplicate history entry id: $id');
      }

      entries.add(
        _HistoryEntry(
          id: id,
          delta: _deltaFromJson(
            _asJsonMap(entry['delta'], context: 'delta'),
            elementRegistry,
          ),
          metadata: _metadataFromRaw(entry['metadata']),
          coalescing: _coalescingFromRaw(entry['coalescing']),
          recordedAt: DateTime.fromMillisecondsSinceEpoch(
            _readInt(entry, 'recordedAtMs'),
          ),
        ),
      );
    }
    return entries;
  }

  Map<String, dynamic> _encodeEntry(_HistoryEntry entry) => {
    'id': entry.id,
    'delta': _deltaToJson(entry.delta),
    if (entry.metadata != null) 'metadata': _metadataToJson(entry.metadata!),
    if (entry.coalescing != null)
      'coalescing': _coalescingToJson(entry.coalescing!),
    'recordedAtMs': entry.recordedAt.millisecondsSinceEpoch,
  };

  HistoryCoalescing? _coalescingFromRaw(Object? raw) {
    if (raw == null) {
      return null;
    }
    return _coalescingFromJson(_asJsonMap(raw, context: 'coalescing'));
  }

  Map<String, dynamic> _coalescingToJson(HistoryCoalescing coalescing) => {
    'key': coalescing.key,
    'windowMs': coalescing.window.inMilliseconds,
  };

  HistoryCoalescing _coalescingFromJson(Map<String, dynamic> json) =>
      HistoryCoalescing(
        key: _readString(json, 'key'),
        window: Duration(milliseconds: _readInt(json, 'windowMs')),
      );

  int _readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    throw StateError('History snapshot field "$key" is missing or invalid');
  }

  double _readDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num) {
      return value.toDouble();
    }
    throw StateError('History snapshot field "$key" is missing or invalid');
  }

  String _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      return value;
    }
    throw StateError('History snapshot field "$key" is missing or invalid');
  }

  List<String> _readStringList(Map<String, dynamic> json, String key) {
    final raw = json[key];
    if (raw is! List) {
      throw StateError('History snapshot field "$key" is missing or invalid');
    }

    final strings = <String>[];
    for (final item in raw) {
      if (item is! String) {
        throw StateError(
          'History snapshot field "$key" contains a non-string value',
        );
      }
      strings.add(item);
    }
    return strings;
  }

  Map<String, dynamic> _asJsonMap(Object? raw, {required String context}) {
    if (raw is! Map) {
      throw StateError('History snapshot field "$context" is invalid');
    }
    final mapped = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        throw StateError('History snapshot field "$context" is invalid');
      }
      mapped[key] = entry.value;
    }
    return mapped;
  }

  List<String>? _readOptionalStringList(
    Object? raw, {
    required String context,
  }) {
    if (raw == null) {
      return null;
    }
    if (raw is! List) {
      throw StateError('History snapshot field "$context" is invalid');
    }

    final strings = <String>[];
    for (final item in raw) {
      if (item is! String) {
        throw StateError('History snapshot field "$context" is invalid');
      }
      strings.add(item);
    }
    return strings;
  }

  Map<String, dynamic>? _readOptionalJsonMap(
    Object? raw, {
    required String context,
  }) {
    if (raw == null) {
      return null;
    }
    return _asJsonMap(raw, context: context);
  }

  Map<String, dynamic> _deltaToJson(HistoryDelta delta) => {
    'beforeElements': delta.beforeElements.map(
      (id, element) => MapEntry(id, _elementToJson(element)),
    ),
    'afterElements': delta.afterElements.map(
      (id, element) => MapEntry(id, _elementToJson(element)),
    ),
    if (delta.globalElementsBefore != null)
      'globalElementsBefore': _globalElementsToJson(
        delta.globalElementsBefore!,
      ),
    if (delta.globalElementsAfter != null)
      'globalElementsAfter': _globalElementsToJson(delta.globalElementsAfter!),
    if (delta.orderBefore != null) 'orderBefore': delta.orderBefore,
    if (delta.orderAfter != null) 'orderAfter': delta.orderAfter,
    if (delta.selectionBefore != null)
      'selectionBefore': _selectionToJson(delta.selectionBefore!),
    if (delta.selectionAfter != null)
      'selectionAfter': _selectionToJson(delta.selectionAfter!),
    if (delta.reindexZIndices) 'reindexZIndices': true,
  };

  HistoryDelta _deltaFromJson(
    Map<String, dynamic> json,
    ElementRegistry elementRegistry,
  ) {
    final globalBeforeJson = _readOptionalJsonMap(
      json['globalElementsBefore'],
      context: 'globalElementsBefore',
    );
    final globalAfterJson = _readOptionalJsonMap(
      json['globalElementsAfter'],
      context: 'globalElementsAfter',
    );
    final selectionBeforeJson = _readOptionalJsonMap(
      json['selectionBefore'],
      context: 'selectionBefore',
    );
    final selectionAfterJson = _readOptionalJsonMap(
      json['selectionAfter'],
      context: 'selectionAfter',
    );

    return HistoryDelta.fromData(
      beforeElements: _decodeElementMap(
        _asJsonMap(json['beforeElements'], context: 'beforeElements'),
        elementRegistry,
      ),
      afterElements: _decodeElementMap(
        _asJsonMap(json['afterElements'], context: 'afterElements'),
        elementRegistry,
      ),
      globalElementsBefore: globalBeforeJson == null
          ? null
          : _globalElementsFromJson(globalBeforeJson),
      globalElementsAfter: globalAfterJson == null
          ? null
          : _globalElementsFromJson(globalAfterJson),
      orderBefore: _readOptionalStringList(
        json['orderBefore'],
        context: 'orderBefore',
      ),
      orderAfter: _readOptionalStringList(
        json['orderAfter'],
        context: 'orderAfter',
      ),
      selectionBefore: selectionBeforeJson == null
          ? null
          : _selectionFromJson(selectionBeforeJson),
      selectionAfter: selectionAfterJson == null
          ? null
          : _selectionFromJson(selectionAfterJson),
      reindexZIndices: json['reindexZIndices'] as bool? ?? false,
    );
  }

  Map<String, dynamic> _elementToJson(ElementState element) => {
    'id': element.id,
    'rect': _rectToJson(element.rect),
    'rotation': element.rotation,
    'opacity': element.opacity,
    'zIndex': element.zIndex,
    'type': element.data.typeId.value,
    'data': element.data.toJson(),
  };

  Map<String, ElementState> _decodeElementMap(
    Map<String, dynamic> elementsJson,
    ElementRegistry elementRegistry,
  ) => {
    for (final entry in elementsJson.entries)
      entry.key: _elementFromJson(
        _asJsonMap(entry.value, context: 'element:${entry.key}'),
        elementRegistry,
      ),
  };

  ElementState _elementFromJson(
    Map<String, dynamic> json,
    ElementRegistry elementRegistry,
  ) {
    final id = _readString(json, 'id');
    final type = _readString(json, 'type');
    final dataJson = _asJsonMap(json['data'], context: 'data');
    final definition = elementRegistry.getDefinitionByValue(type);
    if (definition == null) {
      throw StateError(
        'Unknown element type "$type" while decoding history for element "$id"',
      );
    }
    return ElementState(
      id: id,
      rect: _rectFromJson(_asJsonMap(json['rect'], context: 'rect')),
      rotation: _readDouble(json, 'rotation'),
      opacity: _readDouble(json, 'opacity'),
      zIndex: _readInt(json, 'zIndex'),
      data: definition.fromJson(dataJson),
    );
  }

  HistoryMetadata? _metadataFromRaw(Object? raw) {
    if (raw == null) {
      return null;
    }
    return _metadataFromJson(_asJsonMap(raw, context: 'metadata'));
  }

  Map<String, dynamic> _selectionToJson(SelectionState selection) => {
    'selectedIds': selection.selectedIds.toList(),
    'selectionVersion': selection.selectionVersion,
  };

  SelectionState _selectionFromJson(Map<String, dynamic> json) =>
      SelectionState(
        selectedIds: _readStringList(json, 'selectedIds').toSet(),
        selectionVersion: _readInt(json, 'selectionVersion'),
      );

  Map<String, dynamic> _globalElementsToJson(GlobalElementsState elements) => {
    'highlightMask': _highlightMaskToJson(elements.highlightMask),
    'watermark': _watermarkToJson(elements.watermark),
  };

  GlobalElementsState _globalElementsFromJson(Map<String, dynamic> json) =>
      GlobalElementsState(
        highlightMask: _highlightMaskFromJson(
          _asJsonMap(json['highlightMask'], context: 'highlightMask'),
        ),
        watermark: _watermarkFromJson(
          _asJsonMap(json['watermark'], context: 'watermark'),
        ),
      );

  Map<String, dynamic> _highlightMaskToJson(HighlightMaskConfig config) => {
    'maskColor': config.maskColor.toARGB32(),
    'maskOpacity': config.maskOpacity,
  };

  HighlightMaskConfig _highlightMaskFromJson(Map<String, dynamic> json) =>
      HighlightMaskConfig(
        maskColor: DrawColor(_readInt(json, 'maskColor')),
        maskOpacity: _readDouble(json, 'maskOpacity'),
      );

  Map<String, dynamic> _watermarkToJson(WatermarkConfig config) => {
    'color': config.color.toARGB32(),
    'text': config.text,
    'fontSize': config.fontSize,
    'fontFamily': config.fontFamily,
    'angle': config.angle,
    'gap': config.gap,
    'opacity': config.opacity,
  };

  WatermarkConfig _watermarkFromJson(Map<String, dynamic> json) =>
      WatermarkConfig(
        color: DrawColor(_readInt(json, 'color')),
        text: _readString(json, 'text'),
        fontSize: _readDouble(json, 'fontSize'),
        fontFamily: _readString(json, 'fontFamily'),
        angle: _readDouble(json, 'angle'),
        gap: _readDouble(json, 'gap'),
        opacity: _readDouble(json, 'opacity'),
      );

  Map<String, dynamic> _rectToJson(DrawRect rect) => {
    'minX': rect.minX,
    'minY': rect.minY,
    'maxX': rect.maxX,
    'maxY': rect.maxY,
  };

  DrawRect _rectFromJson(Map<String, dynamic> json) => DrawRect(
    minX: _readDouble(json, 'minX'),
    minY: _readDouble(json, 'minY'),
    maxX: _readDouble(json, 'maxX'),
    maxY: _readDouble(json, 'maxY'),
  );

  Map<String, dynamic> _metadataToJson(HistoryMetadata metadata) => {
    'description': metadata.description,
    'recordType': metadata.recordType.name,
    'affectedElementIds': metadata.affectedElementIds.toList(),
    'timestamp': metadata.timestamp.toIso8601String(),
    if (metadata.extra != null) 'extra': metadata.extra,
  };

  HistoryMetadata _metadataFromJson(Map<String, dynamic> json) {
    final recordType = _parseRecordType(_readString(json, 'recordType'));
    return HistoryMetadata(
      description: _readString(json, 'description'),
      recordType: recordType,
      affectedElementIds: _readStringList(json, 'affectedElementIds').toSet(),
      timestamp: DateTime.parse(_readString(json, 'timestamp')),
      extra: _readOptionalJsonMap(json['extra'], context: 'extra'),
    );
  }

  HistoryRecordType _parseRecordType(String name) {
    for (final type in HistoryRecordType.values) {
      if (type.name == name) {
        return type;
      }
    }
    throw StateError('Unsupported history record type: $name');
  }
}

final _historySnapshotCodec = _HistorySnapshotCodec();

List<_HistoryEntry> _cloneEntries(Iterable<_HistoryEntry> entries) => [
  for (final entry in entries) entry.copy(),
];

int _resolveNextEntryId({
  required int? requestedNextEntryId,
  required int minNextEntryId,
}) {
  final resolved = requestedNextEntryId ?? minNextEntryId;
  return resolved < minNextEntryId ? minNextEntryId : resolved;
}

int _nextEntryIdFromEntries(List<_HistoryEntry> entries) {
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
