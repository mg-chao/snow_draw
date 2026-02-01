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
  // Step C: enforce fixed segment axes after endpoint changes.
  state = _applyFixedSegmentAxes(state);
  // Step D: for unbound arrows, re-route if a diagonal drift appears.
  state = _rerouteForDiagonalDrift(context: context, state: state);
  // Step E: snap neighbors to maintain orthogonality for unbound endpoints.
  state = _snapUnboundNeighbors(context: context, state: state);
  // Step F: re-apply fixed segments after neighbor snapping.
  state = _applyFixedSegmentAxes(state);
  // Step G: merge collinear tail segments for fully unbound paths.
  state = _mergeTailIfUnbound(context: context, state: state);

  final synced = _syncFixedSegmentsToPoints(
    state.points,
    state.fixedSegments,
  );
  if (context.isFullyUnbound) {
    return _FixedSegmentPathResult(points: state.points, fixedSegments: synced);
  }

  // Step H: enforce perpendicularity for bound endpoints in world space.
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
