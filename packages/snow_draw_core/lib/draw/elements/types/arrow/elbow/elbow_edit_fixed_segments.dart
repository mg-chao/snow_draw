part of 'elbow_editing.dart';

/// Fixed-segment utilities for elbow editing.
///
/// These helpers sanitize, map, and reindex pinned segments to keep their
/// axis stable while the rest of the path updates.

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
    final dx = (segment.start.x - segment.end.x).abs();
    final dy = (segment.start.y - segment.end.y).abs();
    if (dx > ElbowConstants.dedupThreshold &&
        dy > ElbowConstants.dedupThreshold) {
      continue;
    }
    final length = ElbowGeometry.manhattanDistance(segment.start, segment.end);
    if (length <= ElbowConstants.dedupThreshold) {
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

List<ElbowFixedSegment> _reindexFixedSegments(
  List<DrawPoint> points,
  List<ElbowFixedSegment> fixedSegments,
) {
  if (fixedSegments.isEmpty || points.length < 2) {
    return const [];
  }
  final result = <ElbowFixedSegment>[];
  for (final segment in fixedSegments) {
    final index = _findSegmentIndex(points, segment);
    if (index == null || !_isInteriorSegmentIndex(index, points.length)) {
      continue;
    }
    final start = points[index - 1];
    final end = points[index];
    final length = ElbowGeometry.manhattanDistance(start, end);
    if (length <= ElbowConstants.dedupThreshold) {
      continue;
    }
    result.add(segment.copyWith(index: index, start: start, end: end));
  }
  return result;
}

int? _findSegmentIndex(List<DrawPoint> points, ElbowFixedSegment segment) {
  final isHorizontal = ElbowPathUtils.segmentIsHorizontal(
    segment.start,
    segment.end,
  );
  final axis = ElbowPathUtils.axisValue(
    segment.start,
    segment.end,
    axis: isHorizontal ? ElbowAxis.horizontal : ElbowAxis.vertical,
  );
  return _selectSegmentIndex(
    points: points,
    isHorizontal: isHorizontal,
    preferredIndex: segment.index,
    axisValue: axis,
  );
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
    if (ElbowPathUtils.segmentIsHorizontal(points[i - 1], points[i]) !=
        isHorizontal) {
      continue;
    }
    final candidateAxis = ElbowPathUtils.axisValue(
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
      return ElbowPathUtils.segmentIsHorizontal(segment.start, segment.end);
    }
  }
  return null;
}

bool _fixedSegmentsEqual(List<ElbowFixedSegment> a, List<ElbowFixedSegment> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i].index != b[i].index) {
      return false;
    }
    final aHorizontal = ElbowPathUtils.segmentIsHorizontal(
      a[i].start,
      a[i].end,
    );
    final bHorizontal = ElbowPathUtils.segmentIsHorizontal(
      b[i].start,
      b[i].end,
    );
    if (aHorizontal != bHorizontal) {
      return false;
    }
    final axis = aHorizontal ? ElbowAxis.horizontal : ElbowAxis.vertical;
    final aAxis = ElbowPathUtils.axisValue(a[i].start, a[i].end, axis: axis);
    final bAxis = ElbowPathUtils.axisValue(b[i].start, b[i].end, axis: axis);
    if ((aAxis - bAxis).abs() > ElbowConstants.dedupThreshold) {
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
    final isHorizontal = ElbowPathUtils.segmentIsHorizontal(
      segment.start,
      segment.end,
    );
    final axis = isHorizontal
        ? (segment.start.y + segment.end.y) / 2
        : (segment.start.x + segment.end.x) / 2;
    if (isHorizontal) {
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
    return requireAll
        ? _FixedSegmentPathResult(
            points: List<DrawPoint>.unmodifiable(
              List<DrawPoint>.from(baseline),
            ),
            fixedSegments: const [],
          )
        : _FixedSegmentPathResult(
            points: baseline,
            fixedSegments: fixedSegments,
          );
  }

  final updated = List<DrawPoint>.from(baseline);
  final usedIndices = <int>{};
  final mappedSegments = <ElbowFixedSegment>[];

  for (final segment in fixedSegments) {
    final isActive =
        activeSegment != null && segment.index == activeSegment.index;
    final isHorizontal = ElbowPathUtils.segmentIsHorizontal(
      segment.start,
      segment.end,
    );
    final axisType = isHorizontal ? ElbowAxis.horizontal : ElbowAxis.vertical;
    final axis = ElbowPathUtils.axisValue(
      segment.start,
      segment.end,
      axis: axisType,
    );
    final index = _selectSegmentIndex(
      points: updated,
      isHorizontal: isHorizontal,
      preferredIndex: segment.index,
      axisValue: axis,
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
      final alignedStart = isHorizontal
          ? start.copyWith(y: axis)
          : start.copyWith(x: axis);
      final alignedEnd = isHorizontal
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

_FixedSegmentPathResult _applyFixedSegmentsToBaselineRoute({
  required List<DrawPoint> baseline,
  required List<ElbowFixedSegment> fixedSegments,
}) =>
    _mapFixedSegmentsToBaseline(
      baseline: baseline,
      fixedSegments: fixedSegments,
    ) ??
    _FixedSegmentPathResult(points: baseline, fixedSegments: fixedSegments);

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
    final length = ElbowGeometry.manhattanDistance(start, end);
    if (length <= ElbowConstants.dedupThreshold) {
      continue;
    }
    result.add(segment.copyWith(index: index, start: start, end: end));
  }
  return result;
}

_FixedSegmentPathResult _mergeFixedSegmentWithEndCollinear({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.length < 3 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final updated = List<DrawPoint>.from(points);
  final updatedSegments = List<ElbowFixedSegment>.from(fixedSegments);
  final neighborIndex = updated.length - 2;
  final fixedIndex = neighborIndex;
  final fixedPos = updatedSegments.indexWhere(
    (segment) => segment.index == fixedIndex,
  );
  if (fixedPos == -1) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final a = updated[neighborIndex - 1];
  final b = updated[neighborIndex];
  final c = updated[neighborIndex + 1];
  if (!ElbowPathUtils.segmentsCollinear(a, b, c)) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
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

  final deduped = _removeAdjacentDuplicates(
    points: points,
    fixedSegments: fixedSegments,
    pinned: pinned,
  );
  final collapsed = allowDirectionFlip
      ? deduped
      : _collapseFixedSegmentBacktracks(
          points: deduped.points,
          fixedSegments: deduped.fixedSegments,
        );
  var updatedPoints = List<DrawPoint>.from(collapsed.points);
  var updatedSegments = List<ElbowFixedSegment>.from(collapsed.fixedSegments);
  var merged = true;

  while (merged) {
    merged = false;
    final fixedIndices = updatedSegments
        .map((segment) => segment.index)
        .toSet();

    for (var i = 0; i < updatedSegments.length; i++) {
      final segment = updatedSegments[i];
      final index = segment.index;
      if (index <= 1 || index >= updatedPoints.length) {
        continue;
      }

      // Merge with the previous segment if it is collinear and not fixed.
      if (index >= 2 && !fixedIndices.contains(index - 1)) {
        final aIndex = index - 2;
        final bIndex = index - 1;
        final cIndex = index;
        if (aIndex >= 0 && cIndex < updatedPoints.length) {
          final a = updatedPoints[aIndex];
          final b = updatedPoints[bIndex];
          final c = updatedPoints[cIndex];
          if (ElbowPathUtils.segmentsCollinear(a, b, c)) {
            final candidatePoints = List<DrawPoint>.from(updatedPoints)
              ..removeAt(bIndex);
            final candidateSegments = List<ElbowFixedSegment>.from(
              updatedSegments,
            );
            candidateSegments[i] = segment.copyWith(
              index: index - 1,
              start: a,
              end: candidatePoints[index - 1],
            );
            final reindexed = _reindexFixedSegments(
              candidatePoints,
              candidateSegments,
            );
            if (reindexed.length == updatedSegments.length) {
              updatedPoints = candidatePoints;
              updatedSegments = reindexed;
              merged = true;
              break;
            }
          }
        }
      }

      // Merge with the next segment if it is collinear and not fixed.
      if (index + 1 < updatedPoints.length &&
          !fixedIndices.contains(index + 1)) {
        final aIndex = index - 1;
        final bIndex = index;
        final cIndex = index + 1;
        if (aIndex >= 0 && cIndex < updatedPoints.length) {
          final a = updatedPoints[aIndex];
          final b = updatedPoints[bIndex];
          final c = updatedPoints[cIndex];
          if (ElbowPathUtils.segmentsCollinear(a, b, c)) {
            final candidatePoints = List<DrawPoint>.from(updatedPoints)
              ..removeAt(bIndex);
            final candidateSegments = List<ElbowFixedSegment>.from(
              updatedSegments,
            );
            candidateSegments[i] = segment.copyWith(
              index: index,
              start: a,
              end: candidatePoints[index],
            );
            final reindexed = _reindexFixedSegments(
              candidatePoints,
              candidateSegments,
            );
            if (reindexed.length == updatedSegments.length) {
              updatedPoints = candidatePoints;
              updatedSegments = reindexed;
              merged = true;
              break;
            }
          }
        }
      }
    }
  }

  return _collapseEndpointBacktracks(
    points: List<DrawPoint>.unmodifiable(updatedPoints),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(updatedSegments),
  );
}

_FixedSegmentPathResult _removeAdjacentDuplicates({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  Set<DrawPoint> pinned = const {},
}) {
  if (points.length < 2 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
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
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final reindexed = _reindexFixedSegments(cleaned, fixedSegments);
  if (reindexed.length != fixedSegments.length) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  return _FixedSegmentPathResult(
    points: List<DrawPoint>.unmodifiable(cleaned),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
  );
}

_FixedSegmentPathResult _collapseFixedSegmentBacktracks({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.length < 4 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  var updatedPoints = List<DrawPoint>.from(points);
  var updatedSegments = List<ElbowFixedSegment>.from(fixedSegments);
  var changed = true;

  while (changed) {
    changed = false;
    for (final segment in updatedSegments) {
      final index = segment.index;
      if (index <= 0 || index + 2 >= updatedPoints.length) {
        continue;
      }
      final prev = updatedPoints[index - 1];
      final curr = updatedPoints[index];
      final next = updatedPoints[index + 1];
      if (!ElbowPathUtils.segmentsCollinear(prev, curr, next)) {
        continue;
      }
      final fixedHorizontal = ElbowPathUtils.segmentIsHorizontal(prev, curr);
      final fixedDelta = fixedHorizontal
          ? (curr.x - prev.x)
          : (curr.y - prev.y);
      final nextDelta = fixedHorizontal ? (next.x - curr.x) : (next.y - curr.y);
      if (fixedDelta.abs() <= ElbowConstants.dedupThreshold ||
          nextDelta.abs() <= ElbowConstants.dedupThreshold) {
        continue;
      }
      if (fixedDelta * nextDelta >= 0) {
        continue;
      }
      final after = updatedPoints[index + 2];

      final candidatePoints = List<DrawPoint>.from(updatedPoints)
        ..removeAt(index + 1);

      if (!ElbowPathUtils.pointsAligned(curr, after)) {
        final corner = fixedHorizontal
            ? DrawPoint(x: curr.x, y: after.y)
            : DrawPoint(x: after.x, y: curr.y);
        if (!ElbowPathUtils.pointsClose(corner, curr) &&
            !ElbowPathUtils.pointsClose(corner, after)) {
          candidatePoints.insert(index + 1, corner);
        }
      }

      final reindexed = _reindexFixedSegments(candidatePoints, updatedSegments);
      if (reindexed.length != updatedSegments.length) {
        continue;
      }

      updatedPoints = candidatePoints;
      updatedSegments = reindexed;
      changed = true;
      break;
    }
  }

  return _FixedSegmentPathResult(
    points: List<DrawPoint>.unmodifiable(updatedPoints),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(updatedSegments),
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

  var updatedPoints = points;
  var updatedSegments = fixedSegments;
  final pinned = _collectPinnedPoints(
    points: points,
    fixedSegments: fixedSegments,
  );

  final startCollapsed = _collapseEndpointBacktrack(
    points: updatedPoints,
    fixedSegments: updatedSegments,
    pinned: pinned,
    isStart: true,
  );
  updatedPoints = startCollapsed.points;
  updatedSegments = startCollapsed.fixedSegments;

  final endCollapsed = _collapseEndpointBacktrack(
    points: updatedPoints,
    fixedSegments: updatedSegments,
    pinned: pinned,
    isStart: false,
  );

  return endCollapsed;
}

_FixedSegmentPathResult _collapseEndpointBacktrack({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  required Set<DrawPoint> pinned,
  required bool isStart,
}) {
  if (points.length < 3) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final midIndex = isStart ? 1 : points.length - 2;
  if (pinned.contains(points[midIndex])) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final prevIndex = isStart ? 0 : points.length - 3;
  final nextIndex = isStart ? 2 : points.length - 1;
  final prev = points[prevIndex];
  final mid = points[midIndex];
  final next = points[nextIndex];
  if (!ElbowPathUtils.segmentsCollinear(prev, mid, next)) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final axis =
      ElbowPathUtils.axisAlignedForSegment(prev, mid) ??
      ElbowPathUtils.axisAlignedForSegment(mid, next);
  if (axis == null) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final delta1 = axis.isHorizontal ? mid.x - prev.x : mid.y - prev.y;
  final delta2 = axis.isHorizontal ? next.x - mid.x : next.y - mid.y;
  if (delta1.abs() <= ElbowConstants.dedupThreshold ||
      delta2.abs() <= ElbowConstants.dedupThreshold ||
      delta1 * delta2 >= 0) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final updated = List<DrawPoint>.from(points)..removeAt(midIndex);
  final reindexed = _reindexFixedSegments(updated, fixedSegments);
  if (reindexed.length != fixedSegments.length) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  return _FixedSegmentPathResult(
    points: List<DrawPoint>.unmodifiable(updated),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
  );
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

/// Simplifies a path while preserving fixed segment anchors.
_FixedSegmentPathResult _simplifyFixedSegmentPath({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.length < 2 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }
  final pinned = _collectPinnedPoints(
    points: points,
    fixedSegments: fixedSegments,
  );
  final simplified = ElbowPathUtils.simplifyPath(points, pinned: pinned);
  final reindexed = _reindexFixedSegments(simplified, fixedSegments);
  return _FixedSegmentPathResult(points: simplified, fixedSegments: reindexed);
}

/// Normalizes a path after fixed-segment release by merging collinear
/// neighbors.
_FixedSegmentPathResult _normalizeFixedSegmentReleasePath({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  Set<DrawPoint> extraPinned = const {},
}) {
  if (points.length < 2 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  // 1) Re-apply fixed axes before any simplification.
  final enforcedPoints = _applyFixedSegmentsToPoints(points, fixedSegments);
  // 2) Simplify while keeping fixed endpoints pinned.
  final prePinned = _collectPinnedPoints(
    points: enforcedPoints,
    fixedSegments: fixedSegments,
  );
  final preSimplified = ElbowPathUtils.simplifyPath(
    enforcedPoints,
    pinned: {...prePinned, ...extraPinned},
  );
  // 3) Reindex fixed segments when every segment still maps cleanly.
  final alignedFixed = _reindexFixedSegments(preSimplified, fixedSegments);
  final mergeFixedSegments = alignedFixed.length == fixedSegments.length
      ? alignedFixed
      : fixedSegments;
  final mergePinned = {
    ..._collectPinnedPoints(
      points: preSimplified,
      fixedSegments: mergeFixedSegments,
    ),
    ...extraPinned,
  };
  // 4) Merge any collinear neighbors introduced by the release.
  final merged = _mergeFixedSegmentsWithCollinearNeighbors(
    points: preSimplified,
    fixedSegments: mergeFixedSegments,
    pinned: mergePinned,
  );
  // 5) Simplify again and reindex to finalize the stable path.
  final pinned = _collectPinnedPoints(
    points: merged.points,
    fixedSegments: merged.fixedSegments,
  );
  final simplified = ElbowPathUtils.simplifyPath(
    merged.points,
    pinned: {...pinned, ...extraPinned},
  );
  final reindexed = _reindexFixedSegments(simplified, merged.fixedSegments);
  return _FixedSegmentPathResult(points: simplified, fixedSegments: reindexed);
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
    finalize: false,
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
