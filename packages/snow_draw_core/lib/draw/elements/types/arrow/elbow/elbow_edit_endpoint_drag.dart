part of 'elbow_editing.dart';

/// Endpoint-drag flow for elbow editing with fixed segments.

/// Aggregates endpoint-drag inputs and derived flags.
@immutable
final class _EndpointDragContext {
  const _EndpointDragContext({
    required this.element,
    required this.elementsById,
    required this.basePoints,
    required this.incomingPoints,
    required this.fixedSegments,
    required this.startBinding,
    required this.endBinding,
    required this.startBindingRemoved,
    required this.endBindingRemoved,
    required this.startArrowhead,
    required this.endArrowhead,
  });

  final ElementState element;
  final Map<String, ElementState> elementsById;
  final List<DrawPoint> basePoints;
  final List<DrawPoint> incomingPoints;
  final List<ElbowFixedSegment> fixedSegments;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final bool startBindingRemoved;
  final bool endBindingRemoved;
  final ArrowheadStyle startArrowhead;
  final ArrowheadStyle endArrowhead;

  bool get hasBindings => startBinding != null || endBinding != null;

  bool get hasBoundStart => _hasBindingTarget(startBinding, elementsById);

  bool get hasBoundEnd => _hasBindingTarget(endBinding, elementsById);

  bool get isFullyUnbound => startBinding == null && endBinding == null;
}

/// State container for endpoint-drag processing.
@immutable
final class _EndpointDragState {
  const _EndpointDragState({
    required this.points,
    required this.fixedSegments,
  });

  final List<DrawPoint> points;
  final List<ElbowFixedSegment> fixedSegments;

  _EndpointDragState copyWith({
    List<DrawPoint>? points,
    List<ElbowFixedSegment>? fixedSegments,
  }) => _EndpointDragState(
    points: points ?? this.points,
    fixedSegments: fixedSegments ?? this.fixedSegments,
  );
}

List<DrawPoint> _referencePointsForEndpointDrag({
  required List<DrawPoint> basePoints,
  required List<DrawPoint> incomingPoints,
}) =>
    _pointsEqualExceptEndpoints(basePoints, incomingPoints)
        ? basePoints
        : incomingPoints;

_FixedSegmentPathResult _maybeAdoptBaselineRoute({
  required List<DrawPoint> currentPoints,
  required List<ElbowFixedSegment> fixedSegments,
  required List<DrawPoint> baseline,
}) {
  final mapped = _applyFixedSegmentsToBaselineRoute(
    baseline: baseline,
    fixedSegments: fixedSegments,
  );
  if (mapped.fixedSegments.length == fixedSegments.length) {
    return _FixedSegmentPathResult(
      points: List<DrawPoint>.from(mapped.points),
      fixedSegments: mapped.fixedSegments,
    );
  }
  return _FixedSegmentPathResult(
    points: currentPoints,
    fixedSegments: fixedSegments,
  );
}

/// Step A: pick a stable reference path and apply endpoint overrides.
_EndpointDragState _buildEndpointDragState(_EndpointDragContext context) {
  final referencePoints = _referencePointsForEndpointDrag(
    basePoints: context.basePoints,
    incomingPoints: context.incomingPoints,
  );
  final updated = List<DrawPoint>.from(referencePoints);
  updated[0] = context.incomingPoints.first;
  updated[updated.length - 1] = context.incomingPoints.last;
  return _EndpointDragState(
    points: updated,
    fixedSegments: context.fixedSegments,
  );
}

/// Step B: adopt a bound-aware baseline route when available.
_EndpointDragState _adoptBaselineRouteIfNeeded({
  required _EndpointDragContext context,
  required _EndpointDragState state,
}) {
  if (!context.hasBindings) {
    return state;
  }
  final boundStart = context.hasBoundStart;
  final boundEnd = context.hasBoundEnd;
  if (!boundStart && !boundEnd) {
    return state;
  }
  if (context.fixedSegments.isNotEmpty && (boundStart != boundEnd)) {
    return state;
  }
  final baseline = _routeLocalPath(
    element: context.element,
    elementsById: context.elementsById,
    startLocal: state.points.first,
    endLocal: state.points.last,
    startArrowhead: context.startArrowhead,
    endArrowhead: context.endArrowhead,
    startBinding: context.startBinding,
    endBinding: context.endBinding,
  );
  final adopted = _maybeAdoptBaselineRoute(
    currentPoints: state.points,
    fixedSegments: state.fixedSegments,
    baseline: baseline,
  );
  return state.copyWith(
    points: List<DrawPoint>.from(adopted.points),
    fixedSegments: adopted.fixedSegments,
  );
}

_EndpointDragState _rerouteReleasedBindingSpan({
  required _EndpointDragContext context,
  required _EndpointDragState state,
}) {
  if (!context.startBindingRemoved && !context.endBindingRemoved) {
    return state;
  }
  if (state.points.length < 2) {
    return state;
  }

  var points = state.points;
  var fixedSegments = state.fixedSegments;

  if (context.startBindingRemoved) {
    final firstFixed = fixedSegments.isEmpty ? null : fixedSegments.first;
    final endIndex =
        firstFixed != null ? firstFixed.index - 1 : points.length - 1;
    if (endIndex > 0 && endIndex < points.length) {
      final startPoint = points.first;
      final endPoint = points[endIndex];
      final routed = _routeReleasedRegion(
        element: context.element,
        elementsById: context.elementsById,
        startLocal: startPoint,
        endLocal: endPoint,
        startArrowhead: context.startArrowhead,
        endArrowhead: endIndex == points.length - 1
            ? context.endArrowhead
            : ArrowheadStyle.none,
        previousFixed: null,
        nextFixed: firstFixed,
        startBinding: null,
        endBinding: endIndex == points.length - 1 ? context.endBinding : null,
      );
      final suffix = endIndex + 1 < points.length
          ? points.sublist(endIndex + 1)
          : const <DrawPoint>[];
      points = List<DrawPoint>.unmodifiable([...routed, ...suffix]);
      fixedSegments = _reindexFixedSegments(points, fixedSegments);
    }
  }

  if (context.endBindingRemoved) {
    final lastFixed = fixedSegments.isEmpty ? null : fixedSegments.last;
    final startIndex = lastFixed?.index ?? 0;
    if (startIndex >= 0 && startIndex < points.length - 1) {
      final startPoint = points[startIndex];
      final endPoint = points.last;
      final routed = _routeReleasedRegion(
        element: context.element,
        elementsById: context.elementsById,
        startLocal: startPoint,
        endLocal: endPoint,
        startArrowhead: startIndex == 0
            ? context.startArrowhead
            : ArrowheadStyle.none,
        endArrowhead: context.endArrowhead,
        previousFixed: lastFixed,
        nextFixed: null,
        startBinding: startIndex == 0 ? context.startBinding : null,
        endBinding: null,
      );
      final prefix = startIndex > 0
          ? points.sublist(0, startIndex)
          : const <DrawPoint>[];
      points = List<DrawPoint>.unmodifiable([...prefix, ...routed]);
      fixedSegments = _reindexFixedSegments(points, fixedSegments);
    }
  }

  return state.copyWith(points: points, fixedSegments: fixedSegments);
}

/// Step C/F: enforce fixed segment axes after any endpoint movement.
_EndpointDragState _applyFixedSegmentAxes(_EndpointDragState state) {
  final updated = _applyFixedSegmentsToPoints(
    state.points,
    state.fixedSegments,
  );
  return state.copyWith(points: List<DrawPoint>.from(updated));
}

/// Step D: re-route for diagonal drift when fully unbound.
_EndpointDragState _rerouteForDiagonalDrift({
  required _EndpointDragContext context,
  required _EndpointDragState state,
}) {
  if (!context.isFullyUnbound || !_hasDiagonalSegments(state.points)) {
    return state;
  }
  final baseline = _routeLocalPath(
    element: context.element,
    elementsById: context.elementsById,
    startLocal: state.points.first,
    endLocal: state.points.last,
    startArrowhead: context.startArrowhead,
    endArrowhead: context.endArrowhead,
  );
  final adopted = _maybeAdoptBaselineRoute(
    currentPoints: state.points,
    fixedSegments: state.fixedSegments,
    baseline: baseline,
  );
  return state.copyWith(
    points: List<DrawPoint>.from(adopted.points),
    fixedSegments: adopted.fixedSegments,
  );
}

/// Step E: snap unbound endpoint neighbors to stay orthogonal.
_EndpointDragState _snapUnboundNeighbors({
  required _EndpointDragContext context,
  required _EndpointDragState state,
}) {
  var points = state.points;
  if (!context.hasBoundStart) {
    points = _snapUnboundStartNeighbor(
      points: points,
      fixedSegments: state.fixedSegments,
    );
  }
  if (!context.hasBoundEnd) {
    points = _snapUnboundEndNeighbor(
      points: points,
      fixedSegments: state.fixedSegments,
    );
  }
  return state.copyWith(points: points);
}

/// Step G: merge a trailing collinear segment for unbound paths.
_EndpointDragState _mergeTailIfUnbound({
  required _EndpointDragContext context,
  required _EndpointDragState state,
}) {
  if (!context.isFullyUnbound) {
    return state;
  }
  final merged = _mergeFixedSegmentWithEndCollinear(
    points: state.points,
    fixedSegments: state.fixedSegments,
  );
  if (merged.fixedSegments.length != state.fixedSegments.length) {
    return state;
  }
  return state.copyWith(
    points: merged.points,
    fixedSegments: merged.fixedSegments,
  );
}

_FixedSegmentPathResult _collapseBindingRemovedEndStub({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.length < 4 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  final lastIndex = points.length - 1;
  final midIndex = lastIndex - 1;
  final prevIndex = lastIndex - 2;
  final prevSegmentIndex = prevIndex;
  final midSegmentIndex = midIndex;
  final lastSegmentIndex = lastIndex;

  final prevFixed = _fixedSegmentIsHorizontal(
    fixedSegments,
    prevSegmentIndex,
  );
  if (prevFixed == null) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }
  if (_fixedSegmentIsHorizontal(fixedSegments, midSegmentIndex) != null ||
      _fixedSegmentIsHorizontal(fixedSegments, lastSegmentIndex) != null) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  final prevHorizontal = ElbowGeometry.isHorizontal(
    points[prevIndex - 1],
    points[prevIndex],
  );
  final midHorizontal = ElbowGeometry.isHorizontal(
    points[prevIndex],
    points[midIndex],
  );
  final lastHorizontal = ElbowGeometry.isHorizontal(
    points[midIndex],
    points[lastIndex],
  );
  if (prevFixed != prevHorizontal) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  if (prevHorizontal == midHorizontal && prevHorizontal != lastHorizontal) {
    final updated = List<DrawPoint>.from(points)..removeAt(prevIndex);
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

  if (prevHorizontal != midHorizontal && midHorizontal == lastHorizontal) {
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

  if (prevHorizontal != lastHorizontal || prevHorizontal == midHorizontal) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  final updated = List<DrawPoint>.from(points);
  final anchor = updated[prevIndex];
  final endPoint = updated[lastIndex];
  final moved = prevHorizontal
      ? anchor.copyWith(x: endPoint.x)
      : anchor.copyWith(y: endPoint.y);
  if (moved == anchor) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }
  if (ElbowGeometry.manhattanDistance(moved, endPoint) <=
      ElbowConstants.dedupThreshold) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }
  updated[prevIndex] = moved;
  updated.removeAt(midIndex);

  final reindexed = _reindexFixedSegments(updated, fixedSegments);
  if (reindexed.length != fixedSegments.length) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  return _FixedSegmentPathResult(
    points: List<DrawPoint>.unmodifiable(updated),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
  );
}

_FixedSegmentPathResult _collapseBindingRemovedStartStub({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.length < 4 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  const startIndex = 0;
  const midIndex = 1;
  const nextIndex = 2;
  const outerSegmentIndex = 3;
  const firstSegmentIndex = 1;
  const middleSegmentIndex = 2;

  final outerFixed = _fixedSegmentIsHorizontal(
    fixedSegments,
    outerSegmentIndex,
  );
  if (outerFixed == null) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }
  if (_fixedSegmentIsHorizontal(fixedSegments, firstSegmentIndex) != null ||
      _fixedSegmentIsHorizontal(fixedSegments, middleSegmentIndex) != null) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  final firstHorizontal = ElbowGeometry.isHorizontal(
    points[startIndex],
    points[midIndex],
  );
  final middleHorizontal = ElbowGeometry.isHorizontal(
    points[midIndex],
    points[nextIndex],
  );
  final outerHorizontal = ElbowGeometry.isHorizontal(
    points[nextIndex],
    points[nextIndex + 1],
  );
  if (outerFixed != outerHorizontal) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  if (middleHorizontal == outerHorizontal &&
      firstHorizontal != middleHorizontal) {
    final updated = List<DrawPoint>.from(points)..removeAt(nextIndex);
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

  if (firstHorizontal == middleHorizontal &&
      firstHorizontal != outerHorizontal) {
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

  if (firstHorizontal != outerHorizontal ||
      firstHorizontal == middleHorizontal) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  final updated = List<DrawPoint>.from(points);
  final startPoint = updated[startIndex];
  final anchor = updated[nextIndex];
  final moved = outerHorizontal
      ? anchor.copyWith(x: startPoint.x)
      : anchor.copyWith(y: startPoint.y);
  if (moved == anchor) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }
  if (ElbowGeometry.manhattanDistance(startPoint, moved) <=
      ElbowConstants.dedupThreshold) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }
  updated[nextIndex] = moved;
  updated.removeAt(midIndex);

  final reindexed = _reindexFixedSegments(updated, fixedSegments);
  if (reindexed.length != fixedSegments.length) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }

  return _FixedSegmentPathResult(
    points: List<DrawPoint>.unmodifiable(updated),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
  );
}

_EndpointDragState _collapseBindingRemovedStubs({
  required _EndpointDragContext context,
  required _EndpointDragState state,
}) {
  var points = state.points;
  var fixedSegments = state.fixedSegments;

  if (context.endBindingRemoved) {
    final collapsed = _collapseBindingRemovedEndStub(
      points: points,
      fixedSegments: fixedSegments,
    );
    points = collapsed.points;
    fixedSegments = collapsed.fixedSegments;
  }

  if (context.startBindingRemoved) {
    final collapsed = _collapseBindingRemovedStartStub(
      points: points,
      fixedSegments: fixedSegments,
    );
    points = collapsed.points;
    fixedSegments = collapsed.fixedSegments;
  }

  return state.copyWith(points: points, fixedSegments: fixedSegments);
}

List<DrawPoint> _snapUnboundStartNeighbor({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.length <= 1) {
    return points;
  }
  final updated = List<DrawPoint>.from(points);
  final start = updated.first;
  final neighbor = updated[1];
  final adjacentFixed = _fixedSegmentIsHorizontal(fixedSegments, 2);
  if (adjacentFixed != null) {
    updated[1] = adjacentFixed
        ? neighbor.copyWith(x: start.x)
        : neighbor.copyWith(y: start.y);
    return updated;
  }
  final dx = (neighbor.x - start.x).abs();
  final dy = (neighbor.y - start.y).abs();
  updated[1] = dx <= dy
      ? neighbor.copyWith(x: start.x)
      : neighbor.copyWith(y: start.y);
  return updated;
}

List<DrawPoint> _snapUnboundEndNeighbor({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.length <= 1) {
    return points;
  }
  final updated = List<DrawPoint>.from(points);
  final lastIndex = updated.length - 1;
  final neighbor = updated[lastIndex - 1];
  final endPoint = updated[lastIndex];
  final adjacentFixed = _fixedSegmentIsHorizontal(fixedSegments, lastIndex - 1);
  if (adjacentFixed != null) {
    updated[lastIndex - 1] = adjacentFixed
        ? neighbor.copyWith(x: endPoint.x)
        : neighbor.copyWith(y: endPoint.y);
    return updated;
  }
  final dx = (neighbor.x - endPoint.x).abs();
  final dy = (neighbor.y - endPoint.y).abs();
  updated[lastIndex - 1] = dx <= dy
      ? neighbor.copyWith(x: endPoint.x)
      : neighbor.copyWith(y: endPoint.y);
  return updated;
}

bool _hasBindingTarget(
  ArrowBinding? binding,
  Map<String, ElementState> elementsById,
) => binding != null && elementsById.containsKey(binding.elementId);

_FixedSegmentPathResult _applyEndpointDragWithFixedSegments({
  required _EndpointDragContext context,
}) {
  if (context.basePoints.length < 2) {
    return _FixedSegmentPathResult(
      points: context.incomingPoints,
      fixedSegments: context.fixedSegments,
    );
  }

  // Step A: apply endpoint overrides to a stable reference path.
  var state = _buildEndpointDragState(context);
  // Step B: adopt a bound-aware baseline route when possible.
  state = _adoptBaselineRouteIfNeeded(context: context, state: state);
  // Step C: reroute spans freed by binding removal.
  state = _rerouteReleasedBindingSpan(context: context, state: state);
  // Step D: enforce fixed segment axes after endpoint changes.
  state = _applyFixedSegmentAxes(state);
  // Step E: for unbound arrows, re-route if a diagonal drift appears.
  state = _rerouteForDiagonalDrift(context: context, state: state);
  // Step F: snap neighbors to maintain orthogonality for unbound endpoints.
  state = _snapUnboundNeighbors(context: context, state: state);
  // Step G: re-apply fixed segments after neighbor snapping.
  state = _applyFixedSegmentAxes(state);
  // Step H: merge collinear tail segments for fully unbound paths.
  state = _mergeTailIfUnbound(context: context, state: state);

  var synced = _syncFixedSegmentsToPoints(
    state.points,
    state.fixedSegments,
  );
  state = state.copyWith(fixedSegments: synced);
  // Step I: drop binding stubs when a binding was removed.
  state = _collapseBindingRemovedStubs(context: context, state: state);
  synced = _syncFixedSegmentsToPoints(state.points, state.fixedSegments);
  if (context.isFullyUnbound) {
    return _FixedSegmentPathResult(points: state.points, fixedSegments: synced);
  }

  // Step J: enforce perpendicularity for bound endpoints in world space.
  return _ensurePerpendicularBindings(
    element: context.element,
    elementsById: context.elementsById,
    points: state.points,
    fixedSegments: synced,
    startBinding: context.startBinding,
    endBinding: context.endBinding,
    startArrowhead: context.startArrowhead,
    endArrowhead: context.endArrowhead,
  );
}
