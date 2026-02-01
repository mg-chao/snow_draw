part of 'elbow_editing.dart';

/// Endpoint-drag flow for elbow editing with fixed segments.

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
  required ElementState element,
  required Map<String, ElementState> elementsById,
  required List<DrawPoint> basePoints,
  required List<DrawPoint> incomingPoints,
  required List<ElbowFixedSegment> fixedSegments,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
}) {
  if (basePoints.length < 2) {
    return _FixedSegmentPathResult(
      points: incomingPoints,
      fixedSegments: fixedSegments,
    );
  }

  // Step A: select a stable reference path and apply endpoint overrides.
  final referencePoints = _referencePointsForEndpointDrag(
    basePoints: basePoints,
    incomingPoints: incomingPoints,
  );
  var updated = List<DrawPoint>.from(referencePoints);
  var workingFixedSegments = fixedSegments;
  updated[0] = incomingPoints.first;
  updated[updated.length - 1] = incomingPoints.last;

  // Step B: if any bindings exist, prefer a baseline route that respects them.
  if (startBinding != null || endBinding != null) {
    final baseline = _routeLocalPath(
      element: element,
      elementsById: elementsById,
      startLocal: updated.first,
      endLocal: updated.last,
      startArrowhead: startArrowhead,
      endArrowhead: endArrowhead,
      startBinding: startBinding,
      endBinding: endBinding,
    );
    final adopted = _maybeAdoptBaselineRoute(
      currentPoints: updated,
      fixedSegments: workingFixedSegments,
      baseline: baseline,
    );
    updated = List<DrawPoint>.from(adopted.points);
    workingFixedSegments = adopted.fixedSegments;
  }

  // Step C: enforce fixed segment axes after endpoint changes.
  updated = List<DrawPoint>.from(
    _applyFixedSegmentsToPoints(updated, workingFixedSegments),
  );

  // Step D: for unbound arrows, re-route if a diagonal drift appears.
  if (startBinding == null &&
      endBinding == null &&
      _hasDiagonalSegments(updated)) {
    final baseline = _routeLocalPath(
      element: element,
      elementsById: elementsById,
      startLocal: updated.first,
      endLocal: updated.last,
      startArrowhead: startArrowhead,
      endArrowhead: endArrowhead,
    );
    final adopted = _maybeAdoptBaselineRoute(
      currentPoints: updated,
      fixedSegments: workingFixedSegments,
      baseline: baseline,
    );
    updated = List<DrawPoint>.from(adopted.points);
    workingFixedSegments = adopted.fixedSegments;
  }

  final hasStartBinding = _hasBindingTarget(startBinding, elementsById);
  final hasEndBinding = _hasBindingTarget(endBinding, elementsById);

  // Step E: snap neighbors to maintain orthogonality for unbound endpoints.
  if (!hasStartBinding) {
    updated = _snapUnboundStartNeighbor(
      points: updated,
      fixedSegments: workingFixedSegments,
    );
  }
  if (!hasEndBinding) {
    updated = _snapUnboundEndNeighbor(
      points: updated,
      fixedSegments: workingFixedSegments,
    );
  }

  // Step F: re-apply fixed segments after neighbor snapping.
  updated = List<DrawPoint>.from(
    _applyFixedSegmentsToPoints(updated, workingFixedSegments),
  );

  // Step G: merge collinear tail segments for unbound paths.
  if (startBinding == null && endBinding == null) {
    final merged = _mergeFixedSegmentWithEndCollinear(
      points: updated,
      fixedSegments: workingFixedSegments,
    );
    if (merged.fixedSegments.length == workingFixedSegments.length) {
      updated = merged.points;
      workingFixedSegments = merged.fixedSegments;
    }
  }

  final synced = _syncFixedSegmentsToPoints(updated, workingFixedSegments);
  if (startBinding == null && endBinding == null) {
    return _FixedSegmentPathResult(points: updated, fixedSegments: synced);
  }

  // Step H: enforce perpendicularity for bound endpoints in world space.
  return _ensurePerpendicularBindings(
    element: element,
    elementsById: elementsById,
    points: updated,
    fixedSegments: synced,
    startBinding: startBinding,
    endBinding: endBinding,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );
}
