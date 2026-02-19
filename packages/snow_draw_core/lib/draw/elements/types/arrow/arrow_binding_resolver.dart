import 'package:meta/meta.dart';

import '../../../core/coordinates/element_space.dart';
import '../../../models/document_state.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import '../../../utils/combined_element_lookup.dart';
import 'arrow_binding.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';
import 'arrow_layout.dart';
import 'arrow_like_data.dart';
import 'elbow/elbow_editing.dart';

/// Resolves arrow bindings when bound elements change position.
///
/// Maintains a cached index of arrow bindings for efficient lookup.
/// Uses version-based invalidation to minimize rebuilds.
class ArrowBindingResolver {
  ArrowBindingResolver._();

  /// Global instance for shared caching across the application.
  static final instance = ArrowBindingResolver._();

  var _cachedElementsVersion = -1;
  Map<String, Set<String>> _bindingIndex = {};
  Map<String, _ArrowBindingEntry> _arrowBindings = {};

  /// Resolves bound arrows when elements change.
  ///
  /// This is the primary entry point. Uses [CombinedElementLookup] to avoid
  /// map allocation when combining document elements with updates.
  ///
  /// Parameters:
  /// - [baseElements]: The document's element map
  /// - [updatedElements]: Elements that have been modified (overlay)
  /// - [changedElementIds]: IDs of elements that changed
  /// - [document]: Optional document for version-based cache invalidation
  ///
  /// Returns a map of arrow IDs to their updated states.
  Map<String, ElementState> resolve({
    required Map<String, ElementState> baseElements,
    required Map<String, ElementState> updatedElements,
    required Set<String> changedElementIds,
    DocumentState? document,
  }) {
    if (changedElementIds.isEmpty) {
      return const {};
    }

    final lookup = CombinedElementLookup(
      base: baseElements,
      overlay: updatedElements,
    );

    final arrowIds = _resolveBoundArrowIds(
      changedElementIds: changedElementIds,
      lookup: lookup,
      document: document,
    );
    if (arrowIds.isEmpty) {
      return const {};
    }

    final updates = <String, ElementState>{};
    for (final arrowId in arrowIds) {
      final element = lookup[arrowId];
      if (element == null) {
        continue;
      }
      final data = element.data;
      if (data is! ArrowLikeData) {
        continue;
      }
      final startBinding = data.startBinding;
      final endBinding = data.endBinding;
      if (startBinding == null && endBinding == null) {
        continue;
      }

      final updateStart =
          startBinding != null &&
          changedElementIds.contains(startBinding.elementId);
      final updateEnd =
          endBinding != null &&
          changedElementIds.contains(endBinding.elementId);
      if (!updateStart && !updateEnd) {
        continue;
      }

      final updated = _applyBindings(
        element: element,
        data: data,
        lookup: lookup,
        updateStart: updateStart,
        updateEnd: updateEnd,
      );
      if (updated != null) {
        updates[updated.id] = updated;
      }
    }

    return updates;
  }

  /// Invalidates the cache, forcing a full rebuild on next resolve.
  void invalidate() {
    _cachedElementsVersion = -1;
    _bindingIndex = {};
    _arrowBindings = {};
  }

  Set<String> _resolveBoundArrowIds({
    required Set<String> changedElementIds,
    required CombinedElementLookup lookup,
    DocumentState? document,
  }) {
    _updateBindingIndexIfNeeded(
      changedElementIds: changedElementIds,
      lookup: lookup,
      document: document,
    );

    final arrowIds = <String>{};
    for (final id in changedElementIds) {
      final bound = _bindingIndex[id];
      if (bound != null) {
        arrowIds.addAll(bound);
      }
    }
    return arrowIds;
  }

  void _updateBindingIndexIfNeeded({
    required Set<String> changedElementIds,
    required CombinedElementLookup lookup,
    DocumentState? document,
  }) {
    final documentVersion = document?.elementsVersion;
    final shouldRebuild =
        _cachedElementsVersion == -1 ||
        (documentVersion != null &&
            (documentVersion < _cachedElementsVersion ||
                documentVersion > _cachedElementsVersion + 1));

    if (shouldRebuild) {
      _rebuildBindingIndex(document?.elements ?? lookup.values);
    } else {
      _incrementalUpdateBindingIndex(
        changedElementIds: changedElementIds,
        lookup: lookup,
      );
    }
    if (documentVersion != null) {
      _cachedElementsVersion = documentVersion;
    } else if (_cachedElementsVersion == -1) {
      _cachedElementsVersion = 0;
    }
  }

  void _rebuildBindingIndex(Iterable<ElementState> elements) {
    _bindingIndex = <String, Set<String>>{};
    _arrowBindings = <String, _ArrowBindingEntry>{};

    for (final element in elements) {
      final data = element.data;
      if (data is! ArrowLikeData) {
        continue;
      }
      final entry = _ArrowBindingEntry(
        startId: data.startBinding?.elementId,
        endId: data.endBinding?.elementId,
      );
      if (entry.isEmpty) {
        continue;
      }
      _arrowBindings[element.id] = entry;
      _addBindingEntry(element.id, entry);
    }
  }

  void _incrementalUpdateBindingIndex({
    required Set<String> changedElementIds,
    required CombinedElementLookup lookup,
  }) {
    for (final id in changedElementIds) {
      final element = lookup[id];
      if (element == null || element.data is! ArrowLikeData) {
        _removeArrowBinding(id);
        continue;
      }

      final data = element.data as ArrowLikeData;
      final next = _ArrowBindingEntry(
        startId: data.startBinding?.elementId,
        endId: data.endBinding?.elementId,
      );
      final previous = _arrowBindings[id];
      if (previous == next) {
        continue;
      }
      if (next.isEmpty) {
        _removeArrowBinding(id);
        continue;
      }
      if (previous != null) {
        _removeBindingEntry(id, previous);
      }
      _arrowBindings[id] = next;
      _addBindingEntry(id, next);
    }
  }

  void _removeArrowBinding(String arrowId) {
    final previous = _arrowBindings.remove(arrowId);
    if (previous != null) {
      _removeBindingEntry(arrowId, previous);
    }
  }

  void _addBindingEntry(String arrowId, _ArrowBindingEntry entry) {
    for (final targetId in entry.targetIds) {
      (_bindingIndex[targetId] ??= <String>{}).add(arrowId);
    }
  }

  void _removeBindingEntry(String arrowId, _ArrowBindingEntry entry) {
    for (final targetId in entry.targetIds) {
      final arrows = _bindingIndex[targetId];
      if (arrows == null) {
        continue;
      }
      arrows.remove(arrowId);
      if (arrows.isEmpty) {
        _bindingIndex.remove(targetId);
      }
    }
  }
}

@immutable
class _ArrowBindingEntry {
  const _ArrowBindingEntry({this.startId, this.endId});

  final String? startId;
  final String? endId;

  bool get isEmpty => startId == null && endId == null;

  Iterable<String> get targetIds sync* {
    if (startId != null) {
      yield startId!;
    }
    if (endId != null && endId != startId) {
      yield endId!;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ArrowBindingEntry &&
          other.startId == startId &&
          other.endId == endId;

  @override
  int get hashCode => Object.hash(startId, endId);
}

ElementState? _applyBindings({
  required ElementState element,
  required ArrowLikeData data,
  required CombinedElementLookup lookup,
  required bool updateStart,
  required bool updateEnd,
}) {
  assert(updateStart || updateEnd, 'At least one endpoint must be updated.');

  final localPoints = _resolveLocalPoints(element, data);
  if (localPoints.length < 2) {
    return null;
  }

  final syncBothEnds =
      (updateStart || updateEnd) &&
      data.startBinding != null &&
      data.endBinding != null;
  final shouldUpdateStart = updateStart || syncBothEnds;
  final shouldUpdateEnd = updateEnd || syncBothEnds;

  final rect = element.rect;
  final space = ElementSpace(rotation: element.rotation, origin: rect.center);
  final isElbow = data.arrowType == ArrowType.elbow;
  final maxIterations =
      shouldUpdateStart && shouldUpdateEnd && localPoints.length == 2 ? 4 : 2;

  var startUpdated = false;
  var endUpdated = false;

  for (var i = 0; i < maxIterations; i++) {
    var changed = false;
    final startReference = space.toWorld(localPoints[1]);
    final endReference = space.toWorld(localPoints[localPoints.length - 2]);

    final startBinding = data.startBinding;
    if (shouldUpdateStart && startBinding != null) {
      final nextLocal = _resolveBoundLocalPoint(
        binding: startBinding,
        lookup: lookup,
        space: space,
        isElbow: isElbow,
        hasArrowhead: data.startArrowhead != ArrowheadStyle.none,
        referencePoint: startReference,
      );
      if (nextLocal != null) {
        if (nextLocal != localPoints[0]) {
          localPoints[0] = nextLocal;
          changed = true;
        }
        startUpdated = true;
      }
    }

    final endBinding = data.endBinding;
    if (shouldUpdateEnd && endBinding != null) {
      final endIndex = localPoints.length - 1;
      final nextLocal = _resolveBoundLocalPoint(
        binding: endBinding,
        lookup: lookup,
        space: space,
        isElbow: isElbow,
        hasArrowhead: data.endArrowhead != ArrowheadStyle.none,
        referencePoint: endReference,
      );
      if (nextLocal != null) {
        if (nextLocal != localPoints[endIndex]) {
          localPoints[endIndex] = nextLocal;
          changed = true;
        }
        endUpdated = true;
      }
    }

    if (!changed) {
      break;
    }
  }

  if (!startUpdated && !endUpdated) {
    return null;
  }

  if (data.arrowType == ArrowType.elbow && data is ArrowData) {
    final updated = computeElbowEdit(
      element: element,
      data: data,
      lookup: lookup,
      localPointsOverride: localPoints,
      fixedSegmentsOverride: data.fixedSegments,
      startBindingOverride: data.startBinding,
      endBindingOverride: data.endBinding,
    );
    final result = computeArrowRectAndPoints(
      localPoints: updated.localPoints,
      oldRect: rect,
      rotation: element.rotation,
      arrowType: data.arrowType,
      strokeWidth: data.strokeWidth,
    );
    final transformedFixedSegments = transformFixedSegments(
      segments: updated.fixedSegments,
      oldRect: rect,
      newRect: result.rect,
      rotation: element.rotation,
    );
    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: result.localPoints,
      rect: result.rect,
    );
    final updatedData = data.copyWith(
      points: normalized,
      fixedSegments: transformedFixedSegments,
      startIsSpecial: updated.startIsSpecial,
      endIsSpecial: updated.endIsSpecial,
    );
    if (updatedData == data && result.rect == rect) {
      return null;
    }
    return element.copyWith(rect: result.rect, data: updatedData);
  }

  final result = computeArrowRectAndPoints(
    localPoints: localPoints,
    oldRect: rect,
    rotation: element.rotation,
    arrowType: data.arrowType,
    strokeWidth: data.strokeWidth,
  );

  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: result.localPoints,
    rect: result.rect,
  );

  final updatedData = data.copyWith(points: normalized);
  if (updatedData == data && result.rect == rect) {
    return null;
  }

  return element.copyWith(rect: result.rect, data: updatedData);
}

DrawPoint? _resolveBoundLocalPoint({
  required ArrowBinding binding,
  required CombinedElementLookup lookup,
  required ElementSpace space,
  required bool isElbow,
  required bool hasArrowhead,
  DrawPoint? referencePoint,
}) {
  final target = lookup[binding.elementId];
  if (target == null) {
    return null;
  }

  final boundPoint = isElbow
      ? ArrowBindingUtils.resolveElbowBoundPoint(
          binding: binding,
          target: target,
          hasArrowhead: hasArrowhead,
        )
      : ArrowBindingUtils.resolveBoundPoint(
          binding: binding,
          target: target,
          referencePoint: referencePoint,
        );
  if (boundPoint == null) {
    return null;
  }

  return space.fromWorld(boundPoint);
}

List<DrawPoint> _resolveLocalPoints(ElementState element, ArrowLikeData data) {
  final resolved = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );
  return resolved
      .map((point) => DrawPoint(x: point.dx, y: point.dy))
      .toList(growable: false);
}
