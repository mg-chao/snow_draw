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
    required this.startWasBound,
    required this.endWasBound,
    required this.startActive,
    required this.endActive,
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
  final bool startWasBound;
  final bool endWasBound;
  final bool startActive;
  final bool endActive;
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
  const _EndpointDragState({required this.points, required this.fixedSegments});

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
}) => _pointsEqualExceptEndpoints(basePoints, incomingPoints)
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

_FixedSegmentPathResult? _mapBaselineWithActiveSegment({
  required List<DrawPoint> baseline,
  required List<ElbowFixedSegment> fixedSegments,
  ElbowFixedSegment? activeSegment,
}) =>
    _mapFixedSegmentsToBaseline(
      baseline: baseline,
      fixedSegments: fixedSegments,
      activeSegment: activeSegment,
      enforceAxisOnPoints: true,
      requireAll: true,
    );

List<DrawPoint>? _buildFallbackPointsForActiveFixed({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowFixedSegment fixedSegment,
  required ElbowHeading requiredHeading,
  bool startBound = false,
}) {
  if (startBound) {
    final reversed = _buildFallbackPointsForActiveFixed(
      start: end,
      end: start,
      fixedSegment: fixedSegment,
      requiredHeading: requiredHeading.opposite,
    );
    if (reversed == null) {
      return null;
    }
    return reversed.reversed.toList(growable: false);
  }
  final fixedHorizontal = ElbowPathUtils.segmentIsHorizontal(
    fixedSegment.start,
    fixedSegment.end,
  );
  final axis = ElbowPathUtils.axisValue(
    fixedSegment.start,
    fixedSegment.end,
    axis: fixedHorizontal ? ElbowAxis.horizontal : ElbowAxis.vertical,
  );
  const padding = ElbowConstants.directionFixPadding;

  List<DrawPoint> points;
  if (fixedHorizontal) {
    var midX = (start.x + end.x) / 2;
    if (requiredHeading == ElbowHeading.right && midX >= end.x) {
      midX = end.x - padding;
    } else if (requiredHeading == ElbowHeading.left && midX <= end.x) {
      midX = end.x + padding;
    }
    final p1 = DrawPoint(x: start.x, y: axis);
    final p2 = DrawPoint(x: midX, y: axis);
    final p3 = DrawPoint(x: midX, y: end.y);
    points = [start, p1, p2, p3, end];
  } else {
    var midY = (start.y + end.y) / 2;
    if (requiredHeading == ElbowHeading.down && midY >= end.y) {
      midY = end.y - padding;
    } else if (requiredHeading == ElbowHeading.up && midY <= end.y) {
      midY = end.y + padding;
    }
    final p1 = DrawPoint(x: axis, y: start.y);
    final p2 = DrawPoint(x: axis, y: midY);
    final p3 = DrawPoint(x: end.x, y: midY);
    points = [start, p1, p2, p3, end];
  }

  final simplified = ElbowPathUtils.simplifyPath(points);
  if (simplified.length < 2) {
    return null;
  }
  return List<DrawPoint>.unmodifiable(simplified);
}

_FixedSegmentPathResult? _buildFallbackPathForActiveFixed({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowFixedSegment fixedSegment,
  required ElbowHeading requiredHeading,
  bool startBound = false,
}) {
  final points = _buildFallbackPointsForActiveFixed(
    start: start,
    end: end,
    fixedSegment: fixedSegment,
    requiredHeading: requiredHeading,
    startBound: startBound,
  );
  if (points == null) {
    return null;
  }
  final reindexed = _reindexFixedSegments(points, [fixedSegment]);
  if (reindexed.isEmpty) {
    return null;
  }
  return _FixedSegmentPathResult(
    points: points,
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
  );
}

_FixedSegmentPathResult? _buildFallbackPathForActiveSpan({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  required ElbowFixedSegment activeSegment,
  required ElbowHeading requiredHeading,
  required bool startBound,
}) {
  if (points.length < 2 || fixedSegments.isEmpty) {
    return null;
  }

  if (startBound) {
    final anchorIndex = activeSegment.index;
    if (anchorIndex <= 0 || anchorIndex >= points.length) {
      return null;
    }
    final anchor = points[anchorIndex];
    final subPath = _buildFallbackPointsForActiveFixed(
      start: points.first,
      end: anchor,
      fixedSegment: activeSegment,
      requiredHeading: requiredHeading,
      startBound: true,
    );
    if (subPath == null) {
      return null;
    }
    final suffix = anchorIndex + 1 < points.length
        ? points.sublist(anchorIndex + 1)
        : const <DrawPoint>[];
    final stitched = <DrawPoint>[...subPath, ...suffix];
    final reindexed = _reindexFixedSegments(stitched, fixedSegments);
    if (reindexed.length != fixedSegments.length) {
      return null;
    }
    final simplified = _simplifyFixedSegmentPath(
      points: stitched,
      fixedSegments: reindexed,
    );
    if (simplified.fixedSegments.length == fixedSegments.length) {
      return _FixedSegmentPathResult(
        points: simplified.points,
        fixedSegments: simplified.fixedSegments,
      );
    }
    return _FixedSegmentPathResult(
      points: List<DrawPoint>.unmodifiable(stitched),
      fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
    );
  }

  final anchorIndex = activeSegment.index - 1;
  if (anchorIndex < 0 || anchorIndex >= points.length) {
    return null;
  }
  final anchor = points[anchorIndex];
  final subPath = _buildFallbackPointsForActiveFixed(
    start: anchor,
    end: points.last,
    fixedSegment: activeSegment,
    requiredHeading: requiredHeading,
  );
  if (subPath == null) {
    return null;
  }
  final prefix = anchorIndex > 0
      ? points.sublist(0, anchorIndex)
      : const <DrawPoint>[];
  final stitched = <DrawPoint>[...prefix, ...subPath];
  final reindexed = _reindexFixedSegments(stitched, fixedSegments);
  if (reindexed.length != fixedSegments.length) {
    return null;
  }
  final simplified = _simplifyFixedSegmentPath(
    points: stitched,
    fixedSegments: reindexed,
  );
  if (simplified.fixedSegments.length == fixedSegments.length) {
    return _FixedSegmentPathResult(
      points: simplified.points,
      fixedSegments: simplified.fixedSegments,
    );
  }
  return _FixedSegmentPathResult(
    points: List<DrawPoint>.unmodifiable(stitched),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
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
({_EndpointDragState state, bool adoptedBaseline}) _adoptBaselineRouteIfNeeded({
  required _EndpointDragContext context,
  required _EndpointDragState state,
}) {
  if (!context.hasBindings) {
    return (state: state, adoptedBaseline: false);
  }
  final boundStart = context.hasBoundStart;
  final boundEnd = context.hasBoundEnd;
  if (!boundStart && !boundEnd) {
    return (state: state, adoptedBaseline: false);
  }
  final startActiveBound =
      boundStart &&
      context.startActive &&
      context.startWasBound &&
      !context.startBindingRemoved;
  final endActiveBound =
      boundEnd &&
      context.endActive &&
      context.endWasBound &&
      !context.endBindingRemoved;
  final forceBaseline = startActiveBound || endActiveBound;
  final activeStart = startActiveBound && !endActiveBound;
  final activeEnd = endActiveBound && !startActiveBound;
  final activeSegment =
      (forceBaseline &&
          state.fixedSegments.isNotEmpty &&
          (activeStart || activeEnd))
      ? (activeStart ? state.fixedSegments.first : state.fixedSegments.last)
      : null;
  final activeBinding = activeSegment == null
      ? null
      : (activeStart ? context.startBinding : context.endBinding);
  final activePoint = activeSegment == null
      ? null
      : (activeStart ? state.points.first : state.points.last);
  final boundHeading = (activeBinding == null || activePoint == null)
      ? null
      : _resolveBoundHeading(
          binding: activeBinding,
          elementsById: context.elementsById,
          point: activePoint,
        );
  final requiredHeading = activeSegment == null
      ? null
      : (activeStart ? boundHeading : boundHeading?.opposite);
  if (forceBaseline && state.fixedSegments.length == 1) {
    if (activeSegment != null && requiredHeading != null) {
      final fallback = _buildFallbackPathForActiveFixed(
        start: state.points.first,
        end: state.points.last,
        fixedSegment: activeSegment,
        requiredHeading: requiredHeading,
        startBound: activeStart,
      );
      if (fallback != null) {
        return (
          state: state.copyWith(
            points: List<DrawPoint>.from(fallback.points),
            fixedSegments: fallback.fixedSegments,
          ),
          adoptedBaseline: true,
        );
      }
    }
  }
  if (context.fixedSegments.isNotEmpty && (boundStart != boundEnd)) {
    if (!forceBaseline) {
      return (state: state, adoptedBaseline: false);
    }
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
  final mapped = _mapBaselineWithActiveSegment(
    baseline: baseline,
    fixedSegments: state.fixedSegments,
    activeSegment: activeSegment,
  );
  if (mapped == null) {
    if (forceBaseline && activeSegment != null && requiredHeading != null) {
      final fallback = _buildFallbackPathForActiveSpan(
        points: state.points,
        fixedSegments: state.fixedSegments,
        activeSegment: activeSegment,
        requiredHeading: requiredHeading,
        startBound: activeStart,
      );
      if (fallback != null) {
        return (
          state: state.copyWith(
            points: List<DrawPoint>.from(fallback.points),
            fixedSegments: fallback.fixedSegments,
          ),
          adoptedBaseline: true,
        );
      }
    }
    return (state: state, adoptedBaseline: false);
  }
  var adoptedPoints = List<DrawPoint>.from(mapped.points);
  var adoptedFixed = mapped.fixedSegments;
  if (forceBaseline) {
    final normalized = _normalizeFixedSegmentReleasePath(
      points: adoptedPoints,
      fixedSegments: adoptedFixed,
    );
    adoptedPoints = List<DrawPoint>.from(normalized.points);
    adoptedFixed = normalized.fixedSegments;
  }
  return (
    state: state.copyWith(points: adoptedPoints, fixedSegments: adoptedFixed),
    adoptedBaseline: true,
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
    final endIndex = firstFixed != null
        ? firstFixed.index - 1
        : points.length - 1;
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
  if (!context.isFullyUnbound ||
      !ElbowPathUtils.hasDiagonalSegments(state.points)) {
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
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final lastIndex = points.length - 1;
  final midIndex = lastIndex - 1;
  final prevIndex = lastIndex - 2;
  final prevSegmentIndex = prevIndex;
  final midSegmentIndex = midIndex;
  final lastSegmentIndex = lastIndex;

  final prevFixed = _fixedSegmentIsHorizontal(fixedSegments, prevSegmentIndex);
  if (prevFixed == null) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }
  if (_fixedSegmentIsHorizontal(fixedSegments, midSegmentIndex) != null ||
      _fixedSegmentIsHorizontal(fixedSegments, lastSegmentIndex) != null) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final prevHorizontal = ElbowPathUtils.segmentIsHorizontal(
    points[prevIndex - 1],
    points[prevIndex],
  );
  final midHorizontal = ElbowPathUtils.segmentIsHorizontal(
    points[prevIndex],
    points[midIndex],
  );
  final lastHorizontal = ElbowPathUtils.segmentIsHorizontal(
    points[midIndex],
    points[lastIndex],
  );
  if (prevFixed != prevHorizontal) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
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
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final updated = List<DrawPoint>.from(points);
  final anchor = updated[prevIndex];
  final endPoint = updated[lastIndex];
  final moved = prevHorizontal
      ? anchor.copyWith(x: endPoint.x)
      : anchor.copyWith(y: endPoint.y);
  if (moved == anchor) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }
  if (ElbowGeometry.manhattanDistance(moved, endPoint) <=
      ElbowConstants.dedupThreshold) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }
  updated[prevIndex] = moved;
  updated.removeAt(midIndex);

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

_FixedSegmentPathResult _collapseBindingRemovedStartStub({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  if (points.length < 4 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
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
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }
  if (_fixedSegmentIsHorizontal(fixedSegments, firstSegmentIndex) != null ||
      _fixedSegmentIsHorizontal(fixedSegments, middleSegmentIndex) != null) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final firstHorizontal = ElbowPathUtils.segmentIsHorizontal(
    points[startIndex],
    points[midIndex],
  );
  final middleHorizontal = ElbowPathUtils.segmentIsHorizontal(
    points[midIndex],
    points[nextIndex],
  );
  final outerHorizontal = ElbowPathUtils.segmentIsHorizontal(
    points[nextIndex],
    points[nextIndex + 1],
  );
  if (outerFixed != outerHorizontal) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
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
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final updated = List<DrawPoint>.from(points);
  final startPoint = updated[startIndex];
  final anchor = updated[nextIndex];
  final moved = outerHorizontal
      ? anchor.copyWith(x: startPoint.x)
      : anchor.copyWith(y: startPoint.y);
  if (moved == anchor) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }
  if (ElbowGeometry.manhattanDistance(startPoint, moved) <=
      ElbowConstants.dedupThreshold) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }
  updated[nextIndex] = moved;
  updated.removeAt(midIndex);

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
}) => _snapUnboundNeighbor(
  points: points,
  fixedSegments: fixedSegments,
  isStart: true,
);

List<DrawPoint> _snapUnboundEndNeighbor({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) => _snapUnboundNeighbor(
  points: points,
  fixedSegments: fixedSegments,
  isStart: false,
);

List<DrawPoint> _snapUnboundNeighbor({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  required bool isStart,
}) {
  if (points.length <= 1) {
    return points;
  }
  final updated = List<DrawPoint>.from(points);
  final lastIndex = updated.length - 1;
  final endpointIndex = isStart ? 0 : lastIndex;
  final neighborIndex = isStart ? 1 : lastIndex - 1;
  final endpoint = updated[endpointIndex];
  final neighbor = updated[neighborIndex];
  final adjacentFixedIndex = isStart ? 2 : neighborIndex;
  final adjacentFixed = _fixedSegmentIsHorizontal(
    fixedSegments,
    adjacentFixedIndex,
  );
  if (adjacentFixed != null) {
    updated[neighborIndex] = adjacentFixed
        ? neighbor.copyWith(x: endpoint.x)
        : neighbor.copyWith(y: endpoint.y);
    return updated;
  }
  final dx = (neighbor.x - endpoint.x).abs();
  final dy = (neighbor.y - endpoint.y).abs();
  updated[neighborIndex] = dx <= dy
      ? neighbor.copyWith(x: endpoint.x)
      : neighbor.copyWith(y: endpoint.y);
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
  final baseline = _adoptBaselineRouteIfNeeded(context: context, state: state);
  state = baseline.state;
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

  var synced = _syncFixedSegmentsToPoints(state.points, state.fixedSegments);
  state = state.copyWith(fixedSegments: synced);
  // Step I: drop binding stubs when a binding was removed.
  state = _collapseBindingRemovedStubs(context: context, state: state);
  synced = _syncFixedSegmentsToPoints(state.points, state.fixedSegments);
  if (context.isFullyUnbound) {
    return _FixedSegmentPathResult(points: state.points, fixedSegments: synced);
  }

  // Step J: enforce perpendicularity for bound endpoints in world space.
  final perpendicular = _ensurePerpendicularBindings(
    element: context.element,
    elementsById: context.elementsById,
    points: state.points,
    fixedSegments: synced,
    startBinding: context.startBinding,
    endBinding: context.endBinding,
    startArrowhead: context.startArrowhead,
    endArrowhead: context.endArrowhead,
  );
  return _alignFixedSegmentsToBoundLanes(
    element: context.element,
    elementsById: context.elementsById,
    points: perpendicular.points,
    fixedSegments: perpendicular.fixedSegments,
    startBinding: context.startBinding,
    endBinding: context.endBinding,
  );
}

_FixedSegmentPathResult _alignFixedSegmentsToBoundLanes({
  required ElementState element,
  required Map<String, ElementState> elementsById,
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
}) {
  if (points.length < 2 || fixedSegments.isEmpty) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }
  if (startBinding == null && endBinding == null) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  var worldPoints = points.map(space.toWorld).toList(growable: false);
  var changed = false;

  if (startBinding != null) {
    final result = _slideFixedSpanForBoundEndpoint(
      points: worldPoints,
      fixedSegments: fixedSegments,
      binding: startBinding,
      elementsById: elementsById,
      isStart: true,
    );
    if (result.moved) {
      worldPoints = result.points;
      changed = true;
    }
  }

  if (endBinding != null) {
    final result = _slideFixedSpanForBoundEndpoint(
      points: worldPoints,
      fixedSegments: fixedSegments,
      binding: endBinding,
      elementsById: elementsById,
      isStart: false,
    );
    if (result.moved) {
      worldPoints = result.points;
      changed = true;
    }
  }

  if (!changed) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }

  var localPoints = worldPoints.map(space.fromWorld).toList(growable: false);
  localPoints = _trimTrailingDuplicates(localPoints);
  final synced = _syncFixedSegmentsToPoints(localPoints, fixedSegments);
  return _mergeFixedSegmentsWithCollinearNeighbors(
    points: localPoints,
    fixedSegments: synced,
    allowDirectionFlip: true,
  );
}

List<DrawPoint> _trimTrailingDuplicates(List<DrawPoint> points) {
  if (points.length < 2) {
    return points;
  }
  final updated = List<DrawPoint>.from(points);
  while (updated.length > 1) {
    final last = updated[updated.length - 1];
    final prev = updated[updated.length - 2];
    if (ElbowGeometry.manhattanDistance(last, prev) >
        ElbowConstants.dedupThreshold) {
      break;
    }
    updated.removeLast();
  }
  return List<DrawPoint>.unmodifiable(updated);
}

({List<DrawPoint> points, bool moved}) _slideFixedSpanForBoundEndpoint({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  required ArrowBinding binding,
  required Map<String, ElementState> elementsById,
  required bool isStart,
}) {
  if (points.length < 2 || fixedSegments.isEmpty) {
    return (points: points, moved: false);
  }
  final endpoint = isStart ? points.first : points.last;
  final heading = _resolveBoundHeading(
    binding: binding,
    elementsById: elementsById,
    point: endpoint,
  );
  if (heading == null) {
    return (points: points, moved: false);
  }

  final targetFixedHorizontal = !heading.isHorizontal;
  ElbowFixedSegment? candidate;
  if (isStart) {
    for (final segment in fixedSegments) {
      final isHorizontal = ElbowPathUtils.segmentIsHorizontal(
        segment.start,
        segment.end,
      );
      if (isHorizontal == targetFixedHorizontal) {
        candidate = segment;
        break;
      }
    }
  } else {
    for (var i = fixedSegments.length - 1; i >= 0; i--) {
      final segment = fixedSegments[i];
      final isHorizontal = ElbowPathUtils.segmentIsHorizontal(
        segment.start,
        segment.end,
      );
      if (isHorizontal == targetFixedHorizontal) {
        candidate = segment;
        break;
      }
    }
  }
  if (candidate == null) {
    return (points: points, moved: false);
  }

  final anchorIndex = isStart ? candidate.index - 1 : candidate.index;
  if (anchorIndex <= 0 || anchorIndex >= points.length - 1) {
    return (points: points, moved: false);
  }

  final adjacentHorizontal = isStart
      ? (points[anchorIndex - 1].y - points[anchorIndex].y).abs() <=
          ElbowConstants.dedupThreshold
      : (points[anchorIndex].y - points[anchorIndex + 1].y).abs() <=
          ElbowConstants.dedupThreshold;
  if (heading.isHorizontal && !adjacentHorizontal) {
    return (points: points, moved: false);
  }
  if (!heading.isHorizontal && adjacentHorizontal) {
    return (points: points, moved: false);
  }

  final targetElement = elementsById[binding.elementId];
  if (targetElement == null) {
    return (points: points, moved: false);
  }
  final bounds = SelectionCalculator.computeElementWorldAabb(targetElement);
  final reference = points[anchorIndex];
  final lane = heading.isHorizontal
      ? _resolveBoundLaneCoordinate(
          horizontal: true,
          bounds: bounds,
          reference: reference,
        )
      : (isStart ? points.first.x : points.last.x);
  if (lane == null) {
    return (points: points, moved: false);
  }

  final updated = _slideRun(
    points: points,
    startIndex: anchorIndex,
    horizontal: heading.isHorizontal,
    target: lane,
    direction: isStart ? -1 : 1,
  );
  return (points: updated.points, moved: updated.moved);
}

double? _resolveBoundLaneCoordinate({
  required bool horizontal,
  required DrawRect bounds,
  required DrawPoint reference,
}) {
  if (horizontal) {
    final above = bounds.minY - ElbowConstants.basePadding;
    final below = bounds.maxY + ElbowConstants.basePadding;
    if (reference.y <= bounds.minY) {
      return above;
    }
    if (reference.y >= bounds.maxY) {
      return below;
    }
    return (reference.y - above).abs() <= (reference.y - below).abs()
        ? above
        : below;
  }

  final left = bounds.minX - ElbowConstants.basePadding;
  final right = bounds.maxX + ElbowConstants.basePadding;
  if (reference.x <= bounds.minX) {
    return left;
  }
  if (reference.x >= bounds.maxX) {
    return right;
  }
  return (reference.x - left).abs() <= (reference.x - right).abs()
      ? left
      : right;
}

({List<DrawPoint> points, bool moved}) _slideRun({
  required List<DrawPoint> points,
  required int startIndex,
  required bool horizontal,
  required double target,
  required int direction,
}) {
  if (startIndex < 0 || startIndex >= points.length) {
    return (points: points, moved: false);
  }
  if (direction != 1 && direction != -1) {
    return (points: points, moved: false);
  }
  final current = horizontal ? points[startIndex].y : points[startIndex].x;
  if ((current - target).abs() <= ElbowConstants.dedupThreshold) {
    return (points: points, moved: false);
  }

  final updated = List<DrawPoint>.from(points);
  updated[startIndex] = horizontal
      ? updated[startIndex].copyWith(y: target)
      : updated[startIndex].copyWith(x: target);

  var i = startIndex;
  while (true) {
    final nextIndex = i + direction;
    if (nextIndex < 0 || nextIndex >= points.length) {
      break;
    }
    final curr = points[i];
    final next = points[nextIndex];
    final isHorizontal =
        (curr.y - next.y).abs() <= ElbowConstants.dedupThreshold;
    if (isHorizontal != horizontal) {
      break;
    }
    updated[nextIndex] = horizontal
        ? updated[nextIndex].copyWith(y: target)
        : updated[nextIndex].copyWith(x: target);
    i = nextIndex;
  }

  return (points: updated, moved: true);
}
