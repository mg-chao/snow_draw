part of 'elbow_editing.dart';

/// Perpendicular binding enforcement for elbow editing.
///
/// Ensures the first and last segments meet bound elements at right angles,
/// preserving arrowhead spacing and stable fixed segments when edits occur.

_FixedSegmentPathResult _ensurePerpendicularBindings({
  required ElementState element,
  required Map<String, ElementState> elementsById,
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
}) {
  if (points.length < 2) {
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
  var worldPoints = points.map(space.toWorld).toList(growable: true);
  var updatedFixedSegments = fixedSegments;
  var localPoints = points;
  final baselinePadding = _resolveBaselineEndpointPadding(
    element: element,
    elementsById: elementsById,
    points: points,
    startBinding: startBinding,
    endBinding: endBinding,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );

  if (startBinding != null) {
    final fixedNeighborAxis = _fixedSegmentIsHorizontal(
      updatedFixedSegments,
      2,
    );
    final adjustment = _adjustPerpendicularStart(
      points: worldPoints,
      binding: startBinding,
      elementsById: elementsById,
      directionPadding: baselinePadding.start,
      fixedNeighborAxis: fixedNeighborAxis,
      hasArrowhead: startArrowhead != ArrowheadStyle.none,
      fixedSegments: updatedFixedSegments,
    );
    worldPoints = adjustment.points;
    if (adjustment.inserted || adjustment.moved) {
      localPoints = worldPoints.map(space.fromWorld).toList(growable: false);
      updatedFixedSegments = adjustment.inserted
          ? _reindexFixedSegments(localPoints, updatedFixedSegments)
          : _syncFixedSegmentsToPoints(localPoints, updatedFixedSegments);
    }
  }

  if (endBinding != null) {
    final endNeighborIndex = math.max(2, localPoints.length - 2);
    final fixedNeighborAxis = _fixedSegmentIsHorizontal(
      updatedFixedSegments,
      endNeighborIndex,
    );
    final adjustment = _adjustPerpendicularEnd(
      points: worldPoints,
      binding: endBinding,
      elementsById: elementsById,
      directionPadding: baselinePadding.end,
      fixedNeighborAxis: fixedNeighborAxis,
      hasArrowhead: endArrowhead != ArrowheadStyle.none,
      fixedSegments: updatedFixedSegments,
    );
    worldPoints = adjustment.points;
    if (adjustment.inserted || adjustment.moved) {
      localPoints = worldPoints.map(space.fromWorld).toList(growable: false);
      updatedFixedSegments = adjustment.inserted
          ? _reindexFixedSegments(localPoints, updatedFixedSegments)
          : _syncFixedSegmentsToPoints(localPoints, updatedFixedSegments);
    }
  }

  if (!identical(localPoints, points)) {
    return _mergeFixedSegmentsWithCollinearNeighbors(
      points: localPoints,
      fixedSegments: updatedFixedSegments,
      allowDirectionFlip: true,
    );
  }

  if (worldPoints.length != points.length) {
    localPoints = worldPoints.map(space.fromWorld).toList(growable: false);
    updatedFixedSegments = _reindexFixedSegments(
      localPoints,
      updatedFixedSegments,
    );
    return _mergeFixedSegmentsWithCollinearNeighbors(
      points: localPoints,
      fixedSegments: updatedFixedSegments,
      allowDirectionFlip: true,
    );
  }

  return _mergeFixedSegmentsWithCollinearNeighbors(
    points: points,
    fixedSegments: fixedSegments,
    allowDirectionFlip: true,
  );
}

({double? start, double? end}) _resolveBaselineEndpointPadding({
  required ElementState element,
  required Map<String, ElementState> elementsById,
  required List<DrawPoint> points,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
}) {
  if (points.length < 2 || (startBinding == null && endBinding == null)) {
    return (start: null, end: null);
  }

  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  final worldStart = space.toWorld(points.first);
  final worldEnd = space.toWorld(points.last);
  final routed = routeElbowArrow(
    start: worldStart,
    end: worldEnd,
    startBinding: startBinding,
    endBinding: endBinding,
    elementsById: elementsById,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );
  final routedPoints = routed.points;
  if (routedPoints.length < 3) {
    return (start: null, end: null);
  }

  final startPadding = startBinding == null
      ? null
      : _segmentPadding(routedPoints.first, routedPoints[1]);
  final endPadding = endBinding == null
      ? null
      : _segmentPadding(
          routedPoints[routedPoints.length - 2],
          routedPoints.last,
        );
  return (start: startPadding, end: endPadding);
}

double? _segmentPadding(DrawPoint from, DrawPoint to) {
  final length = ElbowGeometry.manhattanDistance(from, to);
  if (!length.isFinite || length <= ElbowConstants.dedupThreshold) {
    return null;
  }
  return length;
}

double _resolveDirectionPadding(double? desired) {
  if (desired == null || !desired.isFinite) {
    return ElbowConstants.directionFixPadding;
  }
  if (desired <= ElbowConstants.dedupThreshold) {
    return ElbowConstants.directionFixPadding;
  }
  return math.max(ElbowConstants.directionFixPadding, desired);
}

_PerpendicularAdjustment? _alignEndpointSegmentLength({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double? desiredLength,
  required bool isStart,
}) {
  if (points.length < 2 ||
      desiredLength == null ||
      !desiredLength.isFinite ||
      desiredLength <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final desiredHorizontal = heading.isHorizontal;
  final neighborIndex = isStart ? 1 : points.length - 2;
  if (points.length > 2) {
    final adjacentIndex = isStart ? neighborIndex + 1 : neighborIndex - 1;
    if (adjacentIndex >= 0 && adjacentIndex < points.length) {
      final adjacentHorizontal = ElbowPathUtils.segmentIsHorizontal(
        points[neighborIndex],
        points[adjacentIndex],
      );
      if (adjacentHorizontal != desiredHorizontal) {
        return null;
      }
    }
  }
  final endpoint = isStart ? points.first : points.last;
  final neighbor = points[neighborIndex];
  final target = _offsetPoint(endpoint, heading, desiredLength);
  final delta = desiredHorizontal
      ? (neighbor.x - target.x).abs()
      : (neighbor.y - target.y).abs();
  if (delta <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final updated = List<DrawPoint>.from(points);
  updated[neighborIndex] = desiredHorizontal
      ? neighbor.copyWith(x: target.x)
      : neighbor.copyWith(y: target.y);
  return _PerpendicularAdjustment(
    points: updated,
    moved: true,
    inserted: false,
  );
}

_PerpendicularAdjustment? _slideEndpointCornerToPadding({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double? desiredLength,
  required bool isStart,
}) {
  if (points.length < 4 ||
      desiredLength == null ||
      !desiredLength.isFinite ||
      desiredLength <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final desiredHorizontal = heading.isHorizontal;
  final lastIndex = points.length - 1;
  final endpointIndex = isStart ? 0 : lastIndex;
  final neighborIndex = isStart ? 1 : lastIndex - 1;
  final cornerIndex = isStart ? 2 : lastIndex - 2;
  final outerIndex = isStart ? 3 : lastIndex - 3;
  if (outerIndex < 0 || cornerIndex < 0 || neighborIndex < 0) {
    return null;
  }

  final endpoint = points[endpointIndex];
  final neighbor = points[neighborIndex];
  final corner = points[cornerIndex];
  final outer = points[outerIndex];
  final target = _offsetPoint(endpoint, heading, desiredLength);

  if (desiredHorizontal) {
    if ((neighbor.y - endpoint.y).abs() > ElbowConstants.dedupThreshold) {
      return null;
    }
    if ((corner.x - neighbor.x).abs() > ElbowConstants.dedupThreshold) {
      return null;
    }
    if ((outer.y - corner.y).abs() > ElbowConstants.dedupThreshold) {
      return null;
    }
    final originalDelta = isStart ? outer.x - corner.x : corner.x - outer.x;
    final newDelta = isStart ? outer.x - target.x : target.x - outer.x;
    if (originalDelta.abs() <= ElbowConstants.dedupThreshold ||
        newDelta.abs() <= ElbowConstants.dedupThreshold ||
        originalDelta.sign != newDelta.sign ||
        newDelta.abs() <= originalDelta.abs() * 0.5) {
      return null;
    }
    if ((neighbor.x - target.x).abs() <= ElbowConstants.dedupThreshold) {
      return null;
    }
    final updated = List<DrawPoint>.from(points);
    updated[neighborIndex] = neighbor.copyWith(x: target.x);
    updated[cornerIndex] = corner.copyWith(x: target.x);
    return _PerpendicularAdjustment(
      points: updated,
      moved: true,
      inserted: false,
    );
  }

  if ((neighbor.x - endpoint.x).abs() > ElbowConstants.dedupThreshold) {
    return null;
  }
  if ((corner.y - neighbor.y).abs() > ElbowConstants.dedupThreshold) {
    return null;
  }
  if ((outer.x - corner.x).abs() > ElbowConstants.dedupThreshold) {
    return null;
  }
  final originalDelta = isStart ? outer.y - corner.y : corner.y - outer.y;
  final newDelta = isStart ? outer.y - target.y : target.y - outer.y;
  if (originalDelta.abs() <= ElbowConstants.dedupThreshold ||
      newDelta.abs() <= ElbowConstants.dedupThreshold ||
      originalDelta.sign != newDelta.sign ||
      newDelta.abs() <= originalDelta.abs() * 0.5) {
    return null;
  }
  if ((neighbor.y - target.y).abs() <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final updated = List<DrawPoint>.from(points);
  updated[neighborIndex] = neighbor.copyWith(y: target.y);
  updated[cornerIndex] = corner.copyWith(y: target.y);
  return _PerpendicularAdjustment(
    points: updated,
    moved: true,
    inserted: false,
  );
}

_PerpendicularAdjustment _adjustPerpendicularStart({
  required List<DrawPoint> points,
  required ArrowBinding binding,
  required Map<String, ElementState> elementsById,
  required double? directionPadding,
  required bool hasArrowhead,
  required List<ElbowFixedSegment> fixedSegments,
  bool? fixedNeighborAxis,
}) {
  if (points.length < 2) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final heading = _resolveBoundHeading(
    binding: binding,
    elementsById: elementsById,
    point: points.first,
  );
  if (heading == null) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final desiredHorizontal = heading.isHorizontal;
  final resolvedPadding = _resolveDirectionPadding(directionPadding);
  final start = points.first;
  final neighbor = points[1];
  final stubPadding = _capDirectionPaddingForAxis(
    padding: resolvedPadding,
    endpoint: start,
    heading: heading,
    axis: _resolveFixedAxisLimit(
      points: points,
      fixedSegments: fixedSegments,
      isStart: true,
      heading: heading,
    ),
  );
  final aligned = desiredHorizontal
      ? (neighbor.y - start.y).abs() <= ElbowConstants.dedupThreshold
      : (neighbor.x - start.x).abs() <= ElbowConstants.dedupThreshold;
  final directionOk = _directionMatches(start, neighbor, heading);

  final preserveNeighbor = fixedNeighborAxis != null;
  final canSlideNeighbor = _canSlideFixedNeighbor(
    fixedNeighborAxis: fixedNeighborAxis,
    desiredHorizontal: desiredHorizontal,
  );
  final fixedPadding = _resolveFixedNeighborPadding(hasArrowhead);

  if (preserveNeighbor) {
    if (aligned && directionOk) {
      final adjusted = canSlideNeighbor
          ? _slideEndpointNeighborToPadding(
              points: points,
              heading: heading,
              desiredLength: fixedPadding,
              cornerInserted: false,
              isStart: true,
            )
          : null;
      if (adjusted != null) {
        return adjusted;
      }
      return _PerpendicularAdjustment(
        points: points,
        moved: false,
        inserted: false,
      );
    }
    if (!aligned && directionOk) {
      final inserted = _insertEndpointCorner(
        points: points,
        heading: heading,
        neighbor: neighbor,
        isStart: true,
      );
      final adjusted = canSlideNeighbor
          ? _slideEndpointNeighborToPadding(
              points: inserted.points,
              heading: heading,
              desiredLength: fixedPadding,
              cornerInserted: true,
              isStart: true,
            )
          : null;
      return adjusted ?? inserted;
    }
    if (aligned) {
      if (canSlideNeighbor) {
        final adjusted = _slideEndpointNeighborToPadding(
          points: points,
          heading: heading,
          desiredLength: fixedPadding,
          cornerInserted: false,
          isStart: true,
        );
        if (adjusted != null) {
          return adjusted;
        }
      }
      // Keep the aligned segment when forcing direction would backtrack
      // against a fixed neighbor.
      return _PerpendicularAdjustment(
        points: points,
        moved: false,
        inserted: false,
      );
    }
    return _insertEndpointDirectionStub(
      points: points,
      heading: heading,
      neighbor: neighbor,
      allowExtend: false,
      padding: resolvedPadding,
      isStart: true,
    );
  }

  if (aligned && directionOk) {
    final adjusted = _alignEndpointSegmentLength(
      points: points,
      heading: heading,
      desiredLength: directionPadding,
      isStart: true,
    );
    if (adjusted != null) {
      return adjusted;
    }
    final slid = _slideEndpointCornerToPadding(
      points: points,
      heading: heading,
      desiredLength: directionPadding,
      isStart: true,
    );
    if (slid != null) {
      return slid;
    }
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  if (aligned && !directionOk) {
    final updated = List<DrawPoint>.from(points);
    updated[1] = _applyEndpointDirection(
      neighbor,
      start,
      heading,
      resolvedPadding,
    );
    return _PerpendicularAdjustment(
      points: updated,
      moved: true,
      inserted: false,
    );
  }

  final nextHorizontal = points.length > 2
      ? ElbowPathUtils.segmentIsHorizontal(neighbor, points[2])
      : desiredHorizontal;
  final conflict = nextHorizontal == desiredHorizontal;
  final canShiftDirection =
      points.length <= 2 ||
      (desiredHorizontal ? nextHorizontal : !nextHorizontal);

  if (!conflict && (directionOk || canShiftDirection)) {
    var updatedNeighbor = neighbor;
    if (!aligned) {
      updatedNeighbor = desiredHorizontal
          ? updatedNeighbor.copyWith(y: start.y)
          : updatedNeighbor.copyWith(x: start.x);
    }
    if (!directionOk && canShiftDirection) {
      updatedNeighbor = _applyEndpointDirection(
        updatedNeighbor,
        start,
        heading,
        resolvedPadding,
      );
    }
    final updated = List<DrawPoint>.from(points);
    updated[1] = updatedNeighbor;
    return _PerpendicularAdjustment(
      points: updated,
      moved: true,
      inserted: false,
    );
  }

  return _insertEndpointDirectionStub(
    points: points,
    heading: heading,
    neighbor: neighbor,
    allowExtend: true,
    padding: stubPadding,
    isStart: true,
  );
}

_PerpendicularAdjustment _adjustPerpendicularEnd({
  required List<DrawPoint> points,
  required ArrowBinding binding,
  required Map<String, ElementState> elementsById,
  required double? directionPadding,
  required bool hasArrowhead,
  required List<ElbowFixedSegment> fixedSegments,
  bool? fixedNeighborAxis,
}) {
  if (points.length < 2) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final heading = _resolveBoundHeading(
    binding: binding,
    elementsById: elementsById,
    point: points.last,
  );
  if (heading == null) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final desiredHorizontal = heading.isHorizontal;
  final resolvedPadding = _resolveDirectionPadding(directionPadding);
  final lastIndex = points.length - 1;
  final neighborIndex = lastIndex - 1;
  final neighbor = points[neighborIndex];
  final endPoint = points[lastIndex];
  final stubPadding = _capDirectionPaddingForAxis(
    padding: resolvedPadding,
    endpoint: endPoint,
    heading: heading,
    axis: _resolveFixedAxisLimit(
      points: points,
      fixedSegments: fixedSegments,
      isStart: false,
      heading: heading,
    ),
  );
  final aligned = desiredHorizontal
      ? (neighbor.y - endPoint.y).abs() <= ElbowConstants.dedupThreshold
      : (neighbor.x - endPoint.x).abs() <= ElbowConstants.dedupThreshold;
  final requiredHeading = heading.opposite;
  final directionOk = _directionMatches(neighbor, endPoint, requiredHeading);

  final preserveNeighbor = fixedNeighborAxis != null;
  final canSlideNeighbor = _canSlideFixedNeighbor(
    fixedNeighborAxis: fixedNeighborAxis,
    desiredHorizontal: desiredHorizontal,
  );
  final fixedPadding = _resolveFixedNeighborPadding(hasArrowhead);

  if (preserveNeighbor) {
    if (aligned && directionOk) {
      final adjusted = canSlideNeighbor
          ? _slideEndpointNeighborToPadding(
              points: points,
              heading: heading,
              desiredLength: fixedPadding,
              cornerInserted: false,
              isStart: false,
            )
          : null;
      if (adjusted != null) {
        return adjusted;
      }
      return _PerpendicularAdjustment(
        points: points,
        moved: false,
        inserted: false,
      );
    }
    if (!aligned && directionOk) {
      final inserted = _insertEndpointCorner(
        points: points,
        heading: heading,
        neighbor: neighbor,
        isStart: false,
      );
      final adjusted = canSlideNeighbor
          ? _slideEndpointNeighborToPadding(
              points: inserted.points,
              heading: heading,
              desiredLength: fixedPadding,
              cornerInserted: true,
              isStart: false,
            )
          : null;
      return adjusted ?? inserted;
    }
    if (!directionOk &&
        !desiredHorizontal &&
        fixedNeighborAxis != desiredHorizontal) {
      final snapped = _snapEndPointToFixedAxisAtAnchor(
        points: points,
        neighborIndex: neighborIndex,
        binding: binding,
        elementsById: elementsById,
      );
      if (snapped != null) {
        return snapped;
      }
    }
    if (aligned) {
      if (canSlideNeighbor) {
        final adjusted = _slideEndpointNeighborToPadding(
          points: points,
          heading: heading,
          desiredLength: fixedPadding,
          cornerInserted: false,
          isStart: false,
        );
        if (adjusted != null) {
          return adjusted;
        }
      }
      // Keep the aligned segment when forcing direction would backtrack
      // against a fixed neighbor.
      return _PerpendicularAdjustment(
        points: points,
        moved: false,
        inserted: false,
      );
    }
    return _insertEndpointDirectionStub(
      points: points,
      heading: heading,
      neighbor: neighbor,
      allowExtend: false,
      padding: resolvedPadding,
      isStart: false,
    );
  }

  if (aligned && directionOk) {
    final adjusted = _alignEndpointSegmentLength(
      points: points,
      heading: heading,
      desiredLength: directionPadding,
      isStart: false,
    );
    if (adjusted != null) {
      return adjusted;
    }
    final slid = _slideEndpointCornerToPadding(
      points: points,
      heading: heading,
      desiredLength: directionPadding,
      isStart: false,
    );
    if (slid != null) {
      return slid;
    }
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  if (aligned && !directionOk) {
    final updated = List<DrawPoint>.from(points);
    updated[neighborIndex] = _applyEndpointDirection(
      neighbor,
      endPoint,
      requiredHeading.opposite,
      resolvedPadding,
    );
    return _PerpendicularAdjustment(
      points: updated,
      moved: true,
      inserted: false,
    );
  }

  final prevHorizontal = points.length > 2
      ? ElbowPathUtils.segmentIsHorizontal(points[neighborIndex - 1], neighbor)
      : desiredHorizontal;
  final conflict = prevHorizontal == desiredHorizontal;
  final canShiftDirection =
      points.length <= 2 ||
      (desiredHorizontal ? prevHorizontal : !prevHorizontal);

  if (!conflict && (directionOk || canShiftDirection)) {
    var updatedNeighbor = neighbor;
    if (!aligned) {
      updatedNeighbor = desiredHorizontal
          ? updatedNeighbor.copyWith(y: endPoint.y)
          : updatedNeighbor.copyWith(x: endPoint.x);
    }
    if (!directionOk && canShiftDirection) {
      updatedNeighbor = _applyEndpointDirection(
        updatedNeighbor,
        endPoint,
        requiredHeading.opposite,
        resolvedPadding,
      );
    }
    final updated = List<DrawPoint>.from(points);
    updated[neighborIndex] = updatedNeighbor;
    return _PerpendicularAdjustment(
      points: updated,
      moved: true,
      inserted: false,
    );
  }

  return _insertEndpointDirectionStub(
    points: points,
    heading: heading,
    neighbor: neighbor,
    allowExtend: true,
    padding: stubPadding,
    isStart: false,
  );
}

ElbowHeading? _resolveBoundHeading({
  required ArrowBinding binding,
  required Map<String, ElementState> elementsById,
  required DrawPoint point,
}) {
  final element = elementsById[binding.elementId];
  if (element == null) {
    return null;
  }
  final bounds = SelectionCalculator.computeElementWorldAabb(element);
  final anchor = ArrowBindingUtils.resolveElbowAnchorPoint(
    binding: binding,
    target: element,
  );
  return ElbowGeometry.headingForPointOnBounds(bounds, anchor ?? point);
}

bool _directionMatches(DrawPoint from, DrawPoint to, ElbowHeading heading) =>
    switch (heading) {
      ElbowHeading.right => to.x - from.x > ElbowConstants.dedupThreshold,
      ElbowHeading.left => from.x - to.x > ElbowConstants.dedupThreshold,
      ElbowHeading.down => to.y - from.y > ElbowConstants.dedupThreshold,
      ElbowHeading.up => from.y - to.y > ElbowConstants.dedupThreshold,
    };

DrawPoint _applyEndpointDirection(
  DrawPoint neighbor,
  DrawPoint endpoint,
  ElbowHeading heading,
  double padding,
) => switch (heading) {
  ElbowHeading.right =>
    neighbor.x > endpoint.x + padding
        ? neighbor
        : neighbor.copyWith(x: endpoint.x + padding),
  ElbowHeading.left =>
    neighbor.x < endpoint.x - padding
        ? neighbor
        : neighbor.copyWith(x: endpoint.x - padding),
  ElbowHeading.down =>
    neighbor.y > endpoint.y + padding
        ? neighbor
        : neighbor.copyWith(y: endpoint.y + padding),
  ElbowHeading.up =>
    neighbor.y < endpoint.y - padding
        ? neighbor
        : neighbor.copyWith(y: endpoint.y - padding),
};

bool _canSlideFixedNeighbor({
  required bool? fixedNeighborAxis,
  required bool desiredHorizontal,
}) => fixedNeighborAxis != null && fixedNeighborAxis == desiredHorizontal;

double _resolveFixedNeighborPadding(bool hasArrowhead) =>
    ElbowSpacing.fixedNeighborPadding(hasArrowhead: hasArrowhead);

_PerpendicularAdjustment? _slideEndpointNeighborToPadding({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double? desiredLength,
  required bool cornerInserted,
  required bool isStart,
}) {
  if (points.length < 3 ||
      desiredLength == null ||
      !desiredLength.isFinite ||
      desiredLength <= ElbowConstants.dedupThreshold) {
    return null;
  }

  final lastIndex = points.length - 1;
  final neighborIndex = isStart
      ? (cornerInserted ? 2 : 1)
      : (cornerInserted ? lastIndex - 2 : lastIndex - 1);
  if (isStart) {
    if (neighborIndex + 1 >= points.length) {
      return null;
    }
  } else {
    if (neighborIndex <= 0 || neighborIndex >= lastIndex) {
      return null;
    }
  }

  final endpoint = isStart ? points.first : points.last;
  final neighbor = points[neighborIndex];
  final reference = isStart
      ? points[neighborIndex + 1]
      : points[neighborIndex - 1];
  final target = _offsetPoint(endpoint, heading, desiredLength);
  final updatedNeighbor = heading.isHorizontal
      ? neighbor.copyWith(x: target.x)
      : neighbor.copyWith(y: target.y);
  final originalDelta = heading.isHorizontal
      ? (isStart ? reference.x - neighbor.x : neighbor.x - reference.x)
      : (isStart ? reference.y - neighbor.y : neighbor.y - reference.y);
  final newDelta = heading.isHorizontal
      ? (isStart
            ? reference.x - updatedNeighbor.x
            : updatedNeighbor.x - reference.x)
      : (isStart
            ? reference.y - updatedNeighbor.y
            : updatedNeighbor.y - reference.y);
  final originalLength = originalDelta.abs();
  final newLength = newDelta.abs();
  if (originalDelta.abs() <= ElbowConstants.dedupThreshold ||
      newDelta.abs() <= ElbowConstants.dedupThreshold ||
      originalDelta.sign != newDelta.sign) {
    return null;
  }
  if (newLength <= originalLength * 0.5) {
    return null;
  }
  if (heading.isHorizontal) {
    if ((updatedNeighbor.x - neighbor.x).abs() <=
        ElbowConstants.dedupThreshold) {
      return null;
    }
  } else if ((updatedNeighbor.y - neighbor.y).abs() <=
      ElbowConstants.dedupThreshold) {
    return null;
  }
  final updated = List<DrawPoint>.from(points);
  updated[neighborIndex] = updatedNeighbor;
  if (cornerInserted) {
    final cornerIndex = isStart ? 1 : lastIndex - 1;
    final corner = updated[cornerIndex];
    updated[cornerIndex] = heading.isHorizontal
        ? corner.copyWith(x: updatedNeighbor.x)
        : corner.copyWith(y: updatedNeighbor.y);
  }
  return _PerpendicularAdjustment(
    points: updated,
    moved: true,
    inserted: cornerInserted,
  );
}

_PerpendicularAdjustment _insertEndpointDirectionStub({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required DrawPoint neighbor,
  required bool allowExtend,
  required double padding,
  required bool isStart,
}) {
  if (points.length < 2) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final endpoint = isStart ? points.first : points.last;
  final stub = _offsetPoint(endpoint, heading, padding);
  final connector = heading.isHorizontal
      ? DrawPoint(x: stub.x, y: neighbor.y)
      : DrawPoint(x: neighbor.x, y: stub.y);

  final updated = List<DrawPoint>.from(points);
  final neighborIndex = isStart ? 1 : updated.length - 2;
  var insertIndex = isStart ? 1 : updated.length - 1;
  var moved = false;
  var inserted = false;

  if (allowExtend && points.length > 2) {
    final adjacent = isStart ? points[2] : points[points.length - 3];
    final adjacentHorizontal = ElbowPathUtils.segmentIsHorizontal(
      neighbor,
      adjacent,
    );
    final connectorHorizontal =
        (connector.y - neighbor.y).abs() <= ElbowConstants.dedupThreshold;
    final connectorVertical =
        (connector.x - neighbor.x).abs() <= ElbowConstants.dedupThreshold;
    final collinear = adjacentHorizontal
        ? connectorHorizontal
        : connectorVertical;
    if (collinear) {
      updated[neighborIndex] = connector;
      moved = true;
    }
  }

  if (isStart) {
    if (ElbowGeometry.manhattanDistance(stub, endpoint) >
        ElbowConstants.dedupThreshold) {
      updated.insert(insertIndex, stub);
      insertIndex++;
      inserted = true;
    }
    if (!moved &&
        ElbowGeometry.manhattanDistance(connector, neighbor) >
            ElbowConstants.dedupThreshold &&
        ElbowGeometry.manhattanDistance(connector, stub) >
            ElbowConstants.dedupThreshold) {
      updated.insert(insertIndex, connector);
      inserted = true;
    }
  } else {
    if (!moved &&
        ElbowGeometry.manhattanDistance(connector, neighbor) >
            ElbowConstants.dedupThreshold &&
        ElbowGeometry.manhattanDistance(connector, stub) >
            ElbowConstants.dedupThreshold) {
      updated.insert(insertIndex, connector);
      insertIndex++;
      inserted = true;
    }
    if (ElbowGeometry.manhattanDistance(stub, endpoint) >
        ElbowConstants.dedupThreshold) {
      updated.insert(insertIndex, stub);
      inserted = true;
    }
  }

  return _PerpendicularAdjustment(
    points: updated,
    moved: moved,
    inserted: inserted,
  );
}

_PerpendicularAdjustment _insertEndpointCorner({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required DrawPoint neighbor,
  required bool isStart,
}) {
  if (points.length < 2) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final endpoint = isStart ? points.first : points.last;
  final corner = heading.isHorizontal
      ? DrawPoint(x: neighbor.x, y: endpoint.y)
      : DrawPoint(x: endpoint.x, y: neighbor.y);

  if (ElbowGeometry.manhattanDistance(corner, endpoint) <=
          ElbowConstants.dedupThreshold ||
      ElbowGeometry.manhattanDistance(corner, neighbor) <=
          ElbowConstants.dedupThreshold) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final updated = List<DrawPoint>.from(points);
  final insertIndex = isStart ? 1 : updated.length - 1;
  updated.insert(insertIndex, corner);
  return _PerpendicularAdjustment(
    points: updated,
    moved: false,
    inserted: true,
  );
}

_PerpendicularAdjustment? _snapEndPointToFixedAxisAtAnchor({
  required List<DrawPoint> points,
  required int neighborIndex,
  required ArrowBinding binding,
  required Map<String, ElementState> elementsById,
}) {
  if (neighborIndex <= 0 || neighborIndex >= points.length - 1) {
    return null;
  }
  final element = elementsById[binding.elementId];
  if (element == null) {
    return null;
  }
  final anchor = ArrowBindingUtils.resolveElbowAnchorPoint(
    binding: binding,
    target: element,
  );
  if (anchor == null || !anchor.x.isFinite || !anchor.y.isFinite) {
    return null;
  }
  final neighbor = points[neighborIndex];
  if ((anchor.x - neighbor.x).abs() <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final slid = _slideRunForward(
    points: points,
    startIndex: neighborIndex,
    horizontal: false,
    target: anchor.x,
  );
  if (!slid.moved) {
    return null;
  }
  return _PerpendicularAdjustment(
    points: slid.points,
    moved: true,
    inserted: false,
  );
}

({List<DrawPoint> points, bool moved}) _slideRunForward({
  required List<DrawPoint> points,
  required int startIndex,
  required bool horizontal,
  required double target,
}) => _slideRun(
  points: points,
  startIndex: startIndex,
  horizontal: horizontal,
  target: target,
  direction: 1,
);

DrawPoint _offsetPoint(
  DrawPoint point,
  ElbowHeading heading,
  double distance,
) => DrawPoint(
  x: point.x + heading.dx * distance,
  y: point.y + heading.dy * distance,
);

double? _resolveFixedAxisLimit({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  required bool isStart,
  required ElbowHeading heading,
}) {
  if (points.length < 2 || fixedSegments.isEmpty) {
    return null;
  }
  final wantHorizontal = !heading.isHorizontal;
  final ordered = isStart ? fixedSegments : fixedSegments.reversed;
  for (final segment in ordered) {
    final index = segment.index;
    if (index <= 0 || index >= points.length) {
      continue;
    }
    final start = points[index - 1];
    final end = points[index];
    final isHorizontal = ElbowPathUtils.segmentIsHorizontal(start, end);
    if (isHorizontal != wantHorizontal) {
      continue;
    }
    return isHorizontal
        ? (start.y + end.y) / 2
        : (start.x + end.x) / 2;
  }
  return null;
}

double _capDirectionPaddingForAxis({
  required double padding,
  required DrawPoint endpoint,
  required ElbowHeading heading,
  required double? axis,
}) {
  if (!padding.isFinite || padding <= 0) {
    return padding;
  }
  if (axis == null || !axis.isFinite) {
    return padding;
  }
  double maxPadding;
  switch (heading) {
    case ElbowHeading.left:
      maxPadding = endpoint.x - axis;
    case ElbowHeading.right:
      maxPadding = axis - endpoint.x;
    case ElbowHeading.up:
      maxPadding = endpoint.y - axis;
    case ElbowHeading.down:
      maxPadding = axis - endpoint.y;
  }
  if (maxPadding <= ElbowConstants.dedupThreshold) {
    return padding;
  }
  return math.min(padding, maxPadding);
}
