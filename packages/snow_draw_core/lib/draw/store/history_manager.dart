import 'package:meta/meta.dart';

import '../elements/core/element_data.dart';
import '../elements/core/element_registry_interface.dart';
import '../elements/core/element_type_id.dart';
import '../elements/core/unknown_element_data.dart';
import '../history/history_metadata.dart';
import '../history/recordable.dart';
import '../models/draw_state.dart';
import '../models/element_state.dart';
import '../models/selection_state.dart';
import '../services/log/log_service.dart';
import '../types/draw_rect.dart';
import 'history_change_set.dart';
import 'history_delta.dart';
import 'snapshot.dart';

final ModuleLogger _historyFallbackLog = LogService.fallback.history;

/// Manages undo/redo history as a branching tree of deltas.
///
/// ## Tree Structure
///
/// History is stored as a tree where:
/// - Each **node** represents a state in the history
/// - Each **edge** (parent→child) represents a delta (state change)
/// - The **root** node is the initial state (no delta)
/// - The **current** node is the active state the user sees
///
/// ``` md
///        root
///         |
///      delta1
///         |
///       node1 ← current
///       /   \
///   delta2  delta3
///     /       \
///  node2     node3
/// ```
///
/// ## Branching Behavior
///
/// When the user undoes and then makes a new change, a **branch** is created:
/// 1. User creates element A (node1)
/// 2. User undoes → back to root
/// 3. User creates element B → creates node2 as a sibling of node1
///
/// Both branches are preserved. The user can redo to either node1 or node2.
///
/// ## Navigation
///
/// - **Undo**: Move current pointer to parent node, apply delta backward
/// - **Redo**: Move current pointer to a child node, apply delta forward
/// - **Branch selection**: When multiple children exist, user can choose which
///   branch to follow during redo
///
/// ## Pruning
///
/// To prevent unbounded memory growth, the tree is pruned when depth exceeds
/// [maxHistoryLength]. Pruning removes old nodes while preserving recent
/// branch points (up to [maxBranchPoints]) to maintain user's branching
/// history where it matters most.
class HistoryManager {
  HistoryManager({
    this.maxHistoryLength = 50,
    this.maxBranchPoints = 8,
    LogService? logService,
  }) : _log = logService?.history {
    if (maxHistoryLength < 1) {
      throw ArgumentError.value(
        maxHistoryLength,
        'maxHistoryLength',
        'must be greater than or equal to 1',
      );
    }
    if (maxBranchPoints < 0) {
      throw ArgumentError.value(
        maxBranchPoints,
        'maxBranchPoints',
        'must be greater than or equal to 0',
      );
    }
    _root = _HistoryNode.root(_nextNodeId++);
    _normalizeRootPayload();
    _current = _root;
  }
  final int maxHistoryLength;
  final int maxBranchPoints;
  late _HistoryNode _root;
  late _HistoryNode _current;
  final ModuleLogger? _log;
  var _nextNodeId = 0;

  bool get canUndo => _current.parent != null;
  bool get canRedo => _current.children.isNotEmpty;

  int get undoLength => _pathFromRoot(_current).length - 1;
  int get redoLength => _defaultRedoPath().length;

  List<String> get undoDescriptions => _pathFromRoot(
    _current,
  ).skip(1).map((entry) => entry.metadata?.description ?? '').toList();

  List<String> get redoDescriptions => _defaultRedoPath()
      .map((entry) => entry.metadata?.description ?? '')
      .toList();

  List<HistoryBranch> get redoBranches => _current.children
      .asMap()
      .entries
      .map(
        (entry) => HistoryBranch(
          index: entry.key,
          nodeId: entry.value.id,
          metadata: entry.value.metadata,
        ),
      )
      .toList();

  bool record(
    HistorySnapshot before,
    HistorySnapshot after, {
    HistoryMetadata? metadata,
    HistoryChangeSet? changes,
  }) {
    final delta = HistoryDelta.fromSnapshots(before, after, changes: changes);
    if (!delta.hasChanges) {
      _log?.debug('History record skipped (no changes)', {
        'description': metadata?.description,
      });
      return false;
    }

    final node = _HistoryNode(
      id: _nextNodeId++,
      parent: _current,
      delta: delta,
      metadata: metadata,
    );
    _current.children.add(node);
    _current = node;
    _log?.debug('History record', {
      'nodeId': node.id,
      'parentId': node.parent?.id,
      'description': metadata?.description,
      'changedElements':
          delta.beforeElements.length + delta.afterElements.length,
      'orderChanged': delta.orderBefore != null,
      'selectionChanged': delta.selectionChanged,
    });
    _pruneIfNeeded();
    return true;
  }

  DrawState? undo(DrawState currentState) {
    final parent = _current.parent;
    final delta = _current.delta;
    if (parent == null || delta == null) {
      _log?.debug('History undo skipped', {'reason': 'no_parent'});
      return null;
    }

    final restoredState = delta.applyBackward(currentState);
    _log?.info('History undo', {'nodeId': _current.id, 'parentId': parent.id});
    _current = parent;
    return restoredState;
  }

  DrawState? redo(DrawState currentState, {int? branchIndex}) {
    if (_current.children.isEmpty) {
      _log?.debug('History redo skipped', {'reason': 'no_children'});
      return null;
    }

    final resolvedIndex = branchIndex ?? _current.children.length - 1;
    if (resolvedIndex < 0 || resolvedIndex >= _current.children.length) {
      _log?.debug('History redo skipped', {
        'reason': 'invalid_branch',
        'branchIndex': branchIndex,
      });
      return null;
    }

    final child = _current.children[resolvedIndex];
    final delta = child.delta;
    if (delta == null) {
      _log?.debug('History redo skipped', {'reason': 'missing_delta'});
      return null;
    }

    final restoredState = delta.applyForward(currentState);
    _log?.info('History redo', {
      'nodeId': child.id,
      'branchIndex': resolvedIndex,
    });
    _current = child;
    return restoredState;
  }

  void clear() {
    _log?.info('History cleared', {
      'undoLength': undoLength,
      'redoLength': redoLength,
    });
    _nextNodeId = 0;
    _root = _HistoryNode.root(_nextNodeId++);
    _normalizeRootPayload();
    _current = _root;
  }

  HistoryManagerSnapshot snapshot() {
    final clone = _cloneTree(_root);
    return HistoryManagerSnapshot._(clone.root, _current.id, _nextNodeId);
  }

  void restore(HistoryManagerSnapshot snapshot) {
    final clone = _cloneTree(snapshot._root);
    _root = clone.root;
    _normalizeRootPayload();
    _current = clone.byId[snapshot._currentId] ?? _root;
    _nextNodeId = snapshot._nextNodeId;
  }

  /// Returns the path from root to the given node.
  ///
  /// Walks up the tree from [node] to root, collecting all nodes along the way.
  /// Returns the path in root-first order (reversed from traversal order).
  ///
  /// Used to calculate depth and identify branch points along the current path.
  List<_HistoryNode> _pathFromRoot(_HistoryNode node) {
    final path = <_HistoryNode>[];
    var current = node;
    while (true) {
      path.add(current);
      if (current.parent == null) {
        break;
      }
      current = current.parent!;
    }
    return path.reversed.toList();
  }

  /// Returns the default redo path from current node to a leaf.
  ///
  /// When multiple redo branches exist, this determines which branch to follow
  /// by default. Always follows the **last child** at each branch point, which
  /// corresponds to the most recently created branch.
  ///
  /// Used to calculate redo depth and provide redo descriptions.
  List<_HistoryNode> _defaultRedoPath() {
    final path = <_HistoryNode>[];
    var current = _current;
    while (current.children.isNotEmpty) {
      current = current.children.last;
      path.add(current);
    }
    return path;
  }

  /// Prunes the history tree when it exceeds maximum depth.
  ///
  /// ## Algorithm Overview
  ///
  /// When the path from root to current exceeds [maxHistoryLength], old nodes
  /// are removed by making a deeper node the new root. This algorithm balances
  /// two goals:
  /// 1. **Limit depth**: Keep history within memory bounds
  /// 2. **Preserve branches**: Maintain recent branch points for user
  ///  navigation
  ///
  /// ## Basic Pruning (No Branch Preservation)
  ///
  /// Without branch preservation, pruning simply counts back from current:
  /// ``` md
  /// depth = 52, maxHistoryLength = 50
  /// stepsToMove = 52 - 50 = 2
  /// newRoot = current.parent.parent (2 steps up)
  /// ```
  ///
  /// ## Branch Point Preservation
  ///
  /// When [maxBranchPoints] > 0, pruning can move the new root slightly
  /// earlier to preserve nearby branch points. The move-back window is
  /// capped to [maxBranchPoints] steps before the basic pruning boundary.
  ///
  /// This keeps memory bounded while retaining recent branching context:
  /// max depth <= maxHistoryLength + maxBranchPoints.
  ///
  /// ## Implementation Steps
  ///
  /// 1. Calculate basic newRoot index from [maxHistoryLength]
  /// 2. Scan backward up to [maxBranchPoints] steps
  /// 3. Move newRoot to include recent branch points in that window
  /// 4. Detach newRoot from parent to make it the new root
  void _pruneIfNeeded() {
    final path = _pathFromRoot(_current);
    final depth = path.length - 1;
    if (depth <= maxHistoryLength) {
      return;
    }

    final candidateIndex = depth - maxHistoryLength;
    var resolvedIndex = candidateIndex;

    if (maxBranchPoints > 0 && candidateIndex > 0) {
      final earliestAllowedIndex = candidateIndex - maxBranchPoints < 0
          ? 0
          : candidateIndex - maxBranchPoints;
      var preservedBranchCount = 0;

      for (
        var index = candidateIndex - 1;
        index >= earliestAllowedIndex && preservedBranchCount < maxBranchPoints;
        index--
      ) {
        if (path[index].children.length <= 1) {
          continue;
        }
        resolvedIndex = index;
        preservedBranchCount++;
      }
    }

    final newRoot = path[resolvedIndex];
    final oldParent = newRoot.parent;
    if (oldParent != null) {
      oldParent.children.remove(newRoot);
      _root = newRoot;
      _normalizeRootPayload();
      _log?.debug('History pruned', {
        'newRootId': newRoot.id,
        'depth': depth,
        'maxHistoryLength': maxHistoryLength,
        'maxBranchPoints': maxBranchPoints,
        'candidateIndex': candidateIndex,
        'resolvedIndex': resolvedIndex,
      });
    }
  }

  void _normalizeRootPayload() {
    _root
      ..parent = null
      ..delta = null
      ..metadata = null;
  }
}

@immutable
class HistoryBranch {
  const HistoryBranch({
    required this.index,
    required this.nodeId,
    this.metadata,
  });
  final int index;
  final int nodeId;
  final HistoryMetadata? metadata;

  String get description => metadata?.description ?? '';
}

class _HistoryNode {
  _HistoryNode({
    required this.id,
    required this.parent,
    required this.delta,
    required this.metadata,
    List<_HistoryNode>? children,
  }) : children = children ?? [];

  _HistoryNode.root(this.id)
    : parent = null,
      delta = null,
      metadata = null,
      children = [];
  final int id;
  _HistoryNode? parent;
  final List<_HistoryNode> children;
  HistoryDelta? delta;
  HistoryMetadata? metadata;

  @override
  String toString() => 'HistoryNode(id: $id, children: ${children.length})';
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
  const HistoryManagerSnapshot._(this._root, this._currentId, this._nextNodeId);
  final _HistoryNode _root;
  final int _currentId;
  final int _nextNodeId;

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

class _HistoryTreeClone {
  const _HistoryTreeClone({required this.root, required this.byId});
  final _HistoryNode root;
  final Map<int, _HistoryNode> byId;
}

_HistoryTreeClone _cloneTree(_HistoryNode root) {
  final byId = <int, _HistoryNode>{};

  _HistoryNode cloneNode(_HistoryNode node) {
    final cloned = _HistoryNode(
      id: node.id,
      parent: null,
      delta: node.delta,
      metadata: node.metadata,
    );
    byId[cloned.id] = cloned;
    for (final child in node.children) {
      final childClone = cloneNode(child)..parent = cloned;
      cloned.children.add(childClone);
    }
    return cloned;
  }

  final clonedRoot = cloneNode(root);
  return _HistoryTreeClone(root: clonedRoot, byId: byId);
}

class _HistorySnapshotCodec {
  static const _version = 1;

  Map<String, dynamic> encode(HistoryManagerSnapshot snapshot) {
    final nodes = <Map<String, dynamic>>[];
    void visit(_HistoryNode node) {
      nodes.add(_encodeNode(node));
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(snapshot._root);

    return {
      'version': _version,
      'rootId': snapshot._root.id,
      'currentId': snapshot._currentId,
      'nextNodeId': snapshot._nextNodeId,
      'nodes': nodes,
    };
  }

  HistoryManagerSnapshot decode(
    Map<String, dynamic> json,
    ElementRegistry elementRegistry, {
    UnknownElementReporter? onUnknownElement,
  }) {
    final version = json['version'] as int? ?? _version;
    if (version != _version) {
      throw StateError('Unsupported history snapshot version: $version');
    }

    final nodesData = json['nodes'] as List<dynamic>? ?? const [];
    final byId = <int, _HistoryNode>{};

    for (final entry in nodesData) {
      final data = entry as Map<String, dynamic>;
      final id = data['id'] as int;
      final deltaJson = data['delta'] as Map<String, dynamic>?;
      final metadataJson = data['metadata'] as Map<String, dynamic>?;
      byId[id] = _HistoryNode(
        id: id,
        parent: null,
        delta: deltaJson == null
            ? null
            : _deltaFromJson(
                deltaJson,
                elementRegistry,
                onUnknownElement: onUnknownElement,
              ),
        metadata: metadataJson == null ? null : _metadataFromJson(metadataJson),
      );
    }

    for (final entry in nodesData) {
      final data = entry as Map<String, dynamic>;
      final id = data['id'] as int;
      final node = byId[id];
      if (node == null) {
        continue;
      }
      final parentId = data['parentId'] as int?;
      if (parentId != null) {
        node.parent = byId[parentId];
      }
      final childrenIds = (data['children'] as List<dynamic>? ?? const [])
          .cast<int>();
      for (final childId in childrenIds) {
        final child = byId[childId];
        if (child != null) {
          node.children.add(child);
        }
      }
    }

    final rootId = json['rootId'] as int? ?? 0;
    final currentId = json['currentId'] as int? ?? rootId;
    final nextNodeId =
        json['nextNodeId'] as int? ??
        (byId.isEmpty ? 1 : (byId.keys.reduce((a, b) => a > b ? a : b) + 1));

    final root = (byId[rootId] ?? _HistoryNode.root(rootId))
      ..parent = null
      ..delta = null
      ..metadata = null;
    return HistoryManagerSnapshot._(root, currentId, nextNodeId);
  }

  Map<String, dynamic> _encodeNode(_HistoryNode node) => {
    'id': node.id,
    'parentId': node.parent?.id,
    'children': node.children.map((child) => child.id).toList(),
    if (node.delta != null) 'delta': _deltaToJson(node.delta!),
    if (node.metadata != null) 'metadata': _metadataToJson(node.metadata!),
  };

  Map<String, dynamic> _deltaToJson(HistoryDelta delta) => {
    'beforeElements': delta.beforeElements.map(
      (id, element) => MapEntry(id, _elementToJson(element)),
    ),
    'afterElements': delta.afterElements.map(
      (id, element) => MapEntry(id, _elementToJson(element)),
    ),
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
    final beforeElementsJson =
        (json['beforeElements'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final afterElementsJson =
        (json['afterElements'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final beforeElements = <String, ElementState>{};
    final afterElements = <String, ElementState>{};

    beforeElementsJson.forEach((key, value) {
      final elementJson = value is Map<String, dynamic>
          ? value
          : const <String, dynamic>{};
      beforeElements[key] = _elementFromJson(
        elementJson,
        elementRegistry,
        onUnknownElement: onUnknownElement,
        source: 'beforeElements',
      );
    });
    afterElementsJson.forEach((key, value) {
      final elementJson = value is Map<String, dynamic>
          ? value
          : const <String, dynamic>{};
      afterElements[key] = _elementFromJson(
        elementJson,
        elementRegistry,
        onUnknownElement: onUnknownElement,
        source: 'afterElements',
      );
    });

    final orderBefore = (json['orderBefore'] as List<dynamic>?)?.cast<String>();
    final orderAfter = (json['orderAfter'] as List<dynamic>?)?.cast<String>();

    final selectionBeforeJson =
        json['selectionBefore'] as Map<String, dynamic>?;
    final selectionAfterJson = json['selectionAfter'] as Map<String, dynamic>?;

    return HistoryDelta.fromData(
      beforeElements: beforeElements,
      afterElements: afterElements,
      orderBefore: orderBefore,
      orderAfter: orderAfter,
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
    'type': element.typeId.value,
    'data': element.data.toJson(),
  };

  ElementState _elementFromJson(
    Map<String, dynamic> json,
    ElementRegistry elementRegistry, {
    UnknownElementReporter? onUnknownElement,
    String source = 'unknown',
  }) {
    final id =
        json['id'] as String? ??
        'unknown-${DateTime.now().microsecondsSinceEpoch}';
    final type = json['type'] as String? ?? 'unknown';
    final rawData = json['data'];
    final dataJson = rawData is Map<String, dynamic>
        ? rawData
        : const <String, dynamic>{};

    final typeId = ElementTypeId<ElementData>(type);
    final definition = elementRegistry.getDefinition(typeId);

    ElementData data;

    if (definition == null) {
      _reportUnknownElement(
        onUnknownElement: onUnknownElement,
        elementType: type,
        elementId: id,
        source: '$source:definition_missing',
      );
      data = UnknownElementData(originalType: type, rawData: dataJson);
    } else {
      try {
        data = definition.fromJson(dataJson);
      } on Object catch (error, stackTrace) {
        _reportUnknownElement(
          onUnknownElement: onUnknownElement,
          elementType: type,
          elementId: id,
          source: '$source:deserialization_error',
          error: error,
          stackTrace: stackTrace,
        );
        data = UnknownElementData(originalType: type, rawData: dataJson);
      }
    }

    return ElementState(
      id: id,
      rect: _rectFromJson((json['rect'] as Map<String, dynamic>?) ?? const {}),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      zIndex: json['zIndex'] as int? ?? 0,
      data: data,
    );
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

  Map<String, dynamic> _rectToJson(DrawRect rect) => {
    'minX': rect.minX,
    'minY': rect.minY,
    'maxX': rect.maxX,
    'maxY': rect.maxY,
  };

  DrawRect _rectFromJson(Map<String, dynamic> json) => DrawRect(
    minX: (json['minX'] as num?)?.toDouble() ?? 0,
    minY: (json['minY'] as num?)?.toDouble() ?? 0,
    maxX: (json['maxX'] as num?)?.toDouble() ?? 0,
    maxY: (json['maxY'] as num?)?.toDouble() ?? 0,
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
