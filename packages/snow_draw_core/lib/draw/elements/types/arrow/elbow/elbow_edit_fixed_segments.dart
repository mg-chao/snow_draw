part of 'elbow_editing.dart';

/// Fixed-segment utilities for elbow editing.
///
/// These helpers sanitize, map, and reindex pinned segments to keep their
/// axis stable while the rest of the path updates.

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

bool? _fixedSegmentIsHorizontal(
  List<ElbowFixedSegment> fixedSegments,
  int index,
) {
  for (final segment in fixedSegments) {
    if (segment.index == index) {
      return _isHorizontal(segment.start, segment.end);
    }
  }
  return null;
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
    final aHorizontal = _isHorizontal(a[i].start, a[i].end);
    final bHorizontal = _isHorizontal(b[i].start, b[i].end);
    if (aHorizontal != bHorizontal) {
      return false;
    }
    final aAxis = aHorizontal
        ? (a[i].start.y + a[i].end.y) / 2
        : (a[i].start.x + a[i].end.x) / 2;
    final bAxis = bHorizontal
        ? (b[i].start.y + b[i].end.y) / 2
        : (b[i].start.x + b[i].end.x) / 2;
    if ((aAxis - bAxis).abs() > _dedupThreshold) {
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
    final axis = isHorizontal
        ? (segment.start.y + segment.end.y) / 2
        : (segment.start.x + segment.end.x) / 2;
    if (isHorizontal) {
      if ((start.y - axis).abs() <= _dedupThreshold &&
          (end.y - axis).abs() <= _dedupThreshold) {
        continue;
      }
      updated[index - 1] = start.copyWith(y: axis);
      updated[index] = end.copyWith(y: axis);
    } else {
      if ((start.x - axis).abs() <= _dedupThreshold &&
          (end.x - axis).abs() <= _dedupThreshold) {
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
    if (index == null || index <= 1 || index >= updated.length - 1) {
      continue;
    }
    usedIndices.add(index);
    final axis = isHorizontal
        ? (segment.start.y + segment.end.y) / 2
        : (segment.start.x + segment.end.x) / 2;
    final start = isHorizontal
        ? updated[index - 1].copyWith(y: axis)
        : updated[index - 1].copyWith(x: axis);
    final end = isHorizontal
        ? updated[index].copyWith(y: axis)
        : updated[index].copyWith(x: axis);
    mappedSegments.add(
      ElbowFixedSegment(
        index: index,
        start: start,
        end: end,
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

_FixedSegmentPathResult _mergeFixedSegmentsWithCollinearNeighbors({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.length < 3 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  var updatedPoints = List<DrawPoint>.from(points);
  var updatedSegments = List<ElbowFixedSegment>.from(fixedSegments);
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
