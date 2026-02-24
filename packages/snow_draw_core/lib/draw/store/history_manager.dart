import 'package:meta/meta.dart';

import '../actions/history_coalescing.dart';
import '../config/draw_config.dart';
import '../elements/core/element_data.dart';
import '../elements/core/element_registry_interface.dart';
import '../elements/core/unknown_element_data.dart';
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

final ModuleLogger _historyFallbackLog = LogService.fallback.history;

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

@immutable
class UnknownElementInfo {
  const UnknownElementInfo({
    required this.elementType,
    required this.elementId,
    required this.source,
    this.error,
    this.stackTrace,
  });

  final String elementType;
  final String elementId;
  final String source;
  final Object? error;
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'UnknownElement(type: $elementType, id: $elementId, source: $source)';
}

typedef UnknownElementReporter = void Function(UnknownElementInfo info);

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
    UnknownElementReporter? onUnknownElement,
  }) => _historySnapshotCodec.decode(
    json,
    elementRegistry,
    onUnknownElement: onUnknownElement,
  );
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
    ElementRegistry elementRegistry, {
    UnknownElementReporter? onUnknownElement,
  }) {
    final version = json['version'];
    if (version is! int) {
      throw StateError('History snapshot version is missing or invalid');
    }
    if (version != _version) {
      throw StateError('Unsupported history snapshot version: $version');
    }

    final entriesData = _requireEntriesData(json['entries']);
    final entries = <_HistoryEntry>[];
    final seenIds = <int>{};
    for (final entryData in entriesData) {
      final id = _requireInt(entryData, 'id');
      if (!seenIds.add(id)) {
        throw StateError('Duplicate history entry id: $id');
      }

      final delta = _deltaFromJson(
        _requireMapField(entryData, 'delta'),
        elementRegistry,
        onUnknownElement: onUnknownElement,
      );
      final metadataJson = _asJsonMap(entryData['metadata']);
      final coalescingJson = _asJsonMap(entryData['coalescing']);

      entries.add(
        _HistoryEntry(
          id: id,
          delta: delta,
          metadata: metadataJson == null
              ? null
              : _metadataFromJson(metadataJson),
          coalescing: coalescingJson == null
              ? null
              : _coalescingFromJson(coalescingJson),
          recordedAt: _decodeRecordedAt(entryData['recordedAtMs']),
        ),
      );
    }

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

  List<Map<String, dynamic>> _requireEntriesData(Object? raw) {
    if (raw is! List) {
      throw StateError('History snapshot entries must be a list');
    }

    final entries = <Map<String, dynamic>>[];
    for (final value in raw) {
      final entry = _asJsonMap(value);
      if (entry == null) {
        throw StateError('History snapshot contains an invalid entry');
      }
      entries.add(entry);
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

  Map<String, dynamic> _coalescingToJson(HistoryCoalescing coalescing) => {
    'key': coalescing.key,
    'windowMs': coalescing.window.inMilliseconds,
  };

  HistoryCoalescing _coalescingFromJson(Map<String, dynamic> json) =>
      HistoryCoalescing(
        key: _requireString(json, 'key'),
        window: Duration(milliseconds: _requireInt(json, 'windowMs')),
      );

  DateTime _decodeRecordedAt(Object? raw) {
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _requireInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw StateError('History snapshot field "$key" is missing or invalid');
    }
    return value;
  }

  double _requireDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! num) {
      throw StateError('History snapshot field "$key" is missing or invalid');
    }
    return value.toDouble();
  }

  String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw StateError('History snapshot field "$key" is missing or invalid');
    }
    return value;
  }

  Map<String, dynamic> _requireMapField(Map<String, dynamic> json, String key) {
    final value = _asJsonMap(json[key]);
    if (value == null) {
      throw StateError('History snapshot field "$key" is missing or invalid');
    }
    return value;
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
    ElementRegistry elementRegistry, {
    UnknownElementReporter? onUnknownElement,
  }) {
    final beforeElements = _decodeElementMap(
      json['beforeElements'],
      elementRegistry,
      source: 'beforeElements',
      onUnknownElement: onUnknownElement,
    );
    final afterElements = _decodeElementMap(
      json['afterElements'],
      elementRegistry,
      source: 'afterElements',
      onUnknownElement: onUnknownElement,
    );

    final orderBefore = _asStringList(json['orderBefore']);
    final orderAfter = _asStringList(json['orderAfter']);
    final globalElementsBefore = _decodeOptionalJson(
      json['globalElementsBefore'],
      _globalElementsFromJson,
    );
    final globalElementsAfter = _decodeOptionalJson(
      json['globalElementsAfter'],
      _globalElementsFromJson,
    );
    final selectionBefore = _decodeOptionalJson(
      json['selectionBefore'],
      _selectionFromJson,
    );
    final selectionAfter = _decodeOptionalJson(
      json['selectionAfter'],
      _selectionFromJson,
    );

    return HistoryDelta.fromData(
      beforeElements: beforeElements,
      afterElements: afterElements,
      globalElementsBefore: globalElementsBefore,
      globalElementsAfter: globalElementsAfter,
      orderBefore: orderBefore,
      orderAfter: orderAfter,
      selectionBefore: selectionBefore,
      selectionAfter: selectionAfter,
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

  ElementState _elementFromJson(
    Map<String, dynamic> json,
    ElementRegistry elementRegistry, {
    UnknownElementReporter? onUnknownElement,
    String source = 'unknown',
  }) {
    final id = _requireString(json, 'id');
    final type = _requireString(json, 'type');
    final dataJson = _requireMapField(json, 'data');
    final data = _decodeElementData(
      elementRegistry: elementRegistry,
      elementType: type,
      elementId: id,
      dataJson: dataJson,
      source: source,
      onUnknownElement: onUnknownElement,
    );

    return ElementState(
      id: id,
      rect: _rectFromJson(_requireMapField(json, 'rect')),
      rotation: _requireDouble(json, 'rotation'),
      opacity: _requireDouble(json, 'opacity'),
      zIndex: _requireInt(json, 'zIndex'),
      data: data,
    );
  }

  Map<String, ElementState> _decodeElementMap(
    Object? rawElementsJson,
    ElementRegistry elementRegistry, {
    required String source,
    UnknownElementReporter? onUnknownElement,
  }) {
    final elementsJson = _asJsonMap(rawElementsJson);
    if (elementsJson == null) {
      throw StateError(
        'History snapshot element map "$source" is missing or invalid',
      );
    }

    final decoded = <String, ElementState>{};
    for (final entry in elementsJson.entries) {
      final elementJson = _asJsonMap(entry.value);
      if (elementJson == null) {
        throw StateError(
          'History snapshot element payload is invalid for id "${entry.key}"',
        );
      }
      decoded[entry.key] = _elementFromJson(
        elementJson,
        elementRegistry,
        onUnknownElement: onUnknownElement,
        source: source,
      );
    }
    return decoded;
  }

  Map<String, dynamic>? _asJsonMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }

    final mapped = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        return null;
      }
      mapped[key] = entry.value;
    }
    return mapped;
  }

  List<String>? _asStringList(Object? raw) {
    if (raw is! List) {
      return null;
    }

    return <String>[
      for (final value in raw)
        if (value is String) value,
    ];
  }

  T? _decodeOptionalJson<T>(
    Object? raw,
    T Function(Map<String, dynamic> json) decoder,
  ) {
    final jsonMap = _asJsonMap(raw);
    if (jsonMap == null) {
      return null;
    }
    return decoder(jsonMap);
  }

  ElementData _decodeElementData({
    required ElementRegistry elementRegistry,
    required String elementType,
    required String elementId,
    required Map<String, dynamic> dataJson,
    required String source,
    required UnknownElementReporter? onUnknownElement,
  }) {
    final definition = elementRegistry.getDefinitionByValue(elementType);
    if (definition == null) {
      _reportUnknownElement(
        onUnknownElement: onUnknownElement,
        elementType: elementType,
        elementId: elementId,
        source: '$source:definition_missing',
      );
      return UnknownElementData(originalType: elementType, rawData: dataJson);
    }

    try {
      return definition.fromJson(dataJson);
    } on Object catch (error, stackTrace) {
      _reportUnknownElement(
        onUnknownElement: onUnknownElement,
        elementType: elementType,
        elementId: elementId,
        source: '$source:deserialization_error',
        error: error,
        stackTrace: stackTrace,
      );
      return UnknownElementData(originalType: elementType, rawData: dataJson);
    }
  }

  void _reportUnknownElement({
    required UnknownElementReporter? onUnknownElement,
    required String elementType,
    required String elementId,
    required String source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final info = UnknownElementInfo(
      elementType: elementType,
      elementId: elementId,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );

    if (onUnknownElement != null) {
      onUnknownElement(info);
      return;
    }

    _historyFallbackLog.warning('Unknown element in history', {
      'type': elementType,
      'id': elementId,
      'source': source,
      'error': error?.toString(),
    });
  }

  Map<String, dynamic> _selectionToJson(SelectionState selection) => {
    'selectedIds': selection.selectedIds.toList(),
    'selectionVersion': selection.selectionVersion,
  };

  SelectionState _selectionFromJson(Map<String, dynamic> json) =>
      SelectionState(
        selectedIds:
            (json['selectedIds'] as List<dynamic>?)?.cast<String>().toSet() ??
            const {},
        selectionVersion: json['selectionVersion'] as int? ?? 0,
      );

  Map<String, dynamic> _globalElementsToJson(GlobalElementsState elements) => {
    'highlightMask': _highlightMaskToJson(elements.highlightMask),
    'watermark': _watermarkToJson(elements.watermark),
  };

  GlobalElementsState _globalElementsFromJson(Map<String, dynamic> json) =>
      GlobalElementsState(
        highlightMask: _highlightMaskFromJson(
          (json['highlightMask'] as Map<String, dynamic>?) ?? const {},
        ),
        watermark: _watermarkFromJson(
          (json['watermark'] as Map<String, dynamic>?) ?? const {},
        ),
      );

  Map<String, dynamic> _highlightMaskToJson(HighlightMaskConfig config) => {
    'maskColor': config.maskColor.toARGB32(),
    'maskOpacity': config.maskOpacity,
  };

  HighlightMaskConfig _highlightMaskFromJson(Map<String, dynamic> json) =>
      HighlightMaskConfig(
        maskColor: DrawColor(
          json['maskColor'] as int? ??
              ConfigDefaults.defaultMaskColor.toARGB32(),
        ),
        maskOpacity: (json['maskOpacity'] as num?)?.toDouble() ?? 0,
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

  WatermarkConfig _watermarkFromJson(
    Map<String, dynamic> json,
  ) => WatermarkConfig(
    color: DrawColor(
      json['color'] as int? ?? ConfigDefaults.defaultWatermarkColor.toARGB32(),
    ),
    text: json['text'] as String? ?? ConfigDefaults.defaultWatermarkText,
    fontSize:
        (json['fontSize'] as num?)?.toDouble() ??
        ConfigDefaults.defaultWatermarkFontSize,
    fontFamily: json['fontFamily'] as String? ?? '',
    angle:
        (json['angle'] as num?)?.toDouble() ??
        ConfigDefaults.defaultWatermarkAngle,
    gap:
        (json['gap'] as num?)?.toDouble() ?? ConfigDefaults.defaultWatermarkGap,
    opacity:
        (json['opacity'] as num?)?.toDouble() ??
        ConfigDefaults.defaultWatermarkOpacity,
  );

  Map<String, dynamic> _rectToJson(DrawRect rect) => {
    'minX': rect.minX,
    'minY': rect.minY,
    'maxX': rect.maxX,
    'maxY': rect.maxY,
  };

  DrawRect _rectFromJson(Map<String, dynamic> json) => DrawRect(
    minX: _requireDouble(json, 'minX'),
    minY: _requireDouble(json, 'minY'),
    maxX: _requireDouble(json, 'maxX'),
    maxY: _requireDouble(json, 'maxY'),
  );

  Map<String, dynamic> _metadataToJson(HistoryMetadata metadata) => {
    'description': metadata.description,
    'recordType': metadata.recordType.name,
    'affectedElementIds': metadata.affectedElementIds.toList(),
    'timestamp': metadata.timestamp.toIso8601String(),
    if (metadata.extra != null) 'extra': metadata.extra,
  };

  HistoryMetadata _metadataFromJson(Map<String, dynamic> json) {
    final typeName = json['recordType'] as String? ?? 'other';
    final recordType = HistoryRecordType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => HistoryRecordType.other,
    );

    return HistoryMetadata(
      description: json['description'] as String? ?? '',
      recordType: recordType,
      affectedElementIds:
          (json['affectedElementIds'] as List<dynamic>?)
              ?.cast<String>()
              .toSet() ??
          const {},
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.parse(json['timestamp'] as String),
      extra: json['extra'] as Map<String, dynamic>?,
    );
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
