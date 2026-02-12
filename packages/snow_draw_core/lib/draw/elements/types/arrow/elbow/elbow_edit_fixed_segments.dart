part of 'elbow_editing.dart';

bool _isInteriorSegmentIndex(int index, int pointCount) =>
    index > 1 && index < pointCount - 1;

List<ElbowFixedSegment> _sanitizeFixedSegments(
  List<ElbowFixedSegment>? segments,
  int pointCount,
) {
  if (segments == null || segments.isEmpty || pointCount < 2) {
    return const [];
  }
  final result = <ElbowFixedSegment>[];
  for (final segment in segments) {
    if (!_isInteriorSegmentIndex(segment.index, pointCount)) {
      continue;
    }
    // Reject diagonal or degenerate segments.
    if (ElbowGeometry.axisAlignedForSegment(segment.start, segment.end) ==
        null) {
      continue;
    }
    if (!segment.isSignificant) {
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

_FixedSegmentPathResult _stitchSubPath({
  required List<DrawPoint> points,
  required int startIndex,
  required int endIndex,
  required List<DrawPoint> subPath,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  final prefix = points.sublist(0, startIndex);
  final suffix = endIndex + 1 < points.length
      ? points.sublist(endIndex + 1)
      : const <DrawPoint>[];
  final stitched = <DrawPoint>[...prefix, ...subPath, ...suffix];
  final reindexed = _reindexFixedSegments(stitched, fixedSegments);
  return _FixedSegmentPathResult(
    points: List<DrawPoint>.unmodifiable(stitched),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
  );
}

List<ElbowFixedSegment> _reindexFixedSegments(
  List<DrawPoint> points,
  List<ElbowFixedSegment> fixedSegments,
) {
  if (fixedSegments.isEmpty || points.length < 2) {
    return const [];
  }
  final result = <ElbowFixedSegment>[];
  for (final segment in fixedSegments) {
    final index = _selectSegmentIndex(
      points: points,
      isHorizontal: segment.isHorizontal,
      preferredIndex: segment.index,
      axisValue: segment.axisValue,
    );
    if (index == null || !_isInteriorSegmentIndex(index, points.length)) {
      continue;
    }
    final start = points[index - 1];
    final end = points[index];
    if (ElbowGeometry.manhattanDistance(start, end) <=
        ElbowConstants.dedupThreshold) {
      continue;
    }
    result.add(segment.copyWith(index: index, start: start, end: end));
  }
  return result;
}

int? _selectSegmentIndex({
  required List<DrawPoint> points,
  required bool isHorizontal,
  required int preferredIndex,
  required double axisValue,
  double axisTolerance = double.infinity,
  Set<int> usedIndices = const {},
}) {
  if (points.length < 2) {
    return null;
  }
  final maxIndex = points.length - 1;
  const minIndex = 2;
  int? bestIndex;
  var bestAxisDelta = double.infinity;
  var bestIndexDelta = double.infinity;
  final axis = isHorizontal ? ElbowAxis.horizontal : ElbowAxis.vertical;
  for (var i = minIndex; i < maxIndex; i++) {
    if (usedIndices.contains(i)) {
      continue;
    }
    if (ElbowGeometry.segmentIsHorizontal(points[i - 1], points[i]) !=
        isHorizontal) {
      continue;
    }
    final candidateAxis = ElbowGeometry.axisValue(
      points[i - 1],
      points[i],
      axis: axis,
    );
    final axisDelta = (candidateAxis - axisValue).abs();
    if (axisDelta > axisTolerance) {
      continue;
    }
    final indexDelta = (i - preferredIndex).abs().toDouble();
    final axisCloser =
        axisDelta < bestAxisDelta - ElbowConstants.dedupThreshold;
    final axisTie =
        (axisDelta - bestAxisDelta).abs() <= ElbowConstants.dedupThreshold;
    if (axisCloser || (axisTie && indexDelta < bestIndexDelta)) {
      bestAxisDelta = axisDelta;
      bestIndexDelta = indexDelta;
      bestIndex = i;
    }
  }
  return bestIndex;
}

bool? _fixedSegmentIsHorizontal(
  List<ElbowFixedSegment> fixedSegments,
  int index,
) {
  for (final segment in fixedSegments) {
    if (segment.index == index) {
      return segment.isHorizontal;
    }
  }
  return null;
}

bool _fixedSegmentsEqual(List<ElbowFixedSegment> a, List<ElbowFixedSegment> b) {
  if (!_fixedSegmentAxesStable(a, b)) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i].index != b[i].index) {
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
    final axis = segment.axisValue;
    if (segment.isHorizontal) {
      if ((start.y - axis).abs() <= ElbowConstants.dedupThreshold &&
          (end.y - axis).abs() <= ElbowConstants.dedupThreshold) {
        continue;
      }
      updated[index - 1] = start.copyWith(y: axis);
      updated[index] = end.copyWith(y: axis);
    } else {
      if ((start.x - axis).abs() <= ElbowConstants.dedupThreshold &&
          (end.x - axis).abs() <= ElbowConstants.dedupThreshold) {
        continue;
      }
      updated[index - 1] = start.copyWith(x: axis);
      updated[index] = end.copyWith(x: axis);
    }
  }
  return List<DrawPoint>.unmodifiable(updated);
}

_FixedSegmentPathResult? _mapFixedSegmentsToBaseline({
  required List<DrawPoint> baseline,
  required List<ElbowFixedSegment> fixedSegments,
  ElbowFixedSegment? activeSegment,
  bool enforceAxisOnPoints = false,
  bool requireAll = false,
}) {
  if (baseline.length < 2) {
    return requireAll
        ? null
        : _FixedSegmentPathResult(
            points: baseline,
            fixedSegments: fixedSegments,
          );
  }
  if (fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(
      points: requireAll
          ? List<DrawPoint>.unmodifiable(List<DrawPoint>.from(baseline))
          : baseline,
      fixedSegments: requireAll ? const [] : fixedSegments,
    );
  }

  final updated = List<DrawPoint>.from(baseline);
  final usedIndices = <int>{};
  final mappedSegments = <ElbowFixedSegment>[];

  for (final segment in fixedSegments) {
    final isActive =
        activeSegment != null && segment.index == activeSegment.index;
    final index = _selectSegmentIndex(
      points: updated,
      isHorizontal: segment.isHorizontal,
      preferredIndex: segment.index,
      axisValue: segment.axisValue,
      axisTolerance: isActive ? double.infinity : ElbowConstants.dedupThreshold,
      usedIndices: usedIndices,
    );
    if (index == null || index <= 1 || index >= updated.length - 1) {
      if (requireAll) {
        return null;
      }
      continue;
    }
    usedIndices.add(index);
    var start = updated[index - 1];
    var end = updated[index];
    if (!isActive) {
      final axis = segment.axisValue;
      final alignedStart = segment.isHorizontal
          ? start.copyWith(y: axis)
          : start.copyWith(x: axis);
      final alignedEnd = segment.isHorizontal
          ? end.copyWith(y: axis)
          : end.copyWith(x: axis);
      if (enforceAxisOnPoints) {
        updated[index - 1] = alignedStart;
        updated[index] = alignedEnd;
      }
      start = alignedStart;
      end = alignedEnd;
    }
    mappedSegments.add(ElbowFixedSegment(index: index, start: start, end: end));
  }

  if (requireAll && mappedSegments.length != fixedSegments.length) {
    return null;
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
    final start = points[index - 1];
    final end = points[index];
    if (ElbowGeometry.manhattanDistance(start, end) <=
        ElbowConstants.dedupThreshold) {
      continue;
    }
    result.add(segment.copyWith(index: index, start: start, end: end));
  }
  return result;
}

/// Removes adjacent near-duplicate points, reindexing fixed segments.
///
/// Returns the original lists unchanged when no duplicates are found or
/// when reindexing would lose a fixed segment.
({List<DrawPoint> points, List<ElbowFixedSegment> fixedSegments})
_deduplicateAdjacentPoints({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  Set<DrawPoint> pinned = const {},
}) {
  if (points.length < 2) {
    return (points: points, fixedSegments: fixedSegments);
  }
  final cleaned = <DrawPoint>[points.first];
  for (var i = 1; i < points.length; i++) {
    final current = points[i];
    if (current == cleaned.last) {
      continue;
    }
    if (!pinned.contains(current) &&
        ElbowGeometry.manhattanDistance(cleaned.last, current) <=
            ElbowConstants.dedupThreshold) {
      continue;
    }
    cleaned.add(current);
  }
  if (cleaned.length == points.length) {
    return (points: points, fixedSegments: fixedSegments);
  }
  final reindexed = _reindexFixedSegments(cleaned, fixedSegments);
  if (reindexed.length != fixedSegments.length) {
    return (points: points, fixedSegments: fixedSegments);
  }
  return (
    points: List<DrawPoint>.unmodifiable(cleaned),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
  );
}

/// Tries to merge a single collinear non-fixed neighbor into one segment.
///
/// Returns `null` when no merge is possible.
_FixedSegmentPathResult? _tryMergeCollinearNeighbor({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> segments,
  required int segmentListIndex,
  required Set<int> fixedIndices,
}) {
  final segment = segments[segmentListIndex];
  final index = segment.index;
  if (index <= 1 || index >= points.length) {
    return null;
  }
  for (final offset in const [-1, 1]) {
    final removeIndex = offset == -1 ? index - 1 : index;
    final neighborIndex = offset == -1 ? index - 1 : index + 1;
    if (removeIndex < 1 || neighborIndex >= points.length) {
      continue;
    }
    if (fixedIndices.contains(neighborIndex)) {
      continue;
    }
    final a = points[removeIndex - 1];
    final b = points[removeIndex];
    final c = points[removeIndex + 1];
    if (!ElbowGeometry.segmentsCollinear(a, b, c)) {
      continue;
    }
    final candidatePoints = List<DrawPoint>.from(points)..removeAt(removeIndex);
    final newIndex = offset == -1 ? index - 1 : index;
    final candidateSegments = List<ElbowFixedSegment>.from(segments);
    candidateSegments[segmentListIndex] = segment.copyWith(
      index: newIndex,
      start: a,
      end: candidatePoints[newIndex],
    );
    final reindexed = _reindexFixedSegments(candidatePoints, candidateSegments);
    if (reindexed.length == segments.length) {
      return _FixedSegmentPathResult(
        points: candidatePoints,
        fixedSegments: reindexed,
      );
    }
  }
  return null;
}

_FixedSegmentPathResult _mergeFixedSegmentsWithCollinearNeighbors({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  bool allowDirectionFlip = false,
  Set<DrawPoint> pinned = const {},
}) {
  if (points.length < 3 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }
  final deduped = _deduplicateAdjacentPoints(
    points: points,
    fixedSegments: fixedSegments,
    pinned: pinned,
  );

  // Collapse backtracks around fixed segments (skip when direction
  // flips are allowed, matching the original release-path behavior).
  var updatedPoints = List<DrawPoint>.from(deduped.points);
  var updatedSegments = List<ElbowFixedSegment>.from(deduped.fixedSegments);
  if (!allowDirectionFlip &&
      updatedPoints.length >= 4 &&
      updatedSegments.isNotEmpty) {
    var changed = true;
    while (changed) {
      changed = false;
      for (final segment in updatedSegments) {
        if (segment.index <= 0 || segment.index + 2 >= updatedPoints.length) {
          continue;
        }
        final collapsed = _tryCollapseBacktrackAt(
          points: updatedPoints,
          fixedSegments: updatedSegments,
          removeIndex: segment.index + 1,
          afterIndex: segment.index + 2,
          isHorizontal: segment.isHorizontal,
        );
        if (collapsed == null) {
          continue;
        }
        updatedPoints = List<DrawPoint>.from(collapsed.points);
        updatedSegments = List<ElbowFixedSegment>.from(collapsed.fixedSegments);
        changed = true;
        break;
      }
    }
  }

  // Merge collinear non-fixed neighbors into adjacent fixed segments.
  var merged = true;
  while (merged) {
    merged = false;
    final fixedIndices = updatedSegments.map((s) => s.index).toSet();
    for (var i = 0; i < updatedSegments.length; i++) {
      final result = _tryMergeCollinearNeighbor(
        points: updatedPoints,
        segments: updatedSegments,
        segmentListIndex: i,
        fixedIndices: fixedIndices,
      );
      if (result != null) {
        updatedPoints = List<DrawPoint>.from(result.points);
        updatedSegments = List<ElbowFixedSegment>.from(result.fixedSegments);
        merged = true;
        break;
      }
    }
  }
  return _collapseEndpointBacktracks(
    points: List<DrawPoint>.unmodifiable(updatedPoints),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(updatedSegments),
  );
}

/// Detects a collinear backtrack at [removeIndex] and tries to collapse it.
///
/// Returns `null` when no valid collapse is possible.
_FixedSegmentPathResult? _tryCollapseBacktrackAt({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  required int removeIndex,
  required int afterIndex,
  required bool isHorizontal,
}) {
  if (removeIndex < 1 || removeIndex >= points.length - 1) {
    return null;
  }
  final prev = points[removeIndex - 1];
  final curr = points[removeIndex];
  final next = points[removeIndex + 1];
  if (!ElbowGeometry.segmentsCollinear(prev, curr, next)) {
    return null;
  }
  final d1 = isHorizontal ? curr.x - prev.x : curr.y - prev.y;
  final d2 = isHorizontal ? next.x - curr.x : next.y - curr.y;
  if (d1.abs() <= ElbowConstants.dedupThreshold ||
      d2.abs() <= ElbowConstants.dedupThreshold ||
      d1 * d2 >= 0) {
    return null;
  }
  final candidate = List<DrawPoint>.from(points)..removeAt(removeIndex);
  if (afterIndex < candidate.length) {
    final after =
        candidate[afterIndex > removeIndex ? afterIndex - 1 : afterIndex];
    final ref = candidate[removeIndex > 0 ? removeIndex - 1 : 0];
    if (!ElbowGeometry.pointsAligned(ref, after)) {
      final corner = isHorizontal
          ? DrawPoint(x: ref.x, y: after.y)
          : DrawPoint(x: after.x, y: ref.y);
      if (!ElbowGeometry.pointsClose(corner, ref) &&
          !ElbowGeometry.pointsClose(corner, after)) {
        candidate.insert(removeIndex, corner);
      }
    }
  }
  final reindexed = _reindexFixedSegments(candidate, fixedSegments);
  if (reindexed.length != fixedSegments.length) {
    return null;
  }
  return _FixedSegmentPathResult(
    points: List<DrawPoint>.unmodifiable(candidate),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
  );
}

_FixedSegmentPathResult _collapseEndpointBacktracks({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.length < 3 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }
  final pinned = _collectPinnedPoints(
    points: points,
    fixedSegments: fixedSegments,
  );
  var result = _FixedSegmentPathResult(
    points: points,
    fixedSegments: fixedSegments,
  );
  for (final isStart in const [true, false]) {
    if (result.points.length < 3) {
      continue;
    }
    final midIndex = isStart ? 1 : result.points.length - 2;
    if (pinned.contains(result.points[midIndex])) {
      continue;
    }
    final axis =
        ElbowGeometry.axisAlignedForSegment(
          result.points[isStart ? 0 : result.points.length - 3],
          result.points[midIndex],
        ) ??
        ElbowGeometry.axisAlignedForSegment(
          result.points[midIndex],
          result.points[isStart ? 2 : result.points.length - 1],
        );
    if (axis == null) {
      continue;
    }
    final collapsed = _tryCollapseBacktrackAt(
      points: result.points,
      fixedSegments: result.fixedSegments,
      removeIndex: midIndex,
      afterIndex: midIndex, // no corner insertion for endpoints
      isHorizontal: axis.isHorizontal,
    );
    if (collapsed != null) {
      result = collapsed;
    }
  }
  return result;
}

Set<DrawPoint> _collectPinnedPoints({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.isEmpty) {
    return const <DrawPoint>{};
  }
  final pinned = <DrawPoint>{points.first, points.last};
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

/// Returns the interior corner points of a path (excludes endpoints).
Set<DrawPoint> _interiorCornerPoints(List<DrawPoint> points) {
  final corners = ElbowGeometry.cornerPoints(points);
  return corners.length > 2
      ? corners.sublist(1, corners.length - 1).toSet()
      : const <DrawPoint>{};
}

/// Normalizes an elbow path with fixed segments through a standard
/// sequence of transformations.
///
/// Steps: apply fixed axes → simplify (preserving pinned points) →
/// reindex → merge collinear neighbors → collapse backtracks.
_FixedSegmentPathResult _normalizeFixedSegmentPath({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  Set<DrawPoint> extraPinned = const {},
  bool enforceAxes = false,
  bool allowDirectionFlip = false,
}) {
  if (points.length < 2 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }
  final enforced = enforceAxes
      ? _applyFixedSegmentsToPoints(points, fixedSegments)
      : points;
  final pinned = {
    ..._collectPinnedPoints(points: enforced, fixedSegments: fixedSegments),
    ...extraPinned,
  };
  final simplified = ElbowGeometry.simplifyPath(enforced, pinned: pinned);
  final reindexed = _reindexFixedSegments(simplified, fixedSegments);
  final activeFixed = reindexed.length == fixedSegments.length
      ? reindexed
      : fixedSegments;
  return _mergeFixedSegmentsWithCollinearNeighbors(
    points: simplified,
    fixedSegments: activeFixed,
    allowDirectionFlip: allowDirectionFlip,
    pinned: {
      ..._collectPinnedPoints(points: simplified, fixedSegments: activeFixed),
      ...extraPinned,
    },
  );
}

ElbowEditResult _finalizeElbowEditResult({
  required ElementState element,
  required ArrowData data,
  required CombinedElementLookup lookup,
  required ElbowEditResult result,
  required ArrowBinding? startBindingOverride,
  required ArrowBinding? endBindingOverride,
  required bool startBindingOverrideIsSet,
  required bool endBindingOverrideIsSet,
}) {
  final fixedSegments = result.fixedSegments;
  if (fixedSegments == null || fixedSegments.isEmpty) {
    return result;
  }
  final toDrop = _fixedSegmentsWithSameHeadingAdjacency(
    points: result.localPoints,
    fixedSegments: fixedSegments,
  );
  if (toDrop.isEmpty) {
    return result;
  }
  final remaining = fixedSegments
      .where((segment) => !toDrop.contains(segment.index))
      .toList(growable: false);
  if (remaining.length == fixedSegments.length) {
    return result;
  }

  return computeElbowEdit(
    element: element,
    data: data,
    lookup: lookup,
    localPointsOverride: result.localPoints,
    fixedSegmentsOverride: remaining,
    startBindingOverride: startBindingOverride,
    endBindingOverride: endBindingOverride,
    startBindingOverrideIsSet: startBindingOverrideIsSet,
    endBindingOverrideIsSet: endBindingOverrideIsSet,
  );
}

Set<int> _fixedSegmentsWithSameHeadingAdjacency({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.length < 3 || fixedSegments.isEmpty) {
    return const <int>{};
  }

  final fixedIndices = fixedSegments.map((segment) => segment.index).toSet();
  final toDrop = <int>{};

  for (var i = 1; i < points.length - 1; i++) {
    final a = points[i - 1];
    final b = points[i];
    final c = points[i + 1];
    final prevLength = ElbowGeometry.manhattanDistance(a, b);
    final nextLength = ElbowGeometry.manhattanDistance(b, c);
    if (prevLength <= ElbowConstants.dedupThreshold ||
        nextLength <= ElbowConstants.dedupThreshold) {
      continue;
    }
    final prevHeading = ElbowGeometry.headingForSegment(a, b);
    final nextHeading = ElbowGeometry.headingForSegment(b, c);
    if (prevHeading != nextHeading) {
      continue;
    }
    final prevIndex = i;
    final nextIndex = i + 1;
    if (fixedIndices.contains(prevIndex)) {
      toDrop.add(prevIndex);
    }
    if (fixedIndices.contains(nextIndex)) {
      toDrop.add(nextIndex);
    }
  }

  return toDrop;
}

// ---------------------------------------------------------------------------
// Routing helpers (merged from elbow_edit_routing.dart)
// ---------------------------------------------------------------------------

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
  final routed = routeElbowArrowForElementPoints(
    element: element,
    startLocal: startLocal,
    endLocal: endLocal,
    elementsById: elementsById,
    startBinding: startBinding,
    endBinding: endBinding,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );
  return routed.localPoints;
}

List<DrawPoint> _routeReleasedRegion({
  required ElementState element,
  required Map<String, ElementState> elementsById,
  required DrawPoint startLocal,
  required DrawPoint endLocal,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
  required ElbowFixedSegment? previousFixed,
  required ElbowFixedSegment? nextFixed,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
}) {
  // When no bindings constrain the route, prefer the axis that continues
  // the adjacent fixed segment's pattern via a cheap direct elbow.
  if (startBinding == null && endBinding == null) {
    final preferHorizontal = previousFixed != null && nextFixed == null
        ? previousFixed.isHorizontal
        : (nextFixed != null && previousFixed == null
              ? !nextFixed.isHorizontal
              : null);
    if (preferHorizontal != null) {
      return ElbowGeometry.directElbowPath(
        startLocal,
        endLocal,
        preferHorizontal: preferHorizontal,
        epsilon: ElbowConstants.intersectionEpsilon,
      );
    }
  }

  return _routeLocalPath(
    element: element,
    elementsById: elementsById,
    startLocal: startLocal,
    endLocal: endLocal,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
    startBinding: startBinding,
    endBinding: endBinding,
  );
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
  final previousIndices = previousFixed.map((segment) => segment.index).toSet();
  final remainingIndices = remainingFixed
      .map((segment) => segment.index)
      .toSet();
  final removedIndices = previousIndices.difference(remainingIndices);
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
  final routed = _routeReleasedRegion(
    element: element,
    elementsById: elementsById,
    startLocal: startPoint,
    endLocal: endPoint,
    startArrowhead: startIndex == 0 ? data.startArrowhead : ArrowheadStyle.none,
    endArrowhead: endIndex == currentPoints.length - 1
        ? data.endArrowhead
        : ArrowheadStyle.none,
    previousFixed: previous,
    nextFixed: next,
    startBinding: startIndex == 0 ? startBinding : null,
    endBinding: endIndex == currentPoints.length - 1 ? endBinding : null,
  );

  return _stitchSubPath(
    points: currentPoints,
    startIndex: startIndex,
    endIndex: endIndex,
    subPath: routed,
    fixedSegments: remainingFixed,
  );
}
