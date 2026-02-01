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
  required _EndpointDragContext context,
}) {
  if (context.basePoints.length < 2) {
    return _FixedSegmentPathResult(
      points: context.incomingPoints,
      fixedSegments: context.fixedSegments,
    );
  }

  // Step A: select a stable reference path and apply endpoint overrides.
  final referencePoints = _referencePointsForEndpointDrag(
    basePoints: context.basePoints,
    incomingPoints: context.incomingPoints,
  );
  var updated = List<DrawPoint>.from(referencePoints);
  var workingFixedSegments = context.fixedSegments;
  updated[0] = context.incomingPoints.first;
  updated[updated.length - 1] = context.incomingPoints.last;

  // Step B: if any bindings exist, prefer a baseline route that respects them.
  if (context.hasBindings) {
    final baseline = _routeLocalPath(
      element: context.element,
      elementsById: context.elementsById,
      startLocal: updated.first,
      endLocal: updated.last,
      startArrowhead: context.startArrowhead,
      endArrowhead: context.endArrowhead,
      startBinding: context.startBinding,
      endBinding: context.endBinding,
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
  if (context.isFullyUnbound && _hasDiagonalSegments(updated)) {
    final baseline = _routeLocalPath(
      element: context.element,
      elementsById: context.elementsById,
      startLocal: updated.first,
      endLocal: updated.last,
      startArrowhead: context.startArrowhead,
      endArrowhead: context.endArrowhead,
    );
    final adopted = _maybeAdoptBaselineRoute(
      currentPoints: updated,
      fixedSegments: workingFixedSegments,
      baseline: baseline,
    );
    updated = List<DrawPoint>.from(adopted.points);
    workingFixedSegments = adopted.fixedSegments;
  }

  // Step E: snap neighbors to maintain orthogonality for unbound endpoints.
  if (!context.hasBoundStart) {
    updated = _snapUnboundStartNeighbor(
      points: updated,
      fixedSegments: workingFixedSegments,
    );
  }
  if (!context.hasBoundEnd) {
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
  if (context.isFullyUnbound) {
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
  if (context.isFullyUnbound) {
    return _FixedSegmentPathResult(points: updated, fixedSegments: synced);
  }

  // Step H: enforce perpendicularity for bound endpoints in world space.
  return _ensurePerpendicularBindings(
    element: context.element,
    elementsById: context.elementsById,
    points: updated,
    fixedSegments: synced,
    startBinding: context.startBinding,
    endBinding: context.endBinding,
    startArrowhead: context.startArrowhead,
    endArrowhead: context.endArrowhead,
  );
}
