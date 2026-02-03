part of 'elbow_editing.dart';

/// Fixed-segment utilities for elbow editing.
///
/// These helpers sanitize, map, and reindex pinned segments to keep their
/// axis stable while the rest of the path updates.

bool _isInteriorSegmentIndex(int index, int pointCount) =>
    index > 1 && index < pointCount - 1;

double _segmentAxisValue(
  DrawPoint start,
  DrawPoint end, {
  required bool isHorizontal,
}) => isHorizontal ? (start.y + end.y) / 2 : (start.x + end.x) / 2;

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
  final preferredIndex = segment.index;
  final fixedHorizontal = ElbowGeometry.isHorizontal(
    segment.start,
    segment.end,
  );
  final fixedAxis = _segmentAxisValue(
    segment.start,
    segment.end,
    isHorizontal: fixedHorizontal,
  );
  final maxIndex = points.length - 1;
  const minIndex = 2;
  int? bestIndex;
  var bestAxisDelta = double.infinity;
  var bestIndexDelta = double.infinity;
  for (var i = minIndex; i < maxIndex; i++) {
    if (ElbowGeometry.isHorizontal(points[i - 1], points[i]) !=
        fixedHorizontal) {
      continue;
    }
    final candidateAxis = _segmentAxisValue(
      points[i - 1],
      points[i],
      isHorizontal: fixedHorizontal,
    );
    final axisDelta = (candidateAxis - fixedAxis).abs();
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
      return ElbowGeometry.isHorizontal(segment.start, segment.end);
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
    final aHorizontal = ElbowGeometry.isHorizontal(a[i].start, a[i].end);
    final bHorizontal = ElbowGeometry.isHorizontal(b[i].start, b[i].end);
    if (aHorizontal != bHorizontal) {
      return false;
    }
    final aAxis = aHorizontal
        ? (a[i].start.y + a[i].end.y) / 2
        : (a[i].start.x + a[i].end.x) / 2;
    final bAxis = bHorizontal
        ? (b[i].start.y + b[i].end.y) / 2
        : (b[i].start.x + b[i].end.x) / 2;
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
    final isHorizontal = ElbowGeometry.isHorizontal(segment.start, segment.end);
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

int? _resolveBaselineSegmentIndex({
  required List<DrawPoint> baseline,
  required bool isHorizontal,
  required int preferredIndex,
  required double axis,
  double axisTolerance = ElbowConstants.dedupThreshold,
  Set<int> usedIndices = const {},
}) {
  if (baseline.length < 2) {
    return null;
  }
  final maxIndex = baseline.length - 1;
  const minIndex = 2;
  int? bestIndex;
  var bestAxisDelta = double.infinity;
  var bestIndexDelta = double.infinity;
  for (var i = minIndex; i < maxIndex; i++) {
    if (usedIndices.contains(i)) {
      continue;
    }
    if (ElbowGeometry.isHorizontal(baseline[i - 1], baseline[i]) !=
        isHorizontal) {
      continue;
    }
    final candidateAxis = _segmentAxisValue(
      baseline[i - 1],
      baseline[i],
      isHorizontal: isHorizontal,
    );
    final axisDelta = (candidateAxis - axis).abs();
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

_FixedSegmentPathResult _applyFixedSegmentsToBaselineRoute({
  required List<DrawPoint> baseline,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (fixedSegments.isEmpty || baseline.length < 2) {
    return _FixedSegmentPathResult(
      points: baseline,
      fixedSegments: fixedSegments,
    );
  }

  final updated = List<DrawPoint>.from(baseline);
  final usedIndices = <int>{};
  final mappedSegments = <ElbowFixedSegment>[];

  for (final segment in fixedSegments) {
    final isHorizontal = ElbowGeometry.isHorizontal(segment.start, segment.end);
    final axis = _segmentAxisValue(
      segment.start,
      segment.end,
      isHorizontal: isHorizontal,
    );
    final index = _resolveBaselineSegmentIndex(
      baseline: updated,
      isHorizontal: isHorizontal,
      preferredIndex: segment.index,
      axis: axis,
      usedIndices: usedIndices,
    );
    if (index == null || index <= 1 || index >= updated.length - 1) {
      continue;
    }
    usedIndices.add(index);
    final start = isHorizontal
        ? updated[index - 1].copyWith(y: axis)
        : updated[index - 1].copyWith(x: axis);
    final end = isHorizontal
        ? updated[index].copyWith(y: axis)
        : updated[index].copyWith(x: axis);
    mappedSegments.add(ElbowFixedSegment(index: index, start: start, end: end));
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
  if (!_segmentsCollinear(a, b, c)) {
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
}) {
  if (points.length < 3 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final collapsed = allowDirectionFlip
      ? _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments)
      : _collapseFixedSegmentBacktracks(
          points: points,
          fixedSegments: fixedSegments,
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
          if (_segmentsCollinear(a, b, c)) {
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
          if (_segmentsCollinear(a, b, c)) {
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

  return _FixedSegmentPathResult(
    points: List<DrawPoint>.unmodifiable(updatedPoints),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(updatedSegments),
  );
}

bool _pointsClose(DrawPoint a, DrawPoint b) =>
    (a.x - b.x).abs() <= ElbowConstants.dedupThreshold &&
    (a.y - b.y).abs() <= ElbowConstants.dedupThreshold;

bool _pointsAligned(DrawPoint a, DrawPoint b) =>
    (a.x - b.x).abs() <= ElbowConstants.dedupThreshold ||
    (a.y - b.y).abs() <= ElbowConstants.dedupThreshold;

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
      if (!_segmentsCollinear(prev, curr, next)) {
        continue;
      }
      final fixedHorizontal = ElbowGeometry.isHorizontal(prev, curr);
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

      if (!_pointsAligned(curr, after)) {
        final corner = fixedHorizontal
            ? DrawPoint(x: curr.x, y: after.y)
            : DrawPoint(x: after.x, y: curr.y);
        if (!_pointsClose(corner, curr) && !_pointsClose(corner, after)) {
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
  final simplified = _simplifyPath(points, pinned: pinned);
  final reindexed = _reindexFixedSegments(simplified, fixedSegments);
  return _FixedSegmentPathResult(points: simplified, fixedSegments: reindexed);
}

/// Normalizes a path after fixed-segment release by merging collinear
/// neighbors.
_FixedSegmentPathResult _normalizeFixedSegmentReleasePath({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
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
  final preSimplified = _simplifyPath(enforcedPoints, pinned: prePinned);
  // 3) Reindex fixed segments when every segment still maps cleanly.
  final alignedFixed = _reindexFixedSegments(preSimplified, fixedSegments);
  final mergeFixedSegments = alignedFixed.length == fixedSegments.length
      ? alignedFixed
      : fixedSegments;
  // 4) Merge any collinear neighbors introduced by the release.
  final merged = _mergeFixedSegmentsWithCollinearNeighbors(
    points: preSimplified,
    fixedSegments: mergeFixedSegments,
  );
  // 5) Simplify again and reindex to finalize the stable path.
  final pinned = _collectPinnedPoints(
    points: merged.points,
    fixedSegments: merged.fixedSegments,
  );
  final simplified = _simplifyPath(merged.points, pinned: pinned);
  final reindexed = _reindexFixedSegments(simplified, merged.fixedSegments);
  return _FixedSegmentPathResult(points: simplified, fixedSegments: reindexed);
}
