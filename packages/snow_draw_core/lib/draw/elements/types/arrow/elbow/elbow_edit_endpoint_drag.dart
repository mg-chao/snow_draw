part of 'elbow_editing.dart';

List<DrawPoint>? _buildFallbackPointsForActiveFixed({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowFixedSegment fixedSegment,
  required ElbowHeading requiredHeading,
  bool startBound = false,
}) {
  if (startBound) {
    return _buildFallbackPointsForActiveFixed(
      start: end,
      end: start,
      fixedSegment: fixedSegment,
      requiredHeading: requiredHeading.opposite,
    )?.reversed.toList(growable: false);
  }
  final h = fixedSegment.isHorizontal;
  final axis = fixedSegment.axisValue;
  const padding = ElbowConstants.directionFixPadding;
  double travel(DrawPoint p) => h ? p.x : p.y;
  double perp(DrawPoint p) => h ? p.y : p.x;

  var mid = (travel(start) + travel(end)) / 2;
  final pos = h ? ElbowHeading.right : ElbowHeading.down;
  final neg = h ? ElbowHeading.left : ElbowHeading.up;
  if (requiredHeading == pos && mid >= travel(end)) {
    mid = travel(end) - padding;
  } else if (requiredHeading == neg && mid <= travel(end)) {
    mid = travel(end) + padding;
  }

  DrawPoint pt(double t, double p) =>
      h ? DrawPoint(x: t, y: p) : DrawPoint(x: p, y: t);
  final points = [
    start,
    pt(travel(start), axis),
    pt(mid, axis),
    pt(mid, perp(end)),
    end,
  ];
  final simplified = ElbowGeometry.simplifyPath(points);
  return simplified.length >= 2
      ? List<DrawPoint>.unmodifiable(simplified)
      : null;
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
  final stitched = _stitchSubPath(
    points: points,
    startIndex: startBound ? 0 : anchorIndex,
    endIndex: startBound ? anchorIndex : points.length - 1,
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
  required _ElbowEditContext context,
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

  final activePoint = activeIsStart ? state.points.first : state.points.last;
  final requiredHeading = context.resolveRequiredHeading(
    isStart: activeIsStart,
    point: activePoint,
  );

  final startLocal = activeIsStart
      ? state.points.first
      : state.points[anchorIndex];
  final endLocal = activeIsStart
      ? state.points[anchorIndex]
      : state.points.last;
  final routed = _routeLocalPath(
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
  required _ElbowEditContext context,
  required _FixedSegmentPathResult state,
}) {
  final noChange = (state: state, adoptedBaseline: false);
  if (!context.hasBindings ||
      (!context.hasBoundStart && !context.hasBoundEnd)) {
    return noChange;
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
      forceBaseline &&
          state.fixedSegments.isNotEmpty &&
          (activeStart || activeEnd)
      ? (activeStart ? state.fixedSegments.first : state.fixedSegments.last)
      : null;

  ElbowHeading? requiredHeading;
  if (activeSegment != null) {
    final point = activeStart ? state.points.first : state.points.last;
    requiredHeading = context.resolveRequiredHeading(
      isStart: activeStart,
      point: point,
    );
  }

  if (context.fixedSegments.isNotEmpty &&
      (context.hasBoundStart != context.hasBoundEnd) &&
      !forceBaseline) {
    return noChange;
  }

  // Strategy 1: single-fixed-segment fallback.
  if (forceBaseline &&
      state.fixedSegments.length == 1 &&
      activeSegment != null &&
      requiredHeading != null) {
    final pts = _buildFallbackPointsForActiveFixed(
      start: state.points.first,
      end: state.points.last,
      fixedSegment: activeSegment,
      requiredHeading: requiredHeading,
      startBound: activeStart,
    );
    if (pts != null) {
      final reindexed = _reindexFixedSegments(pts, [activeSegment]);
      if (reindexed.isNotEmpty) {
        return (
          state: state.copyWith(
            points: List<DrawPoint>.from(pts),
            fixedSegments: List<ElbowFixedSegment>.unmodifiable(reindexed),
          ),
          adoptedBaseline: true,
        );
      }
    }
  }

  // Strategy 2: map fixed segments onto a freshly routed baseline.
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
  if (mapped != null) {
    final adopted = forceBaseline
        ? _normalizeFixedSegmentPath(
            points: mapped.points,
            fixedSegments: mapped.fixedSegments,
            enforceAxes: true,
          )
        : mapped;
    return (
      state: state.copyWith(
        points: List<DrawPoint>.from(adopted.points),
        fixedSegments: adopted.fixedSegments,
      ),
      adoptedBaseline: true,
    );
  }

  // Strategy 3: active-span fallback via the fixed segment.
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

  return noChange;
}

_FixedSegmentPathResult _rerouteReleasedBindingSpan({
  required _ElbowEditContext context,
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
  var fixed = state.fixedSegments;

  for (final isStart in const [true, false]) {
    if (!(isStart ? context.startBindingRemoved : context.endBindingRemoved)) {
      continue;
    }
    if (isStart ? skipStart : skipEnd) {
      continue;
    }
    final bf = fixed.isEmpty ? null : (isStart ? fixed.first : fixed.last);
    final s = isStart ? 0 : (bf?.index ?? 0);
    final e = isStart
        ? (bf != null ? bf.index - 1 : points.length - 1)
        : points.length - 1;
    if (s < 0 || e >= points.length || s >= e) {
      continue;
    }
    final routed = _routeLocalPath(
      element: context.element,
      elementsById: context.elementsById,
      startLocal: points[s],
      endLocal: points[e],
      startArrowhead: s == 0 ? context.startArrowhead : ArrowheadStyle.none,
      endArrowhead: e == points.length - 1
          ? context.endArrowhead
          : ArrowheadStyle.none,
      previousFixed: isStart ? null : bf,
      nextFixed: isStart ? bf : null,
      startBinding: s == 0 ? context.startBinding : null,
      endBinding: e == points.length - 1 ? context.endBinding : null,
    );
    final result = _stitchSubPath(
      points: points,
      startIndex: s,
      endIndex: e,
      subPath: routed,
      fixedSegments: fixed,
    );
    points = result.points;
    fixed = result.fixedSegments;
  }
  return state.copyWith(points: points, fixedSegments: fixed);
}

_FixedSegmentPathResult _enforceOrthogonality({
  required _ElbowEditContext context,
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

  // Snap unbound neighbors to the nearest axis.
  if (points.length > 1) {
    final updated = List<DrawPoint>.from(points);
    for (final isStart in const [true, false]) {
      if (isStart ? context.hasBoundStart : context.hasBoundEnd) {
        continue;
      }
      final lastIndex = updated.length - 1;
      final ei = isStart ? 0 : lastIndex;
      final ni = isStart ? 1 : lastIndex - 1;
      final endpoint = updated[ei];
      final neighbor = updated[ni];
      final adjacentFixed = _fixedSegmentIsHorizontal(
        fixedSegments,
        isStart ? 2 : ni,
      );
      final snapX =
          adjacentFixed ??
          ((neighbor.x - endpoint.x).abs() <= (neighbor.y - endpoint.y).abs());
      updated[ni] = snapX
          ? neighbor.copyWith(x: endpoint.x)
          : neighbor.copyWith(y: endpoint.y);
    }
    points = updated;
  }
  points = _applyFixedSegmentsToPoints(points, fixedSegments);

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

_FixedSegmentPathResult _applyEndpointDragWithFixedSegments({
  required _ElbowEditContext context,
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
    final merged = _mergeFixedSegmentsWithCollinearNeighbors(
      points: state.points,
      fixedSegments: _syncFixedSegmentsToPoints(
        state.points,
        state.fixedSegments,
      ),
      allowDirectionFlip: true,
    );
    if (merged.fixedSegments.length == state.fixedSegments.length) {
      state = merged;
    }
  }
  final synced = _syncFixedSegmentsToPoints(state.points, state.fixedSegments);
  if (context.isFullyUnbound) {
    return _FixedSegmentPathResult(points: state.points, fixedSegments: synced);
  }

  // Step 6: enforce perpendicularity for bound endpoints in world space.
  final perpendicular = _ensurePerpendicularBindings(
    context: context,
    points: state.points,
    fixedSegments: synced,
  );
  return _alignFixedSegmentsToBoundLanes(
    context: context,
    points: perpendicular.points,
    fixedSegments: perpendicular.fixedSegments,
  );
}

_FixedSegmentPathResult _alignFixedSegmentsToBoundLanes({
  required _ElbowEditContext context,
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
}) {
  final startBinding = context.startBinding;
  final endBinding = context.endBinding;
  if (points.length < 2 ||
      fixedSegments.isEmpty ||
      (startBinding == null && endBinding == null)) {
    return _FixedSegmentPathResult(
      points: points,
      fixedSegments: fixedSegments,
    );
  }
  final element = context.element;
  final elementsById = context.elementsById;
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
  return _mergeFixedSegmentsWithCollinearNeighbors(
    points: localPoints,
    fixedSegments: _syncFixedSegmentsToPoints(localPoints, fixedSegments),
    allowDirectionFlip: true,
  );
}

({List<DrawPoint> points, bool moved}) _slideFixedSpanForBoundEndpoint({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  required ArrowBinding binding,
  required Map<String, ElementState> elementsById,
  required bool isStart,
}) {
  final noMove = (points: points, moved: false);
  if (points.length < 2 || fixedSegments.isEmpty) {
    return noMove;
  }
  final endpoint = isStart ? points.first : points.last;
  final heading = ElbowGeometry.resolveBoundHeading(
    binding: binding,
    elementsById: elementsById,
    point: endpoint,
  );
  if (heading == null) {
    return noMove;
  }
  final targetFixedH = !heading.isHorizontal;
  final nearest = isStart ? fixedSegments.first : fixedSegments.last;
  ElbowFixedSegment? candidate;
  for (final s in isStart ? fixedSegments : fixedSegments.reversed) {
    if (s.isHorizontal == targetFixedH) {
      candidate = s;
      break;
    }
  }
  if (candidate == null || candidate.index != nearest.index) {
    return noMove;
  }
  final anchorIndex = isStart ? candidate.index - 1 : candidate.index;
  if (anchorIndex <= 0 || anchorIndex >= points.length - 1) {
    return noMove;
  }
  final adjA = isStart ? anchorIndex - 1 : anchorIndex;
  final adjB = isStart ? anchorIndex : anchorIndex + 1;
  final adjacentH =
      (points[adjA].y - points[adjB].y).abs() <= ElbowConstants.dedupThreshold;
  if (heading.isHorizontal != adjacentH) {
    return noMove;
  }
  final target = elementsById[binding.elementId];
  if (target == null) {
    return noMove;
  }
  final bounds = SelectionCalculator.computeElementWorldAabb(target);
  final lane = heading.isHorizontal
      ? _resolveHorizontalLane(
          points: points,
          endpoint: endpoint,
          reference: points[anchorIndex],
          anchorIndex: anchorIndex,
          bounds: bounds,
          isStart: isStart,
        )
      : (isStart ? points.first.x : points.last.x);
  if (lane == null) {
    return noMove;
  }
  return _slideRun(
    points: points,
    startIndex: anchorIndex,
    horizontal: heading.isHorizontal,
    target: lane,
    direction: isStart ? -1 : 1,
  );
}

double? _resolveHorizontalLane({
  required List<DrawPoint> points,
  required DrawPoint endpoint,
  required DrawPoint reference,
  required int anchorIndex,
  required DrawRect bounds,
  required bool isStart,
}) {
  final inBounds =
      reference.y >= bounds.minY - ElbowConstants.intersectionEpsilon &&
      reference.y <= bounds.maxY + ElbowConstants.intersectionEpsilon;
  if (inBounds &&
      !_runIntersectsBounds(
        points: points,
        startIndex: anchorIndex,
        direction: isStart ? -1 : 1,
        horizontal: true,
        bounds: bounds,
      )) {
    return (endpoint.y - reference.y).abs() > ElbowConstants.dedupThreshold
        ? endpoint.y
        : reference.y;
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

/// Walks consecutive points sharing the same axis from [startIndex] in
/// [direction], returning their indices and the min/max extent along the
/// varying axis.
({List<int> indices, double minVar, double maxVar}) _walkRun({
  required List<DrawPoint> points,
  required int startIndex,
  required int direction,
  required bool horizontal,
}) {
  final indices = <int>[startIndex];
  var i = startIndex;
  while (true) {
    final next = i + direction;
    if (next < 0 || next >= points.length) {
      break;
    }
    final isH =
        (points[i].y - points[next].y).abs() <= ElbowConstants.dedupThreshold;
    if (isH != horizontal) {
      break;
    }
    indices.add(next);
    i = next;
  }
  var minVar = horizontal ? points[startIndex].x : points[startIndex].y;
  var maxVar = minVar;
  for (final idx in indices) {
    final v = horizontal ? points[idx].x : points[idx].y;
    if (v < minVar) {
      minVar = v;
    }
    if (v > maxVar) {
      maxVar = v;
    }
  }
  return (indices: indices, minVar: minVar, maxVar: maxVar);
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
  final cMin = horizontal ? bounds.minY : bounds.minX;
  final cMax = horizontal ? bounds.maxY : bounds.maxX;
  if (constant < cMin - epsilon || constant > cMax + epsilon) {
    return false;
  }
  final run = _walkRun(
    points: points,
    startIndex: startIndex,
    direction: direction,
    horizontal: horizontal,
  );
  final vMin = horizontal ? bounds.minX : bounds.minY;
  final vMax = horizontal ? bounds.maxX : bounds.maxY;
  return run.maxVar >= vMin - epsilon && run.minVar <= vMax + epsilon;
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
  final run = _walkRun(
    points: points,
    startIndex: startIndex,
    direction: direction,
    horizontal: horizontal,
  );
  final updated = List<DrawPoint>.from(points);
  for (final idx in run.indices) {
    updated[idx] = horizontal
        ? updated[idx].copyWith(y: target)
        : updated[idx].copyWith(x: target);
  }
  return (points: updated, moved: true);
}
