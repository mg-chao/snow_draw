part of 'elbow_editing.dart';

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
    final hasPoints =
        ctx.basePoints.isNotEmpty && ctx.incomingPoints.isNotEmpty;
    final startPointChanged =
        hasPoints && ctx.basePoints.first != ctx.incomingPoints.first;
    final endPointChanged =
        hasPoints && ctx.basePoints.last != ctx.incomingPoints.last;
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

ElbowHeading? _resolveRequiredHeading({
  required ArrowBinding? binding,
  required Map<String, ElementState> elementsById,
  required DrawPoint point,
  required bool isStart,
}) {
  if (binding == null) {
    return null;
  }
  final heading = ElbowGeometry.resolveBoundHeading(
    binding: binding,
    elementsById: elementsById,
    point: point,
  );
  if (heading == null) {
    return null;
  }
  return isStart ? heading : heading.opposite;
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
  final subPath = _buildFallbackPointsForActiveFixed(
    start: startBound ? points.first : points[anchorIndex],
    end: startBound ? points[anchorIndex] : points.last,
    fixedSegment: activeSegment,
    requiredHeading: requiredHeading,
    startBound: startBound,
  );
  if (subPath == null) {
    return null;
  }

  final startIdx = startBound ? 0 : anchorIndex;
  final endIdx = startBound ? anchorIndex : points.length - 1;
  final stitched = _stitchSubPath(
    points: points,
    startIndex: startIdx,
    endIndex: endIdx,
    subPath: subPath,
    fixedSegments: fixedSegments,
  );
  if (stitched.fixedSegments.length != fixedSegments.length) {
    return null;
  }
  final simplified = _normalizeFixedSegmentPath(
    points: stitched.points,
    fixedSegments: stitched.fixedSegments,
  );
  return simplified.fixedSegments.length == fixedSegments.length
      ? simplified
      : stitched;
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

/// The `reroutedSide` field is `true` when the start span was rerouted,
/// `false` when the end span was rerouted, and `null` when nothing
/// changed.
typedef _RerouteResult = ({_FixedSegmentPathResult state, bool? reroutedSide});

_RerouteResult? _tryActiveSpanFallback({
  required _FixedSegmentPathResult state,
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
  required _FixedSegmentPathResult state,
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
  final requiredHeading = _resolveRequiredHeading(
    binding: activeBinding,
    elementsById: context.elementsById,
    point: activePoint,
    isStart: activeIsStart,
  );

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

  final stitchResult = _stitchSubPath(
    points: state.points,
    startIndex: activeIsStart ? 0 : anchorIndex,
    endIndex: activeIsStart ? anchorIndex : state.points.length - 1,
    subPath: routed,
    fixedSegments: state.fixedSegments,
  );
  final stitched = stitchResult.points;
  if (ElbowGeometry.pointListsEqual(stitched, state.points)) {
    return (state: state, reroutedSide: null);
  }

  final changedStructure =
      stitched.length != state.points.length ||
      !ElbowGeometry.pointListsEqualExceptEndpoints(stitched, state.points);
  final updatedFixed = changedStructure
      ? stitchResult.fixedSegments
      : _syncFixedSegmentsToPoints(stitched, state.fixedSegments);

  // When reindexing lost a segment, axes drifted, or heading flipped,
  // try the fallback path.
  final axesStable =
      updatedFixed.length == state.fixedSegments.length &&
      _fixedSegmentAxesStable(state.fixedSegments, updatedFixed);
  final headingFlipped =
      axesStable &&
      requiredHeading != null &&
      updatedFixed.isNotEmpty &&
      () {
        final seg = activeIsStart ? updatedFixed.first : updatedFixed.last;
        return requiredHeading.isHorizontal == seg.isHorizontal &&
            !_directionMatches(seg.start, seg.end, requiredHeading);
      }();
  if (!axesStable || headingFlipped) {
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

({_FixedSegmentPathResult state, bool adoptedBaseline})
_adoptBaselineRouteIfNeeded({
  required _EndpointDragContext context,
  required _FixedSegmentPathResult state,
}) {
  if (!context.hasBindings ||
      (!context.hasBoundStart && !context.hasBoundEnd)) {
    return (state: state, adoptedBaseline: false);
  }

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
    requiredHeading = _resolveRequiredHeading(
      binding: activeBinding,
      elementsById: context.elementsById,
      point: activePoint,
      isStart: activeStart,
    );
  }

  // Bail early for one-sided bindings without forced baseline.
  if (context.fixedSegments.isNotEmpty &&
      (context.hasBoundStart != context.hasBoundEnd) &&
      !forceBaseline) {
    return (state: state, adoptedBaseline: false);
  }

  // Try strategies in order; return the first success.
  final strategies = [
    () => _trySingleFixedFallback(
      state: state,
      forceBaseline: forceBaseline,
      activeSegment: activeSegment,
      requiredHeading: requiredHeading,
      activeStart: activeStart,
    ),
    () => _tryBaselineMapping(
      context: context,
      state: state,
      activeSegment: activeSegment,
      forceBaseline: forceBaseline,
    ),
    () => _tryActiveSpanBaselineFallback(
      state: state,
      forceBaseline: forceBaseline,
      activeSegment: activeSegment,
      requiredHeading: requiredHeading,
      activeStart: activeStart,
    ),
  ];
  for (final strategy in strategies) {
    final result = strategy();
    if (result != null) {
      return (state: result, adoptedBaseline: true);
    }
  }
  return (state: state, adoptedBaseline: false);
}

_FixedSegmentPathResult? _trySingleFixedFallback({
  required _FixedSegmentPathResult state,
  required bool forceBaseline,
  required ElbowFixedSegment? activeSegment,
  required ElbowHeading? requiredHeading,
  required bool activeStart,
}) {
  if (!forceBaseline ||
      state.fixedSegments.length != 1 ||
      activeSegment == null ||
      requiredHeading == null) {
    return null;
  }
  final fallbackPoints = _buildFallbackPointsForActiveFixed(
    start: state.points.first,
    end: state.points.last,
    fixedSegment: activeSegment,
    requiredHeading: requiredHeading,
    startBound: activeStart,
  );
  if (fallbackPoints == null) {
    return null;
  }
  final reindexed = _reindexFixedSegments(fallbackPoints, [activeSegment]);
  if (reindexed.isEmpty) {
    return null;
  }
  return state.copyWith(
    points: List<DrawPoint>.from(fallbackPoints),
    fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
  );
}

_FixedSegmentPathResult? _tryBaselineMapping({
  required _EndpointDragContext context,
  required _FixedSegmentPathResult state,
  required ElbowFixedSegment? activeSegment,
  required bool forceBaseline,
}) {
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
    return null;
  }
  final adopted = forceBaseline
      ? _normalizeFixedSegmentPath(
          points: mapped.points,
          fixedSegments: mapped.fixedSegments,
          enforceAxes: true,
        )
      : mapped;
  return state.copyWith(
    points: List<DrawPoint>.from(adopted.points),
    fixedSegments: adopted.fixedSegments,
  );
}

_FixedSegmentPathResult? _tryActiveSpanBaselineFallback({
  required _FixedSegmentPathResult state,
  required bool forceBaseline,
  required ElbowFixedSegment? activeSegment,
  required ElbowHeading? requiredHeading,
  required bool activeStart,
}) {
  if (!forceBaseline || activeSegment == null || requiredHeading == null) {
    return null;
  }
  final fallback = _buildFallbackPathForActiveSpan(
    points: state.points,
    fixedSegments: state.fixedSegments,
    activeSegment: activeSegment,
    requiredHeading: requiredHeading,
    startBound: activeStart,
  );
  if (fallback == null) {
    return null;
  }
  return state.copyWith(
    points: List<DrawPoint>.from(fallback.points),
    fixedSegments: fallback.fixedSegments,
  );
}

_FixedSegmentPathResult _rerouteReleasedBindingSpan({
  required _EndpointDragContext context,
  required _FixedSegmentPathResult state,
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
    final result = _stitchSubPath(
      points: points,
      startIndex: spanStart,
      endIndex: spanEnd,
      subPath: routed,
      fixedSegments: fixedSegments,
    );
    points = result.points;
    fixedSegments = result.fixedSegments;
  }

  if (context.startBindingRemoved && !skipStart) {
    rerouteSpan(isStart: true);
  }
  if (context.endBindingRemoved && !skipEnd) {
    rerouteSpan(isStart: false);
  }

  return state.copyWith(points: points, fixedSegments: fixedSegments);
}

_FixedSegmentPathResult _enforceOrthogonality({
  required _EndpointDragContext context,
  required _FixedSegmentPathResult state,
}) {
  var points = _applyFixedSegmentsToPoints(state.points, state.fixedSegments);
  var fixedSegments = state.fixedSegments;

  // Re-route diagonal drift for fully unbound arrows.
  if (context.isFullyUnbound && ElbowGeometry.hasDiagonalSegments(points)) {
    final mapped = _mapFixedSegmentsToBaseline(
      baseline: _routeLocalPath(
        element: context.element,
        elementsById: context.elementsById,
        startLocal: points.first,
        endLocal: points.last,
        startArrowhead: context.startArrowhead,
        endArrowhead: context.endArrowhead,
      ),
      fixedSegments: fixedSegments,
    );
    if (mapped != null && mapped.fixedSegments.length == fixedSegments.length) {
      points = List<DrawPoint>.from(mapped.points);
      fixedSegments = mapped.fixedSegments;
    }
  }

  // Snap unbound endpoint neighbors to stay orthogonal.
  for (final isStart in const [true, false]) {
    final isBound = isStart ? context.hasBoundStart : context.hasBoundEnd;
    if (!isBound) {
      points = _snapUnboundNeighbor(
        points: points,
        fixedSegments: fixedSegments,
        isStart: isStart,
      );
    }
  }

  // Re-apply fixed segment axes after neighbor snapping.
  points = _applyFixedSegmentsToPoints(points, fixedSegments);

  // Merge trailing collinear segment for fully unbound paths.
  if (context.isFullyUnbound) {
    final merged = _mergeFixedSegmentsWithCollinearNeighbors(
      points: points,
      fixedSegments: fixedSegments,
    );
    if (merged.fixedSegments.length == fixedSegments.length) {
      return merged;
    }
  }

  return state.copyWith(
    points: List<DrawPoint>.from(points),
    fixedSegments: fixedSegments,
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
  final lastIndex = points.length - 1;
  final endpointIndex = isStart ? 0 : lastIndex;
  final neighborIndex = isStart ? 1 : lastIndex - 1;
  final endpoint = points[endpointIndex];
  final neighbor = points[neighborIndex];
  final adjacentFixedIndex = isStart ? 2 : neighborIndex;
  final adjacentFixed = _fixedSegmentIsHorizontal(
    fixedSegments,
    adjacentFixedIndex,
  );
  // When a fixed segment constrains the adjacent edge, snap perpendicular
  // to it; otherwise snap to whichever axis is closer.
  final snapX =
      adjacentFixed ??
      ((neighbor.x - endpoint.x).abs() <= (neighbor.y - endpoint.y).abs());
  final updated = List<DrawPoint>.from(points);
  updated[neighborIndex] = snapX
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
  var state = _FixedSegmentPathResult(
    points: updated,
    fixedSegments: context.fixedSegments,
  );

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
    skipStart: local.reroutedSide ?? false,
    skipEnd: local.reroutedSide == false,
  );

  // Step 4: enforce orthogonality (axes, drift, neighbors, tail merge).
  state = _enforceOrthogonality(context: context, state: state);

  // Step 5: sync fixed segments and collapse binding stubs.
  if ((context.startBindingRemoved || context.endBindingRemoved) &&
      state.fixedSegments.isNotEmpty) {
    final merged = _syncAndMergeFixedSegments(
      points: state.points,
      fixedSegments: state.fixedSegments,
      allowDirectionFlip: true,
    );
    if (merged.fixedSegments.length == state.fixedSegments.length) {
      state = merged;
    }
  }
  final synced = _syncFixedSegmentsToPoints(
    state.points,
    state.fixedSegments,
  );
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

  for (final (binding, isStart) in [
    (startBinding, true),
    (endBinding, false),
  ]) {
    if (binding == null) {
      continue;
    }
    final result = _slideFixedSpanForBoundEndpoint(
      points: worldPoints,
      fixedSegments: fixedSegments,
      binding: binding,
      elementsById: elementsById,
      isStart: isStart,
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

  final localPoints = worldPoints.map(space.fromWorld).toList(growable: true);
  while (localPoints.length > 1 &&
      ElbowGeometry.manhattanDistance(
            localPoints[localPoints.length - 1],
            localPoints[localPoints.length - 2],
          ) <=
          ElbowConstants.dedupThreshold) {
    localPoints.removeLast();
  }
  final synced = _syncAndMergeFixedSegments(
    points: localPoints,
    fixedSegments: fixedSegments,
    allowDirectionFlip: true,
  );
  return synced;
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
      ? _resolveHorizontalLane(
          points: points,
          endpoint: endpoint,
          reference: reference,
          anchorIndex: anchorIndex,
          bounds: bounds,
          isStart: isStart,
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

double? _resolveHorizontalLane({
  required List<DrawPoint> points,
  required DrawPoint endpoint,
  required DrawPoint reference,
  required int anchorIndex,
  required DrawRect bounds,
  required bool isStart,
}) {
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
      if ((endpointLane - reference.y).abs() > ElbowConstants.dedupThreshold) {
        return endpointLane;
      }
      return reference.y;
    }
  }
  final lo = bounds.minY - ElbowConstants.basePadding;
  final hi = bounds.maxY + ElbowConstants.basePadding;
  if (reference.y <= bounds.minY) {
    return lo;
  }
  if (reference.y >= bounds.maxY) {
    return hi;
  }
  return (reference.y - lo).abs() <= (reference.y - hi).abs() ? lo : hi;
}

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
