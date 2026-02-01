part of 'elbow_editing.dart';

/// Routing helpers used by elbow edit flows.

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

List<DrawPoint> _directElbowPath(
  DrawPoint start,
  DrawPoint end, {
  required bool preferHorizontal,
}) {
  if ((start.x - end.x).abs() <= ElbowConstants.dedupThreshold ||
      (start.y - end.y).abs() <= ElbowConstants.dedupThreshold) {
    return [start, end];
  }
  final mid = preferHorizontal
      ? DrawPoint(x: end.x, y: start.y)
      : DrawPoint(x: start.x, y: end.y);
  if (mid == start || mid == end) {
    return [start, end];
  }
  return [start, mid, end];
}

bool? _preferredHorizontalForRelease({
  required ElbowFixedSegment? previous,
  required ElbowFixedSegment? next,
}) {
  if (previous != null && next != null) {
    return null;
  }
  if (previous != null) {
    return ElbowGeometry.isHorizontal(previous.start, previous.end);
  }
  if (next != null) {
    return !ElbowGeometry.isHorizontal(next.start, next.end);
  }
  return null;
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
  if (startBinding != null || endBinding != null) {
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

  final preferHorizontal = _preferredHorizontalForRelease(
    previous: previousFixed,
    next: nextFixed,
  );
  if (preferHorizontal != null) {
    return _directElbowPath(
      startLocal,
      endLocal,
      preferHorizontal: preferHorizontal,
    );
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
  final routed = _routeReleasedRegion(
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
    previousFixed: previous,
    nextFixed: next,
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
