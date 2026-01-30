import 'package:meta/meta.dart';

import '../../../core/coordinates/element_space.dart';
import '../../../models/document_state.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import 'arrow_binding.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';
import 'arrow_layout.dart';
import 'elbow/elbow_editing.dart';

@immutable
final class ArrowBindingResolver {
  const ArrowBindingResolver._();

  static Map<String, ElementState> resolveBoundArrows({
    required Map<String, ElementState> elementsById,
    required Set<String> changedElementIds,
    DocumentState? document,
  }) {
    if (changedElementIds.isEmpty) {
      return const {};
    }

    final updates = <String, ElementState>{};
    final arrowIds = _resolveBoundArrowIds(
      changedElementIds: changedElementIds,
      elementsById: elementsById,
      document: document,
    );
    if (arrowIds.isEmpty) {
      return const {};
    }

    for (final arrowId in arrowIds) {
      final element = elementsById[arrowId];
      if (element == null) {
        continue;
      }
      final data = element.data;
      if (data is! ArrowData) {
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
        elementsById: elementsById,
        updateStart: updateStart,
        updateEnd: updateEnd,
      );
      if (updated != null) {
        updates[updated.id] = updated;
      }
    }

    return updates;
  }
}

var _cachedElementsVersion = -1;
var _cachedBindingIndex = <String, Set<String>>{};
var _cachedArrowBindings = <String, _ArrowBindingEntry>{};

Set<String> _resolveBoundArrowIds({
  required Set<String> changedElementIds,
  required Map<String, ElementState> elementsById,
  DocumentState? document,
}) {
  final bindingIndex = _resolveBindingIndex(
    changedElementIds: changedElementIds,
    elementsById: elementsById,
    document: document,
  );
  final arrowIds = <String>{};
  for (final id in changedElementIds) {
    final bound = bindingIndex[id];
    if (bound != null) {
      arrowIds.addAll(bound);
    }
  }
  return arrowIds;
}

Map<String, Set<String>> _resolveBindingIndex({
  required Set<String> changedElementIds,
  required Map<String, ElementState> elementsById,
  DocumentState? document,
}) {
  final documentVersion = document?.elementsVersion;
  if (_cachedElementsVersion == -1 ||
      (documentVersion != null && documentVersion < _cachedElementsVersion)) {
    _rebuildBindingIndex(document?.elements ?? elementsById.values);
    if (documentVersion != null) {
      _cachedElementsVersion = documentVersion;
    } else if (_cachedElementsVersion == -1) {
      _cachedElementsVersion = 0;
    }
    return _cachedBindingIndex;
  }

  if (documentVersion != null &&
      _cachedElementsVersion >= 0 &&
      documentVersion > _cachedElementsVersion + 1) {
    _rebuildBindingIndex(document?.elements ?? elementsById.values);
    _cachedElementsVersion = documentVersion;
    return _cachedBindingIndex;
  }

  final shouldUpdate =
      documentVersion == null ||
      documentVersion != _cachedElementsVersion ||
      changedElementIds.isNotEmpty;
  if (!shouldUpdate) {
    return _cachedBindingIndex;
  }

  if (changedElementIds.isEmpty) {
    _rebuildBindingIndex(document?.elements ?? elementsById.values);
  } else {
    _updateBindingIndex(
      changedElementIds: changedElementIds,
      elementsById: elementsById,
    );
  }

  if (documentVersion != null) {
    _cachedElementsVersion = documentVersion;
  } else if (_cachedElementsVersion == -1) {
    _cachedElementsVersion = 0;
  }
  return _cachedBindingIndex;
}

void _rebuildBindingIndex(Iterable<ElementState> elements) {
  _cachedBindingIndex = <String, Set<String>>{};
  _cachedArrowBindings = <String, _ArrowBindingEntry>{};

  for (final element in elements) {
    final data = element.data;
    if (data is! ArrowData) {
      continue;
    }
    final entry = _ArrowBindingEntry(
      startId: data.startBinding?.elementId,
      endId: data.endBinding?.elementId,
    );
    if (entry.isEmpty) {
      continue;
    }
    _cachedArrowBindings[element.id] = entry;
    _addBindingEntry(element.id, entry);
  }
}

void _updateBindingIndex({
  required Set<String> changedElementIds,
  required Map<String, ElementState> elementsById,
}) {
  for (final id in changedElementIds) {
    final element = elementsById[id];
    if (element == null || element.data is! ArrowData) {
      final previous = _cachedArrowBindings.remove(id);
      if (previous != null) {
        _removeBindingEntry(id, previous);
      }
      continue;
    }

    final data = element.data as ArrowData;
    final next = _ArrowBindingEntry(
      startId: data.startBinding?.elementId,
      endId: data.endBinding?.elementId,
    );
    final previous = _cachedArrowBindings[id];
    if (previous != null && previous == next) {
      continue;
    }
    if (previous != null) {
      _removeBindingEntry(id, previous);
    }
    if (next.isEmpty) {
      _cachedArrowBindings.remove(id);
      continue;
    }
    _cachedArrowBindings[id] = next;
    _addBindingEntry(id, next);
  }
}

void _addBindingEntry(String arrowId, _ArrowBindingEntry entry) {
  for (final targetId in entry.targetIds) {
    (_cachedBindingIndex[targetId] ??= <String>{}).add(arrowId);
  }
}

void _removeBindingEntry(String arrowId, _ArrowBindingEntry entry) {
  for (final targetId in entry.targetIds) {
    final arrows = _cachedBindingIndex[targetId];
    if (arrows == null) {
      continue;
    }
    arrows.remove(arrowId);
    if (arrows.isEmpty) {
      _cachedBindingIndex.remove(targetId);
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
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  required bool updateStart,
  required bool updateEnd,
}) {
  final localPoints = _resolveLocalPoints(element, data);
  if (localPoints.length < 2) {
    return null;
  }

  final rect = element.rect;
  final space = ElementSpace(rotation: element.rotation, origin: rect.center);
  final startReference = localPoints.length > 1
      ? space.toWorld(localPoints[1])
      : null;
  final endReference = localPoints.length > 1
      ? space.toWorld(localPoints[localPoints.length - 2])
      : null;

  var startUpdated = false;
  var endUpdated = false;

  if (updateStart && data.startBinding != null) {
    final target = elementsById[data.startBinding!.elementId];
    final isElbow = data.arrowType == ArrowType.elbow;
    final bound = target == null
        ? null
        : isElbow
        ? ArrowBindingUtils.resolveElbowBoundPoint(
            binding: data.startBinding!,
            target: target,
            hasArrowhead: data.startArrowhead != ArrowheadStyle.none,
          )
        : ArrowBindingUtils.resolveBoundPoint(
            binding: data.startBinding!,
            target: target,
            referencePoint: startReference,
          );
    if (bound != null) {
      localPoints[0] = space.fromWorld(bound);
      startUpdated = true;
    }
  }

  if (updateEnd && data.endBinding != null) {
    final target = elementsById[data.endBinding!.elementId];
    final isElbow = data.arrowType == ArrowType.elbow;
    final bound = target == null
        ? null
        : isElbow
        ? ArrowBindingUtils.resolveElbowBoundPoint(
            binding: data.endBinding!,
            target: target,
            hasArrowhead: data.endArrowhead != ArrowheadStyle.none,
          )
        : ArrowBindingUtils.resolveBoundPoint(
            binding: data.endBinding!,
            target: target,
            referencePoint: endReference,
          );
    if (bound != null) {
      localPoints[localPoints.length - 1] = space.fromWorld(bound);
      endUpdated = true;
    }
  }

  if (!startUpdated && !endUpdated) {
    return null;
  }

  if (data.arrowType == ArrowType.elbow) {
    final updated = computeElbowEdit(
      element: element,
      data: data,
      elementsById: elementsById,
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

List<DrawPoint> _resolveLocalPoints(ElementState element, ArrowData data) {
  final resolved = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );
  return resolved
      .map((point) => DrawPoint(x: point.dx, y: point.dy))
      .toList(growable: false);
}
