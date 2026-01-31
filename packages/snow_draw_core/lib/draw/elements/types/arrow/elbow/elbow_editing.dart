import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../../core/coordinates/element_space.dart';
import '../../../../models/element_state.dart';
import '../../../../types/draw_point.dart';
import '../../../../types/draw_rect.dart';
import '../../../../types/element_style.dart';
import '../../../../utils/selection_calculator.dart';
import '../arrow_binding.dart';
import '../arrow_data.dart';
import '../arrow_geometry.dart';
import 'elbow_geometry.dart';
import 'elbow_fixed_segment.dart';
import 'elbow_router.dart';

const double _dedupThreshold = 1;
const double _directionFixPadding = 12;

/// Output of elbow edit computation (local points + fixed segment updates).
@immutable
final class ElbowEditResult {
  const ElbowEditResult({
    required this.localPoints,
    required this.fixedSegments,
    required this.startIsSpecial,
    required this.endIsSpecial,
  });

  final List<DrawPoint> localPoints;
  final List<ElbowFixedSegment>? fixedSegments;
  final bool? startIsSpecial;
  final bool? endIsSpecial;
}

@immutable
final class _FixedSegmentPathResult {
  const _FixedSegmentPathResult({
    required this.points,
    required this.fixedSegments,
  });

  final List<DrawPoint> points;
  final List<ElbowFixedSegment> fixedSegments;
}

@immutable
final class _PerpendicularAdjustment {
  const _PerpendicularAdjustment({
    required this.points,
    required this.moved,
    required this.inserted,
  });

  final List<DrawPoint> points;
  final bool moved;
  final bool inserted;
}

ElbowEditResult computeElbowEdit({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  List<DrawPoint>? localPointsOverride,
  List<ElbowFixedSegment>? fixedSegmentsOverride,
  ArrowBinding? startBindingOverride,
  ArrowBinding? endBindingOverride,
}) {
  // Step 1: resolve the base local points from the element and incoming edits.
  final basePoints = _resolveLocalPoints(element, data);
  final incomingPoints = localPointsOverride ?? basePoints;
  if (incomingPoints.length < 2) {
    return ElbowEditResult(
      localPoints: incomingPoints,
      fixedSegments: null,
      startIsSpecial: data.startIsSpecial,
      endIsSpecial: data.endIsSpecial,
    );
  }

  // Step 2: sanitize fixed segments and resolve binding overrides.
  final previousFixedSegments = _sanitizeFixedSegments(
    data.fixedSegments,
    basePoints.length,
  );
  final fixedSegments = _sanitizeFixedSegments(
    fixedSegmentsOverride ?? data.fixedSegments,
    incomingPoints.length,
  );
  final startBinding = startBindingOverride ?? data.startBinding;
  final endBinding = endBindingOverride ?? data.endBinding;

  // Step 3: no fixed segments means a fresh route is required.
  if (fixedSegments.isEmpty) {
    final routed = routeElbowArrowForElement(
      element: element,
      data: data.copyWith(startBinding: startBinding, endBinding: endBinding),
      elementsById: elementsById,
      startOverride: incomingPoints.first,
      endOverride: incomingPoints.last,
    );
    return ElbowEditResult(
      localPoints: routed.localPoints,
      fixedSegments: null,
      startIsSpecial: data.startIsSpecial,
      endIsSpecial: data.endIsSpecial,
    );
  }

  final pointsChanged = !_pointsEqual(basePoints, incomingPoints);
  final fixedSegmentsChanged =
      !_fixedSegmentsEqual(previousFixedSegments, fixedSegments);
  final releaseRequested =
      fixedSegmentsOverride != null &&
      fixedSegments.length < previousFixedSegments.length;

  // Step 4: fixed segment release (e.g. user unpins a segment).
  if (releaseRequested) {
    final updated = _handleFixedSegmentRelease(
      element: element,
      data: data,
      elementsById: elementsById,
      currentPoints: incomingPoints,
      previousFixed: previousFixedSegments,
      remainingFixed: fixedSegments,
      startBinding: startBinding,
      endBinding: endBinding,
    );
    final enforcedPoints =
        _applyFixedSegmentsToPoints(updated.points, updated.fixedSegments);
    final pinned = _collectPinnedPoints(
      points: enforcedPoints,
      fixedSegments: updated.fixedSegments,
    );
    final simplified = _simplifyPath(enforcedPoints, pinned: pinned);
    final reindexed = _reindexFixedSegments(simplified, updated.fixedSegments);
    final resultSegments = reindexed.isEmpty
        ? null
        : List<ElbowFixedSegment>.unmodifiable(reindexed);
    return ElbowEditResult(
      localPoints: simplified,
      fixedSegments: resultSegments,
      startIsSpecial: data.startIsSpecial,
      endIsSpecial: data.endIsSpecial,
    );
  }

  // Step 5: endpoint drag while fixed segments stay pinned.
  if (pointsChanged && !fixedSegmentsChanged) {
    final updated = _applyEndpointDragWithFixedSegments(
      element: element,
      elementsById: elementsById,
      basePoints: basePoints,
      incomingPoints: incomingPoints,
      fixedSegments: fixedSegments,
      startBinding: startBinding,
      endBinding: endBinding,
      startArrowhead: data.startArrowhead,
      endArrowhead: data.endArrowhead,
    );
    final resultSegments = updated.fixedSegments.isEmpty
        ? null
        : List<ElbowFixedSegment>.unmodifiable(updated.fixedSegments);
    return ElbowEditResult(
      localPoints: List<DrawPoint>.unmodifiable(updated.points),
      fixedSegments: resultSegments,
      startIsSpecial: data.startIsSpecial,
      endIsSpecial: data.endIsSpecial,
    );
  }

  // Step 6: apply fixed segments to updated points if needed.
  var workingPoints = incomingPoints;
  if (!pointsChanged && fixedSegmentsChanged) {
    workingPoints = _applyFixedSegmentsToPoints(basePoints, fixedSegments);
  }
  workingPoints = _applyFixedSegmentsToPoints(workingPoints, fixedSegments);

  // Step 7: simplify and reindex segments to keep the path stable.
  final pinned = _collectPinnedPoints(
    points: workingPoints,
    fixedSegments: fixedSegments,
  );
  final simplified = _simplifyPath(workingPoints, pinned: pinned);
  final reindexed = _reindexFixedSegments(simplified, fixedSegments);
  final resultSegments = reindexed.isEmpty
      ? null
      : List<ElbowFixedSegment>.unmodifiable(reindexed);

  return ElbowEditResult(
    localPoints: simplified,
    fixedSegments: resultSegments,
    startIsSpecial: data.startIsSpecial,
    endIsSpecial: data.endIsSpecial,
  );
}

/// Transforms fixed segments when the owning element is resized/rotated.
List<ElbowFixedSegment>? transformFixedSegments({
  required List<ElbowFixedSegment>? segments,
  required DrawRect oldRect,
  required DrawRect newRect,
  required double rotation,
}) {
  if (segments == null || segments.isEmpty) {
    return null;
  }
  final oldSpace = ElementSpace(rotation: rotation, origin: oldRect.center);
  final newSpace = ElementSpace(rotation: rotation, origin: newRect.center);
  final transformed = segments
      .map((segment) {
        final worldStart = oldSpace.toWorld(segment.start);
        final worldEnd = oldSpace.toWorld(segment.end);
        return segment.copyWith(
          start: newSpace.fromWorld(worldStart),
          end: newSpace.fromWorld(worldEnd),
        );
      })
      .toList(growable: false);
  return List<ElbowFixedSegment>.unmodifiable(transformed);
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

List<ElbowFixedSegment> _sanitizeFixedSegments(
  List<ElbowFixedSegment>? segments,
  int pointCount,
) {
  if (segments == null || segments.isEmpty || pointCount < 2) {
    return const [];
  }
  final maxIndex = pointCount - 1;
  final result = <ElbowFixedSegment>[];
  for (final segment in segments) {
    if (segment.index <= 1 || segment.index >= maxIndex) {
      continue;
    }
    if (segment.index < 1 || segment.index >= pointCount) {
      continue;
    }
    final dx = (segment.start.x - segment.end.x).abs();
    final dy = (segment.start.y - segment.end.y).abs();
    if (dx > _dedupThreshold && dy > _dedupThreshold) {
      continue;
    }
    final length = _manhattanDistance(segment.start, segment.end);
    if (length <= _dedupThreshold) {
      continue;
    }
    if (result.any((entry) => entry.index == segment.index)) {
      continue;
    }
    result.add(segment);
  }
  result.sort((a, b) => a.index.compareTo(b.index));
  return result;
}

List<DrawPoint> _routeLocalPath({
  required ElementState element,
  required Map<String, ElementState> elementsById,
  required DrawPoint startLocal,
  required DrawPoint endLocal,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
}) {
  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  final worldStart = space.toWorld(startLocal);
  final worldEnd = space.toWorld(endLocal);
  final routed = routeElbowArrow(
    start: worldStart,
    end: worldEnd,
    startBinding: startBinding,
    endBinding: endBinding,
    elementsById: elementsById,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );
  return routed.points.map(space.fromWorld).toList(growable: false);
}

List<DrawPoint> _simplifyPath(
  List<DrawPoint> points, {
  Set<DrawPoint> pinned = const <DrawPoint>{},
}) {
  if (points.length < 3) {
    return points;
  }

  final withoutCollinear = <DrawPoint>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final point = points[i];
    if (pinned.contains(point)) {
      withoutCollinear.add(point);
      continue;
    }
    final prev = withoutCollinear.last;
    final next = points[i + 1];
    final isHorizontalPrev = _isHorizontal(prev, point);
    final isHorizontalNext = _isHorizontal(point, next);
    if (isHorizontalPrev == isHorizontalNext) {
      continue;
    }
    withoutCollinear.add(point);
  }
  withoutCollinear.add(points.last);

  final cleaned = <DrawPoint>[withoutCollinear.first];
  for (var i = 1; i < withoutCollinear.length; i++) {
    final point = withoutCollinear[i];
    if (point == cleaned.last) {
      continue;
    }
    final length = _manhattanDistance(cleaned.last, point);
    if (length <= _dedupThreshold && !pinned.contains(point)) {
      continue;
    }
    cleaned.add(point);
  }

  return List<DrawPoint>.unmodifiable(cleaned);
}

List<ElbowFixedSegment> _reindexFixedSegments(
  List<DrawPoint> points,
  List<ElbowFixedSegment> fixedSegments,
) {
  if (fixedSegments.isEmpty || points.length < 2) {
    return const [];
  }
  final maxIndex = points.length - 1;
  final result = <ElbowFixedSegment>[];
  for (final segment in fixedSegments) {
    final index = _findSegmentIndex(points, segment);
    if (index == null || index <= 1 || index >= maxIndex) {
      continue;
    }
    final start = points[index - 1];
    final end = points[index];
    final length = _manhattanDistance(start, end);
    if (length <= _dedupThreshold) {
      continue;
    }
    result.add(segment.copyWith(index: index, start: start, end: end));
  }
  return result;
}

int? _findSegmentIndex(List<DrawPoint> points, ElbowFixedSegment segment) {
  final preferredIndex = segment.index;
  final fixedHorizontal = _isHorizontal(segment.start, segment.end);
  final maxIndex = points.length - 1;
  const minIndex = 2;
  if (preferredIndex >= minIndex && preferredIndex < maxIndex) {
    final preferredHorizontal =
        _isHorizontal(points[preferredIndex - 1], points[preferredIndex]);
    if (preferredHorizontal == fixedHorizontal) {
      return preferredIndex;
    }
  }
  int? bestIndex;
  var bestIndexDelta = double.infinity;
  for (var i = minIndex; i < maxIndex; i++) {
    if (_isHorizontal(points[i - 1], points[i]) != fixedHorizontal) {
      continue;
    }
    final indexDelta = (i - preferredIndex).abs().toDouble();
    if (indexDelta < bestIndexDelta) {
      bestIndexDelta = indexDelta;
      bestIndex = i;
    }
  }
  return bestIndex;
}

bool _hasDiagonalSegments(List<DrawPoint> points) {
  if (points.length < 2) {
    return false;
  }
  for (var i = 1; i < points.length; i++) {
    final dx = (points[i].x - points[i - 1].x).abs();
    final dy = (points[i].y - points[i - 1].y).abs();
    if (dx > _dedupThreshold && dy > _dedupThreshold) {
      return true;
    }
  }
  return false;
}

bool _segmentsCollinear(DrawPoint a, DrawPoint b, DrawPoint c) {
  final horizontal = _isHorizontal(a, b);
  final nextHorizontal = _isHorizontal(b, c);
  if (horizontal != nextHorizontal) {
    return false;
  }
  if (horizontal) {
    return (a.y - b.y).abs() <= _dedupThreshold &&
        (b.y - c.y).abs() <= _dedupThreshold;
  }
  return (a.x - b.x).abs() <= _dedupThreshold &&
      (b.x - c.x).abs() <= _dedupThreshold;
}

_FixedSegmentPathResult _mergeFixedSegmentWithEndCollinear({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.length < 3 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  final updated = List<DrawPoint>.from(points);
  final updatedSegments = List<ElbowFixedSegment>.from(fixedSegments);
  final neighborIndex = updated.length - 2;
  final fixedIndex = neighborIndex;
  final fixedPos =
      updatedSegments.indexWhere((segment) => segment.index == fixedIndex);
  if (fixedPos == -1) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  final a = updated[neighborIndex - 1];
  final b = updated[neighborIndex];
  final c = updated[neighborIndex + 1];
  if (!_segmentsCollinear(a, b, c)) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  updated.removeAt(neighborIndex);
  final newEnd = updated[neighborIndex];
  updatedSegments[fixedPos] = updatedSegments[fixedPos].copyWith(
    end: newEnd,
    start: updated[neighborIndex - 1],
    index: fixedIndex,
  );
  final reindexed = _reindexFixedSegments(updated, updatedSegments);
  return _FixedSegmentPathResult(
    points: List<DrawPoint>.unmodifiable(updated),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
  );
}

bool _isHorizontal(DrawPoint a, DrawPoint b) =>
    (a.y - b.y).abs() <= (a.x - b.x).abs();

double _manhattanDistance(DrawPoint a, DrawPoint b) =>
    (a.x - b.x).abs() + (a.y - b.y).abs();

bool _pointsEqual(List<DrawPoint> a, List<DrawPoint> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _pointsEqualExceptEndpoints(List<DrawPoint> a, List<DrawPoint> b) {
  if (a.length != b.length) {
    return false;
  }
  if (a.length <= 2) {
    return true;
  }
  for (var i = 1; i < a.length - 1; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _fixedSegmentsEqual(
  List<ElbowFixedSegment> a,
  List<ElbowFixedSegment> b,
) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i].index != b[i].index) {
      return false;
    }
    if (_isHorizontal(a[i].start, a[i].end) !=
        _isHorizontal(b[i].start, b[i].end)) {
      return false;
    }
  }
  return true;
}

List<DrawPoint> _applyFixedSegmentsToPoints(
  List<DrawPoint> points,
  List<ElbowFixedSegment> fixedSegments,
) {
  if (points.length < 2 || fixedSegments.isEmpty) {
    return points;
  }
  final updated = List<DrawPoint>.from(points);
  for (final segment in fixedSegments) {
    final index = segment.index;
    if (index <= 0 || index >= updated.length) {
      continue;
    }
    final start = updated[index - 1];
    final end = updated[index];
    final isHorizontal = _isHorizontal(segment.start, segment.end);
    if (isHorizontal) {
      if ((start.y - end.y).abs() <= _dedupThreshold) {
        continue;
      }
      final axis = (start.y + end.y) / 2;
      updated[index - 1] = start.copyWith(y: axis);
      updated[index] = end.copyWith(y: axis);
    } else {
      if ((start.x - end.x).abs() <= _dedupThreshold) {
        continue;
      }
      final axis = (start.x + end.x) / 2;
      updated[index - 1] = start.copyWith(x: axis);
      updated[index] = end.copyWith(x: axis);
    }
  }
  return List<DrawPoint>.unmodifiable(updated);
}

_FixedSegmentPathResult _applyEndpointDragWithFixedSegments({
  required ElementState element,
  required Map<String, ElementState> elementsById,
  required List<DrawPoint> basePoints,
  required List<DrawPoint> incomingPoints,
  required List<ElbowFixedSegment> fixedSegments,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
}) {
  if (basePoints.length < 2) {
    return _FixedSegmentPathResult(
      points: incomingPoints,
      fixedSegments: fixedSegments,
    );
  }

  final referencePoints = _pointsEqualExceptEndpoints(
        basePoints,
        incomingPoints,
      )
      ? basePoints
      : incomingPoints;
  var updated = List<DrawPoint>.from(referencePoints);
  var workingFixedSegments = fixedSegments;
  updated[0] = incomingPoints.first;
  updated[updated.length - 1] = incomingPoints.last;

  if (startBinding != null || endBinding != null) {
    final baseline = _routeLocalPath(
      element: element,
      elementsById: elementsById,
      startLocal: updated.first,
      endLocal: updated.last,
      startArrowhead: startArrowhead,
      endArrowhead: endArrowhead,
      startBinding: startBinding,
      endBinding: endBinding,
    );
    final mapped = _applyFixedSegmentsToBaselineRoute(
      baseline: baseline,
      fixedSegments: workingFixedSegments,
    );
    if (mapped.fixedSegments.length == workingFixedSegments.length) {
      updated = List<DrawPoint>.from(mapped.points);
      workingFixedSegments = mapped.fixedSegments;
    }
  }

  updated = List<DrawPoint>.from(
    _applyFixedSegmentsToPoints(updated, workingFixedSegments),
  );

  if (startBinding == null &&
      endBinding == null &&
      _hasDiagonalSegments(updated)) {
    final baseline = _routeLocalPath(
      element: element,
      elementsById: elementsById,
      startLocal: updated.first,
      endLocal: updated.last,
      startArrowhead: startArrowhead,
      endArrowhead: endArrowhead,
    );
    final mapped = _applyFixedSegmentsToBaselineRoute(
      baseline: baseline,
      fixedSegments: workingFixedSegments,
    );
    if (mapped.fixedSegments.length == workingFixedSegments.length) {
      updated = List<DrawPoint>.from(mapped.points);
      workingFixedSegments = mapped.fixedSegments;
    }
  }

  final hasStartBinding =
      startBinding != null && elementsById.containsKey(startBinding.elementId);
  final hasEndBinding =
      endBinding != null && elementsById.containsKey(endBinding.elementId);

  if (updated.length > 1 && !hasStartBinding) {
    final start = updated.first;
    final neighbor = updated[1];
    final dx = (neighbor.x - start.x).abs();
    final dy = (neighbor.y - start.y).abs();
    if (dx <= dy) {
      updated[1] = neighbor.copyWith(x: start.x);
    } else {
      updated[1] = neighbor.copyWith(y: start.y);
    }
  }

  if (updated.length > 1 && !hasEndBinding) {
    final lastIndex = updated.length - 1;
    var neighbor = updated[lastIndex - 1];
    final endPoint = updated[lastIndex];
    final dx = (neighbor.x - endPoint.x).abs();
    final dy = (neighbor.y - endPoint.y).abs();
    if (dx <= dy) {
      updated[lastIndex - 1] = neighbor.copyWith(x: endPoint.x);
    } else {
      updated[lastIndex - 1] = neighbor.copyWith(y: endPoint.y);
    }
  }

  updated = List<DrawPoint>.from(
    _applyFixedSegmentsToPoints(updated, workingFixedSegments),
  );

  if (startBinding == null && endBinding == null) {
    final merged = _mergeFixedSegmentWithEndCollinear(
      points: updated,
      fixedSegments: workingFixedSegments,
    );
    if (merged.fixedSegments.length == workingFixedSegments.length) {
      updated = merged.points;
      workingFixedSegments = merged.fixedSegments;
    }
  }

  final synced = _syncFixedSegmentsToPoints(updated, workingFixedSegments);
  if (startBinding == null && endBinding == null) {
    return _FixedSegmentPathResult(points: updated, fixedSegments: synced);
  }
  return _ensurePerpendicularBindings(
    element: element,
    elementsById: elementsById,
    points: updated,
    fixedSegments: synced,
    startBinding: startBinding,
    endBinding: endBinding,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );
}

_FixedSegmentPathResult _ensurePerpendicularBindings({
  required ElementState element,
  required Map<String, ElementState> elementsById,
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
}) {
  if (points.length < 2) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }
  if (startBinding == null && endBinding == null) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  var worldPoints = points.map(space.toWorld).toList(growable: true);
  var updatedFixedSegments = fixedSegments;
  var localPoints = points;
  final baselinePadding = _resolveBaselineEndpointPadding(
    element: element,
    elementsById: elementsById,
    points: points,
    startBinding: startBinding,
    endBinding: endBinding,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );

  if (startBinding != null) {
    final adjustment = _adjustPerpendicularStart(
      points: worldPoints,
      binding: startBinding,
      elementsById: elementsById,
      directionPadding: baselinePadding.start,
    );
    worldPoints = adjustment.points;
    if (adjustment.inserted || adjustment.moved) {
      localPoints = worldPoints.map(space.fromWorld).toList(growable: false);
      updatedFixedSegments = adjustment.inserted
          ? _reindexFixedSegments(localPoints, updatedFixedSegments)
          : _syncFixedSegmentsToPoints(localPoints, updatedFixedSegments);
    }
  }

  if (endBinding != null) {
    final adjustment = _adjustPerpendicularEnd(
      points: worldPoints,
      binding: endBinding,
      elementsById: elementsById,
      directionPadding: baselinePadding.end,
    );
    worldPoints = adjustment.points;
    if (adjustment.inserted || adjustment.moved) {
      localPoints = worldPoints.map(space.fromWorld).toList(growable: false);
      updatedFixedSegments = adjustment.inserted
          ? _reindexFixedSegments(localPoints, updatedFixedSegments)
          : _syncFixedSegmentsToPoints(localPoints, updatedFixedSegments);
    }
  }

  if (!identical(localPoints, points)) {
    return _FixedSegmentPathResult(
      points: localPoints,
      fixedSegments: updatedFixedSegments,
    );
  }

  if (worldPoints.length != points.length) {
    localPoints = worldPoints.map(space.fromWorld).toList(growable: false);
    updatedFixedSegments = _reindexFixedSegments(
      localPoints,
      updatedFixedSegments,
    );
    return _FixedSegmentPathResult(
      points: localPoints,
      fixedSegments: updatedFixedSegments,
    );
  }

  return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
}

({double? start, double? end}) _resolveBaselineEndpointPadding({
  required ElementState element,
  required Map<String, ElementState> elementsById,
  required List<DrawPoint> points,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
}) {
  if (points.length < 2 || (startBinding == null && endBinding == null)) {
    return (start: null, end: null);
  }

  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  final worldStart = space.toWorld(points.first);
  final worldEnd = space.toWorld(points.last);
  final routed = routeElbowArrow(
    start: worldStart,
    end: worldEnd,
    startBinding: startBinding,
    endBinding: endBinding,
    elementsById: elementsById,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );
  final routedPoints = routed.points;
  if (routedPoints.length < 3) {
    return (start: null, end: null);
  }

  final startPadding = startBinding == null
      ? null
      : _segmentPadding(routedPoints.first, routedPoints[1]);
  final endPadding = endBinding == null
      ? null
      : _segmentPadding(
          routedPoints[routedPoints.length - 2],
          routedPoints.last,
        );
  return (start: startPadding, end: endPadding);
}

double? _segmentPadding(DrawPoint from, DrawPoint to) {
  final length = _manhattanDistance(from, to);
  if (!length.isFinite || length <= _dedupThreshold) {
    return null;
  }
  return length;
}

double _resolveDirectionPadding(double? desired) {
  final resolved = desired;
  if (resolved == null || !resolved.isFinite) {
    return _directionFixPadding;
  }
  if (resolved <= _dedupThreshold) {
    return _directionFixPadding;
  }
  return math.max(_directionFixPadding, resolved);
}

_PerpendicularAdjustment? _alignStartSegmentLength({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double? desiredLength,
}) {
  if (points.length < 2 ||
      desiredLength == null ||
      !desiredLength.isFinite ||
      desiredLength <= _dedupThreshold) {
    return null;
  }
  final desiredHorizontal = heading.isHorizontal;
  if (points.length > 2) {
    final nextHorizontal = _isHorizontal(points[1], points[2]);
    if (nextHorizontal != desiredHorizontal) {
      return null;
    }
  }
  final start = points.first;
  final neighbor = points[1];
  final target = _offsetPoint(start, heading, desiredLength);
  final delta = desiredHorizontal
      ? (neighbor.x - target.x).abs()
      : (neighbor.y - target.y).abs();
  if (delta <= _dedupThreshold) {
    return null;
  }
  final updated = List<DrawPoint>.from(points);
  updated[1] = desiredHorizontal
      ? neighbor.copyWith(x: target.x)
      : neighbor.copyWith(y: target.y);
  return _PerpendicularAdjustment(
    points: updated,
    moved: true,
    inserted: false,
  );
}

_PerpendicularAdjustment? _alignEndSegmentLength({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double? desiredLength,
}) {
  if (points.length < 2 ||
      desiredLength == null ||
      !desiredLength.isFinite ||
      desiredLength <= _dedupThreshold) {
    return null;
  }
  final desiredHorizontal = heading.isHorizontal;
  final neighborIndex = points.length - 2;
  if (points.length > 2) {
    final prev = points[neighborIndex - 1];
    final prevHorizontal = _isHorizontal(prev, points[neighborIndex]);
    if (prevHorizontal != desiredHorizontal) {
      return null;
    }
  }
  final endPoint = points.last;
  final neighbor = points[neighborIndex];
  final target = _offsetPoint(endPoint, heading, desiredLength);
  final delta = desiredHorizontal
      ? (neighbor.x - target.x).abs()
      : (neighbor.y - target.y).abs();
  if (delta <= _dedupThreshold) {
    return null;
  }
  final updated = List<DrawPoint>.from(points);
  updated[neighborIndex] = desiredHorizontal
      ? neighbor.copyWith(x: target.x)
      : neighbor.copyWith(y: target.y);
  return _PerpendicularAdjustment(
    points: updated,
    moved: true,
    inserted: false,
  );
}

_PerpendicularAdjustment _adjustPerpendicularStart({
  required List<DrawPoint> points,
  required ArrowBinding binding,
  required Map<String, ElementState> elementsById,
  required double? directionPadding,
}) {
  if (points.length < 2) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final heading = _resolveBoundHeading(
    binding: binding,
    elementsById: elementsById,
    point: points.first,
  );
  if (heading == null) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final desiredHorizontal = heading.isHorizontal;
  final resolvedPadding = _resolveDirectionPadding(directionPadding);
  final start = points.first;
  final neighbor = points[1];
  final aligned = desiredHorizontal
      ? (neighbor.y - start.y).abs() <= _dedupThreshold
      : (neighbor.x - start.x).abs() <= _dedupThreshold;
  final directionOk = _directionMatches(start, neighbor, heading);
  if (aligned && directionOk) {
    final adjusted = _alignStartSegmentLength(
      points: points,
      heading: heading,
      desiredLength: directionPadding,
    );
    if (adjusted != null) {
      return adjusted;
    }
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  if (aligned && !directionOk) {
    final updated = List<DrawPoint>.from(points);
    updated[1] = _applyStartDirection(
      neighbor,
      start,
      heading,
      resolvedPadding,
    );
    return _PerpendicularAdjustment(
      points: updated,
      moved: true,
      inserted: false,
    );
  }

  final nextHorizontal =
      points.length > 2 ? _isHorizontal(neighbor, points[2]) : desiredHorizontal;
  final conflict = nextHorizontal == desiredHorizontal;
  final canShiftDirection =
      points.length <= 2 || (desiredHorizontal ? nextHorizontal : !nextHorizontal);

  if (!conflict && (directionOk || canShiftDirection)) {
    var updatedNeighbor = neighbor;
    if (!aligned) {
      updatedNeighbor = desiredHorizontal
          ? updatedNeighbor.copyWith(y: start.y)
          : updatedNeighbor.copyWith(x: start.x);
    }
    if (!directionOk && canShiftDirection) {
      updatedNeighbor = _applyStartDirection(
        updatedNeighbor,
        start,
        heading,
        resolvedPadding,
      );
    }
    final updated = List<DrawPoint>.from(points);
    updated[1] = updatedNeighbor;
    return _PerpendicularAdjustment(
      points: updated,
      moved: true,
      inserted: false,
    );
  }

  return _insertStartDirectionStub(
    points: points,
    heading: heading,
    neighbor: neighbor,
    allowExtend: true,
    padding: resolvedPadding,
  );
}

_PerpendicularAdjustment _adjustPerpendicularEnd({
  required List<DrawPoint> points,
  required ArrowBinding binding,
  required Map<String, ElementState> elementsById,
  required double? directionPadding,
}) {
  if (points.length < 2) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final heading = _resolveBoundHeading(
    binding: binding,
    elementsById: elementsById,
    point: points.last,
  );
  if (heading == null) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final desiredHorizontal = heading.isHorizontal;
  final resolvedPadding = _resolveDirectionPadding(directionPadding);
  final lastIndex = points.length - 1;
  final neighborIndex = lastIndex - 1;
  final neighbor = points[neighborIndex];
  final endPoint = points[lastIndex];
  final aligned = desiredHorizontal
      ? (neighbor.y - endPoint.y).abs() <= _dedupThreshold
      : (neighbor.x - endPoint.x).abs() <= _dedupThreshold;
  final requiredHeading = heading.opposite;
  final directionOk = _directionMatches(neighbor, endPoint, requiredHeading);
  if (aligned && directionOk) {
    final adjusted = _alignEndSegmentLength(
      points: points,
      heading: heading,
      desiredLength: directionPadding,
    );
    if (adjusted != null) {
      return adjusted;
    }
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  if (aligned && !directionOk) {
    final updated = List<DrawPoint>.from(points);
    updated[neighborIndex] = _applyEndDirection(
      neighbor,
      endPoint,
      requiredHeading,
      resolvedPadding,
    );
    return _PerpendicularAdjustment(
      points: updated,
      moved: true,
      inserted: false,
    );
  }

  final prevHorizontal = points.length > 2
      ? _isHorizontal(points[neighborIndex - 1], neighbor)
      : desiredHorizontal;
  final conflict = prevHorizontal == desiredHorizontal;
  final canShiftDirection =
      points.length <= 2 || (desiredHorizontal ? prevHorizontal : !prevHorizontal);

  if (!conflict && (directionOk || canShiftDirection)) {
    var updatedNeighbor = neighbor;
    if (!aligned) {
      updatedNeighbor = desiredHorizontal
          ? updatedNeighbor.copyWith(y: endPoint.y)
          : updatedNeighbor.copyWith(x: endPoint.x);
    }
    if (!directionOk && canShiftDirection) {
      updatedNeighbor = _applyEndDirection(
        updatedNeighbor,
        endPoint,
        requiredHeading,
        resolvedPadding,
      );
    }
    final updated = List<DrawPoint>.from(points);
    updated[neighborIndex] = updatedNeighbor;
    return _PerpendicularAdjustment(
      points: updated,
      moved: true,
      inserted: false,
    );
  }

  return _insertEndDirectionStub(
    points: points,
    heading: heading,
    neighbor: neighbor,
    allowExtend: true,
    padding: resolvedPadding,
  );
}

ElbowHeading? _resolveBoundHeading({
  required ArrowBinding binding,
  required Map<String, ElementState> elementsById,
  required DrawPoint point,
}) {
  final element = elementsById[binding.elementId];
  if (element == null) {
    return null;
  }
  final bounds = SelectionCalculator.computeElementWorldAabb(element);
  final anchor = ArrowBindingUtils.resolveElbowAnchorPoint(
    binding: binding,
    target: element,
  );
  return ElbowGeometry.headingForPointOnBounds(bounds, anchor ?? point);
}

int? _resolveBaselineSegmentIndex({
  required List<DrawPoint> baseline,
  required bool isHorizontal,
  required int preferredIndex,
  Set<int> usedIndices = const {},
}) {
  if (baseline.length < 2) {
    return null;
  }
  final maxIndex = baseline.length - 1;
  const minIndex = 2;
  int? bestIndex;
  var bestIndexDelta = double.infinity;
  for (var i = minIndex; i < maxIndex; i++) {
    if (usedIndices.contains(i)) {
      continue;
    }
    if (_isHorizontal(baseline[i - 1], baseline[i]) != isHorizontal) {
      continue;
    }
    final indexDelta = (i - preferredIndex).abs().toDouble();
    if (indexDelta < bestIndexDelta) {
      bestIndexDelta = indexDelta;
      bestIndex = i;
    }
  }
  return bestIndex;
}

_FixedSegmentPathResult _applyFixedSegmentsToBaselineRoute({
  required List<DrawPoint> baseline,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (fixedSegments.isEmpty || baseline.length < 2) {
    return _FixedSegmentPathResult(points: baseline, fixedSegments: fixedSegments);
  }

  final updated = List<DrawPoint>.from(baseline);
  final usedIndices = <int>{};
  final mappedSegments = <ElbowFixedSegment>[];

  for (final segment in fixedSegments) {
    final isHorizontal = _isHorizontal(segment.start, segment.end);
    final index = _resolveBaselineSegmentIndex(
      baseline: updated,
      isHorizontal: isHorizontal,
      preferredIndex: segment.index,
      usedIndices: usedIndices,
    );
    if (index == null ||
        index <= 1 ||
        index >= updated.length - 1) {
      continue;
    }
    usedIndices.add(index);
    mappedSegments.add(
      ElbowFixedSegment(
        index: index,
        start: updated[index - 1],
        end: updated[index],
      ),
    );
  }

  return _FixedSegmentPathResult(
    points: List<DrawPoint>.unmodifiable(updated),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(mappedSegments),
  );
}

List<ElbowFixedSegment> _syncFixedSegmentsToPoints(
  List<DrawPoint> points,
  List<ElbowFixedSegment> fixedSegments,
) {
  if (fixedSegments.isEmpty || points.length < 2) {
    return const [];
  }
  final maxIndex = points.length - 1;
  final result = <ElbowFixedSegment>[];
  for (final segment in fixedSegments) {
    final index = segment.index;
    if (index <= 1 || index >= maxIndex) {
      continue;
    }
    if (index < 1 || index >= points.length) {
      continue;
    }
    final start = points[index - 1];
    final end = points[index];
    final length = _manhattanDistance(start, end);
    if (length <= _dedupThreshold) {
      continue;
    }
    result.add(segment.copyWith(index: index, start: start, end: end));
  }
  return result;
}

bool _directionMatches(
  DrawPoint from,
  DrawPoint to,
  ElbowHeading heading,
) => switch (heading) {
  ElbowHeading.right => to.x - from.x > _dedupThreshold,
  ElbowHeading.left => from.x - to.x > _dedupThreshold,
  ElbowHeading.down => to.y - from.y > _dedupThreshold,
  ElbowHeading.up => from.y - to.y > _dedupThreshold,
};

DrawPoint _applyStartDirection(
  DrawPoint neighbor,
  DrawPoint start,
  ElbowHeading heading,
  double padding,
) => switch (heading) {
  ElbowHeading.right => neighbor.x > start.x + padding
      ? neighbor
      : neighbor.copyWith(x: start.x + padding),
  ElbowHeading.left => neighbor.x < start.x - padding
      ? neighbor
      : neighbor.copyWith(x: start.x - padding),
  ElbowHeading.down => neighbor.y > start.y + padding
      ? neighbor
      : neighbor.copyWith(y: start.y + padding),
  ElbowHeading.up => neighbor.y < start.y - padding
      ? neighbor
      : neighbor.copyWith(y: start.y - padding),
};

DrawPoint _applyEndDirection(
  DrawPoint neighbor,
  DrawPoint endPoint,
  ElbowHeading requiredHeading,
  double padding,
) => switch (requiredHeading) {
  ElbowHeading.right => neighbor.x < endPoint.x - padding
      ? neighbor
      : neighbor.copyWith(x: endPoint.x - padding),
  ElbowHeading.left => neighbor.x > endPoint.x + padding
      ? neighbor
      : neighbor.copyWith(x: endPoint.x + padding),
  ElbowHeading.down => neighbor.y < endPoint.y - padding
      ? neighbor
      : neighbor.copyWith(y: endPoint.y - padding),
  ElbowHeading.up => neighbor.y > endPoint.y + padding
      ? neighbor
      : neighbor.copyWith(y: endPoint.y + padding),
};

_PerpendicularAdjustment _insertStartDirectionStub({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required DrawPoint neighbor,
  required bool allowExtend,
  required double padding,
}) {
  if (points.length < 2) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final start = points.first;
  final stub = _offsetPoint(start, heading, padding);
  final connector = heading.isHorizontal
      ? DrawPoint(x: stub.x, y: neighbor.y)
      : DrawPoint(x: neighbor.x, y: stub.y);

  final updated = List<DrawPoint>.from(points);
  var insertIndex = 1;
  var moved = false;
  var inserted = false;

  if (allowExtend && points.length > 2) {
    final next = points[2];
    final nextHorizontal = _isHorizontal(neighbor, next);
    final connectorHorizontal =
        (connector.y - neighbor.y).abs() <= _dedupThreshold;
    final connectorVertical =
        (connector.x - neighbor.x).abs() <= _dedupThreshold;
    final collinear =
        nextHorizontal ? connectorHorizontal : connectorVertical;
    if (collinear) {
      updated[1] = connector;
      moved = true;
    }
  }

  if (_manhattanDistance(stub, start) > _dedupThreshold) {
    updated.insert(insertIndex, stub);
    insertIndex++;
    inserted = true;
  }
  if (!moved &&
      _manhattanDistance(connector, neighbor) > _dedupThreshold &&
      _manhattanDistance(connector, stub) > _dedupThreshold) {
    updated.insert(insertIndex, connector);
    inserted = true;
  }

  return _PerpendicularAdjustment(
    points: updated,
    moved: moved,
    inserted: inserted,
  );
}

_PerpendicularAdjustment _insertEndDirectionStub({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required DrawPoint neighbor,
  required bool allowExtend,
  required double padding,
}) {
  if (points.length < 2) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final endPoint = points.last;
  final stub = _offsetPoint(endPoint, heading, padding);
  final connector = heading.isHorizontal
      ? DrawPoint(x: stub.x, y: neighbor.y)
      : DrawPoint(x: neighbor.x, y: stub.y);

  final updated = List<DrawPoint>.from(points);
  final neighborIndex = updated.length - 2;
  var insertIndex = updated.length - 1;
  var moved = false;
  var inserted = false;

  if (allowExtend && points.length > 2) {
    final prev = points[points.length - 3];
    final prevHorizontal = _isHorizontal(prev, neighbor);
    final connectorHorizontal =
        (connector.y - neighbor.y).abs() <= _dedupThreshold;
    final connectorVertical =
        (connector.x - neighbor.x).abs() <= _dedupThreshold;
    final collinear =
        prevHorizontal ? connectorHorizontal : connectorVertical;
    if (collinear) {
      updated[neighborIndex] = connector;
      moved = true;
    }
  }

  if (!moved &&
      _manhattanDistance(connector, neighbor) > _dedupThreshold &&
      _manhattanDistance(connector, stub) > _dedupThreshold) {
    updated.insert(insertIndex, connector);
    insertIndex++;
    inserted = true;
  }
  if (_manhattanDistance(stub, endPoint) > _dedupThreshold) {
    updated.insert(insertIndex, stub);
    inserted = true;
  }

  return _PerpendicularAdjustment(
    points: updated,
    moved: moved,
    inserted: inserted,
  );
}

DrawPoint _offsetPoint(
  DrawPoint point,
  ElbowHeading heading,
  double distance,
) => DrawPoint(
  x: point.x + heading.dx * distance,
  y: point.y + heading.dy * distance,
);

_FixedSegmentPathResult _handleFixedSegmentRelease({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  required List<DrawPoint> currentPoints,
  required List<ElbowFixedSegment> previousFixed,
  required List<ElbowFixedSegment> remainingFixed,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
}) {
  final removedIndices =
      _resolveRemovedFixedIndices(previousFixed, remainingFixed);
  if (removedIndices.isEmpty || currentPoints.length < 2) {
    return _FixedSegmentPathResult(
      points: currentPoints,
      fixedSegments: remainingFixed,
    );
  }

  final minRemoved = removedIndices.reduce((a, b) => a < b ? a : b);
  final maxRemoved = removedIndices.reduce((a, b) => a > b ? a : b);

  ElbowFixedSegment? previous;
  ElbowFixedSegment? next;
  for (final segment in remainingFixed) {
    if (segment.index < minRemoved) {
      previous = segment;
    } else if (segment.index > maxRemoved) {
      next ??= segment;
    }
  }

  final startIndex = previous?.index ?? 0;
  final endIndex = next != null ? next.index - 1 : currentPoints.length - 1;
  if (startIndex < 0 ||
      endIndex >= currentPoints.length ||
      startIndex >= endIndex) {
    return _FixedSegmentPathResult(
      points: currentPoints,
      fixedSegments: remainingFixed,
    );
  }

  final startPoint = currentPoints[startIndex];
  final endPoint = currentPoints[endIndex];
  final routed = _routeLocalPath(
    element: element,
    elementsById: elementsById,
    startLocal: startPoint,
    endLocal: endPoint,
    startArrowhead: startIndex == 0
        ? data.startArrowhead
        : ArrowheadStyle.none,
    endArrowhead:
        endIndex == currentPoints.length - 1
            ? data.endArrowhead
            : ArrowheadStyle.none,
    startBinding: startIndex == 0 ? startBinding : null,
    endBinding: endIndex == currentPoints.length - 1 ? endBinding : null,
  );

  final prefix = startIndex > 0
      ? currentPoints.sublist(0, startIndex)
      : const <DrawPoint>[];
  final suffix = endIndex + 1 < currentPoints.length
      ? currentPoints.sublist(endIndex + 1)
      : const <DrawPoint>[];

  final stitched = <DrawPoint>[
    ...prefix,
    ...routed,
    ...suffix,
  ];

  return _FixedSegmentPathResult(
    points: List<DrawPoint>.unmodifiable(stitched),
    fixedSegments: remainingFixed,
  );
}

Set<int> _resolveRemovedFixedIndices(
  List<ElbowFixedSegment> previous,
  List<ElbowFixedSegment> remaining,
) {
  if (previous.isEmpty) {
    return const {};
  }
  final previousIndices = previous.map((segment) => segment.index).toSet();
  final remainingIndices = remaining.map((segment) => segment.index).toSet();
  return previousIndices.difference(remainingIndices);
}

Set<DrawPoint> _collectPinnedPoints({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.isEmpty) {
    return const <DrawPoint>{};
  }
  final pinned = <DrawPoint>{
    points.first,
    points.last,
  };
  for (final segment in fixedSegments) {
    final index = segment.index;
    if (index <= 0 || index >= points.length) {
      continue;
    }
    pinned
      ..add(points[index - 1])
      ..add(points[index]);
  }
  return pinned;
}

