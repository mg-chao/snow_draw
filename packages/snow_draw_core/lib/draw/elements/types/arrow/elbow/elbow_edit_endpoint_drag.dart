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

  /// Derives a drag context from the shared edit context.
  factory _EndpointDragContext.fromEditContext(_ElbowEditContext ctx) {
    final startPointChanged =
        ctx.basePoints.isNotEmpty &&
        ctx.incomingPoints.isNotEmpty &&
        ctx.basePoints.first != ctx.incomingPoints.first;
    final endPointChanged =
        ctx.basePoints.isNotEmpty &&
        ctx.incomingPoints.isNotEmpty &&
        ctx.basePoints.last != ctx.incomingPoints.last;
    return _EndpointDragContext(
      element: ctx.element,
      elementsById: ctx.elementsById,
      basePoints: ctx.basePoints,
      incomingPoints: ctx.incomingPoints,
      fixedSegments: ctx.fixedSegments,
      startBinding: ctx.startBinding,
      endBinding: ctx.endBinding,
      startBindingRemoved: ctx.startBindingRemoved,
      endBindingRemoved: ctx.endBindingRemoved,
      startWasBound: ctx.previousStartBinding != null,
      endWasBound: ctx.previousEndBinding != null,
      startActive:
          startPointChanged || ctx.previousStartBinding != ctx.startBinding,
      endActive: endPointChanged || ctx.previousEndBinding != ctx.endBinding,
      startArrowhead: ctx.data.startArrowhead,
      endArrowhead: ctx.data.endArrowhead,
    );
  }

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

  bool get hasBoundStart =>
      startBinding != null && elementsById.containsKey(startBinding!.elementId);

  bool get hasBoundEnd =>
      endBinding != null && elementsById.containsKey(endBinding!.elementId);

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
  final h = fixedSegment.isHorizontal;
  final axis = fixedSegment.axisValue;
  const padding = ElbowConstants.directionFixPadding;

  // For a horizontal fixed segment the "travel" axis is X; for vertical, Y.
  double travel(DrawPoint p) => h ? p.x : p.y;
  double perp(DrawPoint p) => h ? p.y : p.x;

  var mid = (travel(start) + travel(end)) / 2;
  final positiveHeading = h ? ElbowHeading.right : ElbowHeading.down;
  final negativeHeading = h ? ElbowHeading.left : ElbowHeading.up;
  if (requiredHeading == positiveHeading && mid >= travel(end)) {
    mid = travel(end) - padding;
  } else if (requiredHeading == negativeHeading && mid <= travel(end)) {
    mid = travel(end) + padding;
  }

  DrawPoint pt(double travelVal, double perpVal) => h
      ? DrawPoint(x: travelVal, y: perpVal)
      : DrawPoint(x: perpVal, y: travelVal);
  final p1 = pt(travel(start), axis);
  final p2 = pt(mid, axis);
  final p3 = pt(mid, perp(end));
  final points = [start, p1, p2, p3, end];

  final simplified = ElbowGeometry.simplifyPath(points);
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

  final anchorIndex = startBound
      ? activeSegment.index
      : activeSegment.index - 1;
  if (anchorIndex <= 0 || anchorIndex >= points.length) {
    return null;
  }
  final anchor = points[anchorIndex];
  final subPath = _buildFallbackPointsForActiveFixed(
    start: startBound ? points.first : anchor,
    end: startBound ? anchor : points.last,
    fixedSegment: activeSegment,
    requiredHeading: requiredHeading,
    startBound: startBound,
  );
  if (subPath == null) {
    return null;
  }
  final prefix = startBound
      ? const <DrawPoint>[]
      : (anchorIndex > 0
            ? points.sublist(0, anchorIndex)
            : const <DrawPoint>[]);
  final suffix = startBound
      ? (anchorIndex + 1 < points.length
            ? points.sublist(anchorIndex + 1)
            : const <DrawPoint>[])
      : const <DrawPoint>[];
  final stitched = <DrawPoint>[...prefix, ...subPath, ...suffix];
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
  final referencePoints =
      ElbowGeometry.pointListsEqualExceptEndpoints(
        context.basePoints,
        context.incomingPoints,
      )
      ? context.basePoints
      : context.incomingPoints;
  final updated = List<DrawPoint>.from(referencePoints);
  updated[0] = context.incomingPoints.first;
  updated[updated.length - 1] = context.incomingPoints.last;
  return _EndpointDragState(
    points: updated,
    fixedSegments: context.fixedSegments,
  );
}

bool _fixedSegmentAxesStable(
  List<ElbowFixedSegment> original,
  List<ElbowFixedSegment> updated,
) {
  if (original.length != updated.length) {
    return false;
  }
  for (var i = 0; i < original.length; i++) {
    if (original[i].isHorizontal != updated[i].isHorizontal) {
      return false;
    }
    if ((original[i].axisValue - updated[i].axisValue).abs() >
        ElbowConstants.dedupThreshold) {
      return false;
    }
  }
  return true;
}

/// Result type for [_rerouteActiveSpanIfNeeded].
///
/// [reroutedSide] is `true` when the start span was rerouted, `false`
/// when the end span was rerouted, and `null` when nothing changed.
typedef _RerouteResult = ({_EndpointDragState state, bool? reroutedSide});

/// Tries the active-span fallback path and returns an applied result,
/// or `null` when the fallback is not available or unstable.
_RerouteResult? _tryActiveSpanFallback({
  required _EndpointDragState state,
  required ElbowFixedSegment activeFixed,
  required ElbowHeading? requiredHeading,
  required bool activeIsStart,
}) {
  if (requiredHeading == null) {
    return null;
  }
  final fallback = _buildFallbackPathForActiveSpan(
    points: state.points,
    fixedSegments: state.fixedSegments,
    activeSegment: activeFixed,
    requiredHeading: requiredHeading,
    startBound: activeIsStart,
  );
  if (fallback == null ||
      !_fixedSegmentAxesStable(state.fixedSegments, fallback.fixedSegments)) {
    return null;
  }
  return (
    state: state.copyWith(
      points: List<DrawPoint>.from(fallback.points),
      fixedSegments: fallback.fixedSegments,
    ),
    reroutedSide: activeIsStart,
  );
}

_RerouteResult _rerouteActiveSpanIfNeeded({
  required _EndpointDragContext context,
  required _EndpointDragState state,
}) {
  if (state.fixedSegments.isEmpty || state.points.length < 2) {
    return (state: state, reroutedSide: null);
  }
  if (context.startActive == context.endActive) {
    return (state: state, reroutedSide: null);
  }

  final activeIsStart = context.startActive;
  final activeFixed = activeIsStart
      ? state.fixedSegments.first
      : state.fixedSegments.last;
  final anchorIndex = activeIsStart ? activeFixed.index : activeFixed.index - 1;
  if (anchorIndex <= 0 || anchorIndex >= state.points.length) {
    return (state: state, reroutedSide: null);
  }

  final activeBinding = activeIsStart
      ? context.startBinding
      : context.endBinding;
  final activePoint = activeIsStart ? state.points.first : state.points.last;
  final boundHeading = activeBinding == null
      ? null
      : ElbowGeometry.resolveBoundHeading(
          binding: activeBinding,
          elementsById: context.elementsById,
          point: activePoint,
        );
  final requiredHeading = boundHeading == null
      ? null
      : (activeIsStart ? boundHeading : boundHeading.opposite);

  final startLocal = activeIsStart
      ? state.points.first
      : state.points[anchorIndex];
  final endLocal = activeIsStart
      ? state.points[anchorIndex]
      : state.points.last;
  final routed = _routeReleasedRegion(
    element: context.element,
    elementsById: context.elementsById,
    startLocal: startLocal,
    endLocal: endLocal,
    startArrowhead: activeIsStart
        ? context.startArrowhead
        : ArrowheadStyle.none,
    endArrowhead: activeIsStart ? ArrowheadStyle.none : context.endArrowhead,
    previousFixed: activeIsStart ? null : activeFixed,
    nextFixed: activeIsStart ? activeFixed : null,
    startBinding: activeIsStart ? context.startBinding : null,
    endBinding: activeIsStart ? null : context.endBinding,
  );
  if (routed.length < 2) {
    return (state: state, reroutedSide: null);
  }

  final stitched = activeIsStart
      ? <DrawPoint>[
          ...routed,
          if (anchorIndex + 1 < state.points.length)
            ...state.points.sublist(anchorIndex + 1),
        ]
      : <DrawPoint>[
          if (anchorIndex > 0) ...state.points.sublist(0, anchorIndex),
          ...routed,
        ];
  if (ElbowGeometry.pointListsEqual(stitched, state.points)) {
    return (state: state, reroutedSide: null);
  }

  final changedStructure =
      stitched.length != state.points.length ||
      !ElbowGeometry.pointListsEqualExceptEndpoints(stitched, state.points);
  final updatedFixed = changedStructure
      ? _reindexFixedSegments(stitched, state.fixedSegments)
      : _syncFixedSegmentsToPoints(stitched, state.fixedSegments);

  // When reindexing lost a segment, try the fallback path.
  if (updatedFixed.length != state.fixedSegments.length) {
    return _tryActiveSpanFallback(
          state: state,
          activeFixed: activeFixed,
          requiredHeading: requiredHeading,
          activeIsStart: activeIsStart,
        ) ??
        (state: state, reroutedSide: null);
  }

  // When axes drifted or heading flipped, try the fallback path.
  final axesStable = _fixedSegmentAxesStable(state.fixedSegments, updatedFixed);
  var headingMatches = true;
  if (requiredHeading != null) {
    final activeUpdated = activeIsStart
        ? updatedFixed.first
        : updatedFixed.last;
    final h = requiredHeading;
    if (h.isHorizontal == activeUpdated.isHorizontal) {
      final dx = activeUpdated.end.x - activeUpdated.start.x;
      final dy = activeUpdated.end.y - activeUpdated.start.y;
      headingMatches = switch (h) {
        ElbowHeading.right => dx > ElbowConstants.dedupThreshold,
        ElbowHeading.left => dx < -ElbowConstants.dedupThreshold,
        ElbowHeading.down => dy > ElbowConstants.dedupThreshold,
        ElbowHeading.up => dy < -ElbowConstants.dedupThreshold,
      };
    }
  }
  if (!axesStable || !headingMatches) {
    return _tryActiveSpanFallback(
          state: state,
          activeFixed: activeFixed,
          requiredHeading: requiredHeading,
          activeIsStart: activeIsStart,
        ) ??
        (state: state, reroutedSide: null);
  }

  return (
    state: state.copyWith(
      points: List<DrawPoint>.unmodifiable(stitched),
      fixedSegments: List<ElbowFixedSegment>.unmodifiable(updatedFixed),
    ),
    reroutedSide: activeIsStart,
  );
}

/// Step C: adopt a bound-aware baseline route when available.
({_EndpointDragState state, bool adoptedBaseline}) _adoptBaselineRouteIfNeeded({
  required _EndpointDragContext context,
  required _EndpointDragState state,
}) {
  if (!context.hasBindings) {
    return (state: state, adoptedBaseline: false);
  }
  if (!context.hasBoundStart && !context.hasBoundEnd) {
    return (state: state, adoptedBaseline: false);
  }

  // Resolve which endpoint is actively being dragged toward a bound element.
  final startActiveBound =
      context.hasBoundStart &&
      context.startActive &&
      context.startWasBound &&
      !context.startBindingRemoved;
  final endActiveBound =
      context.hasBoundEnd &&
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

  ElbowHeading? requiredHeading;
  if (activeSegment != null) {
    final activeBinding = activeStart
        ? context.startBinding
        : context.endBinding;
    final activePoint = activeStart ? state.points.first : state.points.last;
    final boundHeading = activeBinding == null
        ? null
        : ElbowGeometry.resolveBoundHeading(
            binding: activeBinding,
            elementsById: context.elementsById,
            point: activePoint,
          );
    requiredHeading = activeStart ? boundHeading : boundHeading?.opposite;
  }

  // Single fixed segment with a forced baseline: try direct fallback.
  if (forceBaseline &&
      state.fixedSegments.length == 1 &&
      activeSegment != null &&
      requiredHeading != null) {
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

  if (context.fixedSegments.isNotEmpty &&
      (context.hasBoundStart != context.hasBoundEnd) &&
      !forceBaseline) {
    return (state: state, adoptedBaseline: false);
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
  final mapped = _mapFixedSegmentsToBaseline(
    baseline: baseline,
    fixedSegments: state.fixedSegments,
    activeSegment: activeSegment,
    enforceAxisOnPoints: true,
    requireAll: true,
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
  bool skipStart = false,
  bool skipEnd = false,
}) {
  if (!context.startBindingRemoved && !context.endBindingRemoved) {
    return state;
  }
  if (state.points.length < 2) {
    return state;
  }

  var points = state.points;
  var fixedSegments = state.fixedSegments;

  void rerouteSpan({required bool isStart}) {
    final boundaryFixed = fixedSegments.isEmpty
        ? null
        : (isStart ? fixedSegments.first : fixedSegments.last);
    final spanStart = isStart ? 0 : (boundaryFixed?.index ?? 0);
    final spanEnd = isStart
        ? (boundaryFixed != null ? boundaryFixed.index - 1 : points.length - 1)
        : points.length - 1;
    if (spanStart < 0 || spanEnd >= points.length || spanStart >= spanEnd) {
      return;
    }
    final isFullSpan = spanStart == 0 && spanEnd == points.length - 1;
    final routed = _routeReleasedRegion(
      element: context.element,
      elementsById: context.elementsById,
      startLocal: points[spanStart],
      endLocal: points[spanEnd],
      startArrowhead: spanStart == 0
          ? context.startArrowhead
          : ArrowheadStyle.none,
      endArrowhead: spanEnd == points.length - 1
          ? context.endArrowhead
          : ArrowheadStyle.none,
      previousFixed: isStart ? null : boundaryFixed,
      nextFixed: isStart ? boundaryFixed : null,
      startBinding: spanStart == 0 ? context.startBinding : null,
      endBinding: isFullSpan || spanEnd == points.length - 1
          ? context.endBinding
          : null,
    );
    final prefix = spanStart > 0
        ? points.sublist(0, spanStart)
        : const <DrawPoint>[];
    final suffix = spanEnd + 1 < points.length
        ? points.sublist(spanEnd + 1)
        : const <DrawPoint>[];
    points = List<DrawPoint>.unmodifiable([...prefix, ...routed, ...suffix]);
    fixedSegments = _reindexFixedSegments(points, fixedSegments);
  }

  if (context.startBindingRemoved && !skipStart) {
    rerouteSpan(isStart: true);
  }
  if (context.endBindingRemoved && !skipEnd) {
    rerouteSpan(isStart: false);
  }

  return state.copyWith(points: points, fixedSegments: fixedSegments);
}

/// Enforces orthogonality in a single pass: applies fixed-segment axes,
/// re-routes diagonal drift, snaps unbound neighbors, and merges collinear
/// tails.
_EndpointDragState _enforceOrthogonality({
  required _EndpointDragContext context,
  required _EndpointDragState state,
}) {
  // Apply fixed segment axes.
  var points = _applyFixedSegmentsToPoints(state.points, state.fixedSegments);
  var fixedSegments = state.fixedSegments;

  // Re-route diagonal drift for fully unbound arrows.
  if (context.isFullyUnbound && ElbowGeometry.hasDiagonalSegments(points)) {
    final baseline = _routeLocalPath(
      element: context.element,
      elementsById: context.elementsById,
      startLocal: points.first,
      endLocal: points.last,
      startArrowhead: context.startArrowhead,
      endArrowhead: context.endArrowhead,
    );
    final mapped = _applyFixedSegmentsToBaselineRoute(
      baseline: baseline,
      fixedSegments: fixedSegments,
    );
    if (mapped.fixedSegments.length == fixedSegments.length) {
      points = List<DrawPoint>.from(mapped.points);
      fixedSegments = mapped.fixedSegments;
    }
  }

  // Snap unbound endpoint neighbors to stay orthogonal.
  if (!context.hasBoundStart) {
    points = _snapUnboundNeighbor(
      points: points,
      fixedSegments: fixedSegments,
      isStart: true,
    );
  }
  if (!context.hasBoundEnd) {
    points = _snapUnboundNeighbor(
      points: points,
      fixedSegments: fixedSegments,
      isStart: false,
    );
  }

  // Re-apply fixed segment axes after neighbor snapping.
  points = _applyFixedSegmentsToPoints(points, fixedSegments);

  // Merge trailing collinear segment for fully unbound paths.
  if (context.isFullyUnbound) {
    final merged = _mergeFixedSegmentWithEndCollinear(
      points: points,
      fixedSegments: fixedSegments,
    );
    if (merged.fixedSegments.length == fixedSegments.length) {
      points = merged.points;
      fixedSegments = merged.fixedSegments;
    }
  }

  return state.copyWith(
    points: List<DrawPoint>.from(points),
    fixedSegments: fixedSegments,
  );
}

/// Unchanged path result (no-op).
_FixedSegmentPathResult _unchangedResult(
  List<DrawPoint> points,
  List<ElbowFixedSegment> fixedSegments,
) => _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);

/// Collapses redundant stubs near binding endpoints after removal.
///
/// Delegates to the generic collinear-merge pass which already handles
/// removing intermediate points that share the same heading as their
/// neighbors, then collapses endpoint backtracks.
_EndpointDragState _collapseBindingRemovedStubs({
  required _EndpointDragContext context,
  required _EndpointDragState state,
}) {
  if (!context.startBindingRemoved && !context.endBindingRemoved) {
    return state;
  }
  if (state.fixedSegments.isEmpty) {
    return state;
  }
  final merged = _mergeFixedSegmentsWithCollinearNeighbors(
    points: state.points,
    fixedSegments: state.fixedSegments,
    allowDirectionFlip: true,
  );
  if (merged.fixedSegments.length != state.fixedSegments.length) {
    return state;
  }
  return state.copyWith(
    points: merged.points,
    fixedSegments: merged.fixedSegments,
  );
}

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

_FixedSegmentPathResult _applyEndpointDragWithFixedSegments({
  required _EndpointDragContext context,
}) {
  if (context.basePoints.length < 2) {
    return _FixedSegmentPathResult(
      points: context.incomingPoints,
      fixedSegments: context.fixedSegments,
    );
  }

  // Step 1: apply endpoint overrides to a stable reference path.
  var state = _buildEndpointDragState(context);

  // Step 2: reroute the active span or adopt a baseline route.
  final local = _rerouteActiveSpanIfNeeded(context: context, state: state);
  state = local.state;
  if (local.reroutedSide == null) {
    final baseline = _adoptBaselineRouteIfNeeded(
      context: context,
      state: state,
    );
    state = baseline.state;
  }

  // Step 3: reroute spans freed by binding removal.
  state = _rerouteReleasedBindingSpan(
    context: context,
    state: state,
    skipStart: local.reroutedSide == true,
    skipEnd: local.reroutedSide == false,
  );

  // Step 4: enforce orthogonality (axes, drift, neighbors, tail merge).
  state = _enforceOrthogonality(context: context, state: state);

  // Step 5: sync fixed segments and collapse binding stubs.
  var synced = _syncFixedSegmentsToPoints(state.points, state.fixedSegments);
  state = state.copyWith(fixedSegments: synced);
  state = _collapseBindingRemovedStubs(context: context, state: state);
  synced = _syncFixedSegmentsToPoints(state.points, state.fixedSegments);
  if (context.isFullyUnbound) {
    return _FixedSegmentPathResult(points: state.points, fixedSegments: synced);
  }

  // Step 6: enforce perpendicularity for bound endpoints in world space.
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
    return _unchangedResult(points, fixedSegments);
  }
  if (startBinding == null && endBinding == null) {
    return _unchangedResult(points, fixedSegments);
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
    return _unchangedResult(points, fixedSegments);
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
  final heading = ElbowGeometry.resolveBoundHeading(
    binding: binding,
    elementsById: elementsById,
    point: endpoint,
  );
  if (heading == null) {
    return (points: points, moved: false);
  }

  final targetFixedHorizontal = !heading.isHorizontal;
  ElbowFixedSegment? candidate;
  final searchOrder = isStart ? fixedSegments : fixedSegments.reversed;
  for (final segment in searchOrder) {
    if (segment.isHorizontal == targetFixedHorizontal) {
      candidate = segment;
      break;
    }
  }
  if (candidate == null) {
    return (points: points, moved: false);
  }
  final nearest = isStart ? fixedSegments.first : fixedSegments.last;
  if (candidate.index != nearest.index) {
    return (points: points, moved: false);
  }

  final anchorIndex = isStart ? candidate.index - 1 : candidate.index;
  if (anchorIndex <= 0 || anchorIndex >= points.length - 1) {
    return (points: points, moved: false);
  }

  final adjA = isStart ? anchorIndex - 1 : anchorIndex;
  final adjB = isStart ? anchorIndex : anchorIndex + 1;
  final adjacentHorizontal =
      (points[adjA].y - points[adjB].y).abs() <= ElbowConstants.dedupThreshold;
  if (heading.isHorizontal != adjacentHorizontal) {
    return (points: points, moved: false);
  }

  final targetElement = elementsById[binding.elementId];
  if (targetElement == null) {
    return (points: points, moved: false);
  }
  final bounds = SelectionCalculator.computeElementWorldAabb(targetElement);
  final reference = points[anchorIndex];
  final lane = heading.isHorizontal
      ? () {
          final endpointLane = endpoint.y;
          final inBounds =
              reference.y >= bounds.minY - ElbowConstants.intersectionEpsilon &&
              reference.y <= bounds.maxY + ElbowConstants.intersectionEpsilon;
          if (inBounds) {
            final intersects = _runIntersectsBounds(
              points: points,
              startIndex: anchorIndex,
              direction: isStart ? -1 : 1,
              horizontal: true,
              bounds: bounds,
            );
            if (!intersects) {
              if ((endpointLane - reference.y).abs() >
                  ElbowConstants.dedupThreshold) {
                return endpointLane;
              }
              return reference.y;
            }
          }
          return _resolveBoundLaneCoordinate(
            horizontal: true,
            bounds: bounds,
            reference: reference,
          );
        }()
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

/// Collects the indices of a collinear run starting at [startIndex]
/// and walking in [direction] (+1 or -1).
///
/// The returned list always starts with [startIndex] and includes
/// every consecutive point that shares the same [horizontal] axis.
List<int> _walkRunIndices({
  required List<DrawPoint> points,
  required int startIndex,
  required int direction,
  required bool horizontal,
}) {
  final indices = <int>[startIndex];
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
    indices.add(nextIndex);
    i = nextIndex;
  }
  return indices;
}

bool _runIntersectsBounds({
  required List<DrawPoint> points,
  required int startIndex,
  required int direction,
  required bool horizontal,
  required DrawRect bounds,
}) {
  if (points.length < 2 || startIndex < 0 || startIndex >= points.length) {
    return false;
  }
  const epsilon = ElbowConstants.intersectionEpsilon;
  final constant = horizontal ? points[startIndex].y : points[startIndex].x;
  if (horizontal) {
    if (constant < bounds.minY - epsilon || constant > bounds.maxY + epsilon) {
      return false;
    }
  } else if (constant < bounds.minX - epsilon ||
      constant > bounds.maxX + epsilon) {
    return false;
  }

  final indices = _walkRunIndices(
    points: points,
    startIndex: startIndex,
    direction: direction,
    horizontal: horizontal,
  );
  var minVar = horizontal ? points[startIndex].x : points[startIndex].y;
  var maxVar = minVar;
  for (final idx in indices) {
    final value = horizontal ? points[idx].x : points[idx].y;
    minVar = math.min(minVar, value);
    maxVar = math.max(maxVar, value);
  }

  if (horizontal) {
    return maxVar >= bounds.minX - epsilon && minVar <= bounds.maxX + epsilon;
  }
  return maxVar >= bounds.minY - epsilon && minVar <= bounds.maxY + epsilon;
}

({List<DrawPoint> points, bool moved}) _slideRun({
  required List<DrawPoint> points,
  required int startIndex,
  required bool horizontal,
  required double target,
  required int direction,
}) {
  if (startIndex < 0 ||
      startIndex >= points.length ||
      (direction != 1 && direction != -1)) {
    return (points: points, moved: false);
  }
  final current = horizontal ? points[startIndex].y : points[startIndex].x;
  if ((current - target).abs() <= ElbowConstants.dedupThreshold) {
    return (points: points, moved: false);
  }

  final indices = _walkRunIndices(
    points: points,
    startIndex: startIndex,
    direction: direction,
    horizontal: horizontal,
  );
  final updated = List<DrawPoint>.from(points);
  for (final idx in indices) {
    updated[idx] = horizontal
        ? updated[idx].copyWith(y: target)
        : updated[idx].copyWith(x: target);
  }
  return (points: updated, moved: true);
}
