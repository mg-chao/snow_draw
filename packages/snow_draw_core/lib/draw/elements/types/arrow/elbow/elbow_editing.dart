import 'package:meta/meta.dart';

import '../../../../core/coordinates/element_space.dart';
import '../../../../models/element_state.dart';
import '../../../../types/draw_point.dart';
import '../../../../types/draw_rect.dart';
import '../../../../types/element_style.dart';
import '../arrow_binding.dart';
import '../arrow_data.dart';
import '../arrow_geometry.dart';
import 'elbow_fixed_segment.dart';
import 'elbow_router.dart';

const double _dedupThreshold = 1;

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

ElbowEditResult computeElbowEdit({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  List<DrawPoint>? localPointsOverride,
  List<ElbowFixedSegment>? fixedSegmentsOverride,
  ArrowBinding? startBindingOverride,
  ArrowBinding? endBindingOverride,
}) {
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
    final pinned = _collectPinnedPoints(
      points: updated.points,
      fixedSegments: updated.fixedSegments,
    );
    final simplified = _simplifyPath(updated.points, pinned: pinned);
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

  if (pointsChanged && !fixedSegmentsChanged) {
    final updated = _applyEndpointDragWithFixedSegments(
      basePoints: basePoints,
      incomingPoints: incomingPoints,
      fixedSegments: fixedSegments,
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

  var workingPoints = incomingPoints;
  if (!pointsChanged && fixedSegmentsChanged) {
    workingPoints = _applyFixedSegmentsToPoints(basePoints, fixedSegments);
  }

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
  required ArrowData data,
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
    final index = _findSegmentIndex(points, segment.start, segment.end);
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

int? _findSegmentIndex(List<DrawPoint> points, DrawPoint start, DrawPoint end) {
  for (var i = 1; i < points.length; i++) {
    if (points[i - 1] == start && points[i] == end) {
      return i;
    }
  }
  return null;
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

bool _fixedSegmentsEqual(
  List<ElbowFixedSegment> a,
  List<ElbowFixedSegment> b,
) {
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
    updated[index - 1] = segment.start;
    updated[index] = segment.end;
  }
  return List<DrawPoint>.unmodifiable(updated);
}

_FixedSegmentPathResult _applyEndpointDragWithFixedSegments({
  required List<DrawPoint> basePoints,
  required List<DrawPoint> incomingPoints,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (basePoints.length < 2) {
    return _FixedSegmentPathResult(
      points: incomingPoints,
      fixedSegments: fixedSegments,
    );
  }

  final updated = List<DrawPoint>.from(basePoints);
  updated[0] = incomingPoints.first;
  updated[updated.length - 1] = incomingPoints.last;

  for (final segment in fixedSegments) {
    final index = segment.index;
    if (index <= 0 || index >= updated.length) {
      continue;
    }
    final isHorizontal = _isHorizontal(segment.start, segment.end);
    if (isHorizontal) {
      updated[index - 1] = updated[index - 1].copyWith(y: segment.start.y);
      updated[index] = updated[index].copyWith(y: segment.start.y);
    } else {
      updated[index - 1] = updated[index - 1].copyWith(x: segment.start.x);
      updated[index] = updated[index].copyWith(x: segment.start.x);
    }
  }

  if (updated.length > 1) {
    final isHorizontal = _isHorizontal(basePoints[0], basePoints[1]);
    if (isHorizontal) {
      updated[1] = updated[1].copyWith(y: updated.first.y);
    } else {
      updated[1] = updated[1].copyWith(x: updated.first.x);
    }
  }

  if (updated.length > 1) {
    final lastIndex = updated.length - 1;
    final isHorizontal = _isHorizontal(
      basePoints[lastIndex - 1],
      basePoints[lastIndex],
    );
    if (isHorizontal) {
      updated[lastIndex - 1] =
          updated[lastIndex - 1].copyWith(y: updated.last.y);
    } else {
      updated[lastIndex - 1] =
          updated[lastIndex - 1].copyWith(x: updated.last.x);
    }
  }

  final synced = _syncFixedSegmentsToPoints(updated, fixedSegments);
  return _FixedSegmentPathResult(points: updated, fixedSegments: synced);
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
    data: data,
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
  return {
    points.first,
    points.last,
    for (final segment in fixedSegments) segment.start,
    for (final segment in fixedSegments) segment.end,
  };
}
