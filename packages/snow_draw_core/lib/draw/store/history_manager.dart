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
    HistoryCoalescing? coalescing,
    DrawState? currentState,
    DrawState? nextState,
    DateTime? recordedAt,
  }) {
    final now = recordedAt ?? DateTime.now();
    if (coalescing != null && currentState != null) {
      final coalesced = _tryCoalesceCurrentRecord(
        after: after,
        metadata: metadata,
        changes: changes,
        coalescing: coalescing,
        currentState: currentState,
        nextState: nextState,
        includeSelection: before.includeSelection,
        recordedAt: now,
      );
      if (coalesced != null) {
        return coalesced;
      }
    }

    final delta = HistoryDelta.fromSnapshots(before, after, changes: changes);
    if (!delta.hasChanges) {
      _log?.trace('History record skipped (no changes)', {
        'description': metadata?.description,
      });
      return false;
    }

    final node = _HistoryNode(
      id: _nextNodeId++,
      parent: _current,
      delta: delta,
      metadata: metadata,
      coalescing: coalescing,
      recordedAt: now,
    );
    _current.children.add(node);
    _current = node;
    _log?.trace('History record', {
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

  bool? _tryCoalesceCurrentRecord({
    required HistorySnapshot after,
    required HistoryMetadata? metadata,
    required HistoryChangeSet? changes,
    required HistoryCoalescing coalescing,
    required DrawState currentState,
    required DrawState? nextState,
    required bool includeSelection,
    required DateTime recordedAt,
  }) {
    if (!_canCoalesceCurrent(coalescing: coalescing, recordedAt: recordedAt)) {
      return null;
    }

    final currentNode = _current;
    final parent = currentNode.parent!;
    final currentDelta = currentNode.delta!;
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
      currentDelta: currentDelta,
      nextState: nextState,
      changes: changes,
      includeSelection: includeSelection,
    );
    if (!mergedDelta.hasChanges) {
      parent.children.remove(currentNode);
      _current = parent;
      _log?.trace('History coalesced and removed empty node', {
        'parentId': parent.id,
        'coalescingKey': coalescing.key,
      });
      return false;
    }

    currentNode
      ..delta = mergedDelta
      ..metadata = metadata
      ..coalescing = coalescing
      ..recordedAt = recordedAt;

    _log?.trace('History coalesced into current node', {
      'nodeId': currentNode.id,
      'parentId': parent.id,
      'coalescingKey': coalescing.key,
      'description': metadata?.description,
    });
    return true;
  }

  HistoryDelta _buildCoalescedDelta({
    required DrawState parentState,
    required HistorySnapshot afterSnapshot,
    required HistoryDelta currentDelta,
    required DrawState? nextState,
    required HistoryChangeSet? changes,
    required bool includeSelection,
  }) {
    if (nextState == null || changes == null) {
      final mergedBefore = PersistentSnapshot.fromState(
        parentState,
        includeSelection: includeSelection,
      );
      return HistoryDelta.fromSnapshots(mergedBefore, afterSnapshot);
    }

    final mergedChanges = _composeCoalescedChangeSet(
      currentDelta: currentDelta,
      incomingChanges: changes,
    );
    final mergedBefore = _snapshotForCoalescedState(
      state: parentState,
      changes: mergedChanges,
      includeSelection: includeSelection,
    );
    final mergedAfter = _snapshotForCoalescedState(
      state: nextState,
      changes: mergedChanges,
      includeSelection: includeSelection,
    );
    return HistoryDelta.fromSnapshots(
      mergedBefore,
      mergedAfter,
      changes: mergedChanges,
    );
  }

  HistoryChangeSet _composeCoalescedChangeSet({
    required HistoryDelta currentDelta,
    required HistoryChangeSet incomingChanges,
  }) {
    final currentElementIds = <String>{
      ...currentDelta.beforeElements.keys,
      ...currentDelta.afterElements.keys,
    };

    return HistoryChangeSet(
      modifiedIds: <String>{
        ...incomingChanges.allElementIds,
        ...currentElementIds,
      },
      orderChanged:
          incomingChanges.orderChanged || currentDelta.orderBefore != null,
      globalElementsChanged:
          incomingChanges.globalElementsChanged ||
          currentDelta.globalElementsBefore != null,
      selectionChanged:
          incomingChanges.selectionChanged || currentDelta.selectionChanged,
      reindexZIndices:
          incomingChanges.reindexZIndices || currentDelta.reindexZIndices,
    );
  }

  HistorySnapshot _snapshotForCoalescedState({
    required DrawState state,
    required HistoryChangeSet changes,
    required bool includeSelection,
  }) {
    if (!_canUseIncrementalCoalescingSnapshot(changes)) {
      return PersistentSnapshot.fromState(
        state,
        includeSelection: includeSelection,
      );
    }

    final elementsById = <String, ElementState>{};
    if (changes.hasElementChanges) {
      final elementMap = state.domain.document.elementMap;
      for (final id in changes.allElementIds) {
        final element = elementMap[id];
        if (element != null) {
          elementsById[id] = element;
        }
      }
    }

    return IncrementalSnapshot(
      elementsById: elementsById,
      globalElements: state.domain.document.globalElements,
      selection: includeSelection
          ? state.domain.selection
          : const SelectionState(),
      includeSelection: includeSelection,
      order: changes.orderChanged
          ? state.domain.document.elements.map((element) => element.id).toList()
          : null,
    );
  }

  bool _canUseIncrementalCoalescingSnapshot(HistoryChangeSet changes) =>
      !changes.orderChanged || changes.reindexZIndices;

  bool _canCoalesceCurrent({
    required HistoryCoalescing coalescing,
    required DateTime recordedAt,
  }) {
    if (_current.parent == null ||
        _current.delta == null ||
        _current.children.isNotEmpty) {
      return false;
    }
    final active = _current.coalescing;
    if (active == null || active.key != coalescing.key) {
      return false;
    }
    final expiresAt = _current.recordedAt.add(coalescing.window);
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
        'nodeId': _current.id,
        'error': error.toString(),
      });
      return null;
    }
  }

  DrawState? undo(DrawState currentState) {
    final node = _current;
    final parent = node.parent;
    if (parent == null) {
      _log?.trace('History undo skipped', {'reason': 'no_parent'});
      return null;
    }

    final restoredState = node.delta!.applyBackward(currentState);
    _log?.trace('History undo', {'nodeId': node.id, 'parentId': parent.id});
    _current = parent;
    return restoredState;
  }

  DrawState? redo(DrawState currentState, {int? branchIndex}) {
    final target = _resolveRedoTarget(branchIndex);
    if (target == null) {
      return null;
    }

    final restoredState = target.node.delta!.applyForward(currentState);
    _log?.trace('History redo', {
      'nodeId': target.node.id,
      'branchIndex': target.index,
    });
    _current = target.node;
    return restoredState;
  }

  void clear() {
    _log?.trace('History cleared', {
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
    _nextNodeId = _resolveNextNodeId(
      requestedNextNodeId: snapshot._nextNodeId,
      minNextNodeId: _maxNodeId(_root) + 1,
    );
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
    final resolvedIndex = _resolvePruneRootIndex(path, candidateIndex);

    final newRoot = path[resolvedIndex];
    final oldParent = newRoot.parent;
    if (oldParent == null) {
      return;
    }

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

  void _normalizeRootPayload() {
    _normalizeRootNode(_root);
  }

  ({int index, _HistoryNode node})? _resolveRedoTarget(int? branchIndex) {
    if (_current.children.isEmpty) {
      _log?.trace('History redo skipped', {'reason': 'no_children'});
      return null;
    }

    final resolvedIndex = branchIndex ?? _current.children.length - 1;
    if (!_isValidRedoBranchIndex(resolvedIndex)) {
      _log?.trace('History redo skipped', {
        'reason': 'invalid_branch',
        'branchIndex': branchIndex,
      });
      return null;
    }
    return (index: resolvedIndex, node: _current.children[resolvedIndex]);
  }

  bool _isValidRedoBranchIndex(int index) =>
      index >= 0 && index < _current.children.length;

  int _resolvePruneRootIndex(List<_HistoryNode> path, int candidateIndex) {
    if (maxBranchPoints <= 0) {
      return candidateIndex;
    }

    var resolvedIndex = candidateIndex;
    final earliestAllowedIndex = candidateIndex - maxBranchPoints;
    for (
      var index = candidateIndex - 1;
      index >= 0 && index >= earliestAllowedIndex;
      index--
    ) {
      if (_isBranchPoint(path[index])) {
        resolvedIndex = index;
      }
    }
    return resolvedIndex;
  }

  bool _isBranchPoint(_HistoryNode node) => node.children.length > 1;
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
    required this.recordedAt,
    this.coalescing,
    List<_HistoryNode>? children,
  }) : children = children ?? [];

  _HistoryNode.root(this.id)
    : parent = null,
      delta = null,
      metadata = null,
      coalescing = null,
      recordedAt = DateTime.fromMillisecondsSinceEpoch(0),
      children = [];
  final int id;
  _HistoryNode? parent;
  final List<_HistoryNode> children;
  HistoryDelta? delta;
  HistoryMetadata? metadata;
  HistoryCoalescing? coalescing;
  DateTime recordedAt;

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
      coalescing: node.coalescing,
      recordedAt: node.recordedAt,
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

    final nodesData = (json['nodes'] as List<dynamic>?) ?? const [];
    final byId = <int, _HistoryNode>{};
    final nodeDataById = <int, Map<String, dynamic>>{};

    for (final entry in nodesData) {
      final decodedData = _asJsonMap(entry);
      if (decodedData == null) {
        continue;
      }
      final id = decodedData['id'] as int?;
      if (id == null) {
        continue;
      }
      nodeDataById[id] = decodedData;
      final deltaJson = _asJsonMap(decodedData['delta']);
      final metadataJson = _asJsonMap(decodedData['metadata']);
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
        recordedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }

    _linkDecodedNodes(byId: byId, nodeDataById: nodeDataById);

    final rootId = json['rootId'] as int? ?? 0;
    final currentId = json['currentId'] as int? ?? rootId;
    final maxNodeId = byId.isEmpty
        ? rootId
        : byId.keys.reduce((a, b) => a > b ? a : b);
    final nextNodeId = _resolveNextNodeId(
      requestedNextNodeId: json['nextNodeId'] as int?,
      minNextNodeId: maxNodeId + 1,
    );

    final root = byId[rootId] ?? _HistoryNode.root(rootId);
    _normalizeRootNode(root);
    return HistoryManagerSnapshot._(root, currentId, nextNodeId);
  }

  void _linkDecodedNodes({
    required Map<int, _HistoryNode> byId,
    required Map<int, Map<String, dynamic>> nodeDataById,
  }) {
    final parentAssignments = _resolveDecodedParentAssignments(
      byId: byId,
      nodeDataById: nodeDataById,
    );
    for (final entry in parentAssignments.entries) {
      final child = byId[entry.key];
      final parent = byId[entry.value];
      if (parent == null || child == null) {
        continue;
      }
      _linkNodes(parent: parent, child: child);
    }
  }

  Map<int, int> _resolveDecodedParentAssignments({
    required Map<int, _HistoryNode> byId,
    required Map<int, Map<String, dynamic>> nodeDataById,
  }) {
    final assignments = <int, int>{};

    for (final entry in nodeDataById.entries) {
      final childId = entry.key;
      final parentId = entry.value['parentId'] as int?;
      if (_isValidParentAssignment(
        byId: byId,
        parentId: parentId,
        childId: childId,
      )) {
        assignments[childId] = parentId!;
      }
    }

    for (final entry in nodeDataById.entries) {
      final parentId = entry.key;
      for (final childId in _asIntList(entry.value['children'])) {
        if (assignments.containsKey(childId)) {
          continue;
        }
        if (_isValidParentAssignment(
          byId: byId,
          parentId: parentId,
          childId: childId,
        )) {
          assignments[childId] = parentId;
        }
      }
    }

    return assignments;
  }

  bool _isValidParentAssignment({
    required Map<int, _HistoryNode> byId,
    required int? parentId,
    required int childId,
  }) {
    if (parentId == null || parentId == childId) {
      return false;
    }
    return byId.containsKey(parentId) && byId.containsKey(childId);
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
    final dataJson = _asJsonMap(json['data']) ?? const <String, dynamic>{};
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
      rect: _rectFromJson(_asJsonMap(json['rect']) ?? const {}),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      zIndex: json['zIndex'] as int? ?? 0,
      data: data,
    );
  }

  Map<String, ElementState> _decodeElementMap(
    Object? rawElementsJson,
    ElementRegistry elementRegistry, {
    required String source,
    UnknownElementReporter? onUnknownElement,
  }) {
    final decoded = <String, ElementState>{};
    final elementsJson = _asJsonMap(rawElementsJson);
    if (elementsJson == null) {
      return decoded;
    }
    for (final entry in elementsJson.entries) {
      final elementJson = _asJsonMap(entry.value) ?? const <String, dynamic>{};
      decoded[entry.key] = _elementFromJson(
        elementJson,
        elementRegistry,
        onUnknownElement: onUnknownElement,
        source: source,
      );
    }
    return decoded;
  }

  void _linkNodes({required _HistoryNode parent, required _HistoryNode child}) {
    if (identical(parent, child)) {
      return;
    }
    final currentParent = child.parent;
    if (currentParent != null && !identical(currentParent, parent)) {
      return;
    }
    if (_createsParentCycle(parent: parent, child: child)) {
      return;
    }
    child.parent = parent;
    if (!parent.children.contains(child)) {
      parent.children.add(child);
    }
  }

  bool _createsParentCycle({
    required _HistoryNode parent,
    required _HistoryNode child,
  }) {
    _HistoryNode? current = parent;
    final visited = <_HistoryNode>{};
    while (current != null && visited.add(current)) {
      if (identical(current, child)) {
        return true;
      }
      current = current.parent;
    }
    return false;
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

  List<int> _asIntList(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return <int>[
      for (final value in raw)
        if (value is int) value,
    ];
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

void _normalizeRootNode(_HistoryNode root) {
  final parent = root.parent;
  if (parent != null) {
    parent.children.remove(root);
  }
  root
    ..parent = null
    ..delta = null
    ..metadata = null
    ..coalescing = null;
}

int _resolveNextNodeId({
  required int? requestedNextNodeId,
  required int minNextNodeId,
}) {
  final resolved = requestedNextNodeId ?? minNextNodeId;
  return resolved < minNextNodeId ? minNextNodeId : resolved;
}

int _maxNodeId(_HistoryNode root) {
  var maxId = root.id;
  final stack = <_HistoryNode>[root];
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (node.id > maxId) {
      maxId = node.id;
    }
    stack.addAll(node.children);
  }
  return maxId;
}
