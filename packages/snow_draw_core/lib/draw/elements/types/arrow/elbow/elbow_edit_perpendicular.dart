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
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
  }
  if (startBinding == null && endBinding == null) {
    return _FixedSegmentPathResult(points: points, fixedSegments: fixedSegments);
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
    final fixedNeighborAxis = _fixedSegmentIsHorizontal(updatedFixedSegments, 2);
    final adjustment = _adjustPerpendicularStart(
      points: worldPoints,
      binding: startBinding,
      elementsById: elementsById,
      directionPadding: baselinePadding.start,
      fixedNeighborAxis: fixedNeighborAxis,
      hasArrowhead: startArrowhead != ArrowheadStyle.none,
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
  final resolved = desired;
  if (resolved == null || !resolved.isFinite) {
    return ElbowConstants.directionFixPadding;
  }
  if (resolved <= ElbowConstants.dedupThreshold) {
    return ElbowConstants.directionFixPadding;
  }
  return math.max(ElbowConstants.directionFixPadding, resolved);
}

_PerpendicularAdjustment? _alignStartSegmentLength({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double? desiredLength,
}) {
  if (points.length < 2 ||
      desiredLength == null ||
      !desiredLength.isFinite ||
      desiredLength <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final desiredHorizontal = heading.isHorizontal;
  if (points.length > 2) {
    final nextHorizontal = ElbowGeometry.isHorizontal(points[1], points[2]);
    if (nextHorizontal != desiredHorizontal) {
      return null;
    }
  }
  final start = points.first;
  final neighbor = points[1];
  final target = _offsetPoint(start, heading, desiredLength);
  final delta = desiredHorizontal
      ? (neighbor.x - target.x).abs()
      : (neighbor.y - target.y).abs();
  if (delta <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final updated = List<DrawPoint>.from(points);
  updated[1] = desiredHorizontal
      ? neighbor.copyWith(x: target.x)
      : neighbor.copyWith(y: target.y);
  return _PerpendicularAdjustment(
    points: updated,
    moved: true,
    inserted: false,
  );
}

_PerpendicularAdjustment? _slideStartCornerToPadding({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double? desiredLength,
}) {
  if (points.length < 4 ||
      desiredLength == null ||
      !desiredLength.isFinite ||
      desiredLength <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final desiredHorizontal = heading.isHorizontal;
  final start = points.first;
  final neighbor = points[1];
  final corner = points[2];
  final target = _offsetPoint(start, heading, desiredLength);

  if (desiredHorizontal) {
    if ((neighbor.y - start.y).abs() > ElbowConstants.dedupThreshold) {
      return null;
    }
    if ((corner.x - neighbor.x).abs() > ElbowConstants.dedupThreshold) {
      return null;
    }
    final next = points[3];
    if ((next.y - corner.y).abs() > ElbowConstants.dedupThreshold) {
      return null;
    }
    final originalDelta = next.x - corner.x;
    final newDelta = next.x - target.x;
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
    updated[1] = neighbor.copyWith(x: target.x);
    updated[2] = corner.copyWith(x: target.x);
    return _PerpendicularAdjustment(
      points: updated,
      moved: true,
      inserted: false,
    );
  }

  if ((neighbor.x - start.x).abs() > ElbowConstants.dedupThreshold) {
    return null;
  }
  if ((corner.y - neighbor.y).abs() > ElbowConstants.dedupThreshold) {
    return null;
  }
  final next = points[3];
  if ((next.x - corner.x).abs() > ElbowConstants.dedupThreshold) {
    return null;
  }
  final originalDelta = next.y - corner.y;
  final newDelta = next.y - target.y;
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
  updated[1] = neighbor.copyWith(y: target.y);
  updated[2] = corner.copyWith(y: target.y);
  return _PerpendicularAdjustment(
    points: updated,
    moved: true,
    inserted: false,
  );
}

_PerpendicularAdjustment? _alignEndSegmentLength({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double? desiredLength,
}) {
  if (points.length < 2 ||
      desiredLength == null ||
      !desiredLength.isFinite ||
      desiredLength <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final desiredHorizontal = heading.isHorizontal;
  final neighborIndex = points.length - 2;
  if (points.length > 2) {
    final prev = points[neighborIndex - 1];
    final prevHorizontal = ElbowGeometry.isHorizontal(
      prev,
      points[neighborIndex],
    );
    if (prevHorizontal != desiredHorizontal) {
      return null;
    }
  }
  final endPoint = points.last;
  final neighbor = points[neighborIndex];
  final target = _offsetPoint(endPoint, heading, desiredLength);
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

_PerpendicularAdjustment? _slideEndCornerToPadding({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double? desiredLength,
}) {
  if (points.length < 4 ||
      desiredLength == null ||
      !desiredLength.isFinite ||
      desiredLength <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final desiredHorizontal = heading.isHorizontal;
  final lastIndex = points.length - 1;
  final neighborIndex = lastIndex - 1;
  final cornerIndex = neighborIndex - 1;
  if (cornerIndex < 1) {
    return null;
  }
  final endPoint = points[lastIndex];
  final neighbor = points[neighborIndex];
  final corner = points[cornerIndex];
  final target = _offsetPoint(endPoint, heading, desiredLength);

  if (desiredHorizontal) {
    if ((neighbor.y - endPoint.y).abs() > ElbowConstants.dedupThreshold) {
      return null;
    }
    if ((corner.x - neighbor.x).abs() > ElbowConstants.dedupThreshold) {
      return null;
    }
    final prev = points[cornerIndex - 1];
    if ((prev.y - corner.y).abs() > ElbowConstants.dedupThreshold) {
      return null;
    }
    final originalDelta = corner.x - prev.x;
    final newDelta = target.x - prev.x;
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

  if ((neighbor.x - endPoint.x).abs() > ElbowConstants.dedupThreshold) {
    return null;
  }
  if ((corner.y - neighbor.y).abs() > ElbowConstants.dedupThreshold) {
    return null;
  }
  final prev = points[cornerIndex - 1];
  if ((prev.x - corner.x).abs() > ElbowConstants.dedupThreshold) {
    return null;
  }
  final originalDelta = corner.y - prev.y;
  final newDelta = target.y - prev.y;
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
  bool? fixedNeighborAxis,
  required bool hasArrowhead,
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
          ? _slideStartNeighborToPadding(
              points: points,
              heading: heading,
              desiredLength: fixedPadding,
              cornerInserted: false,
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
      final inserted = _insertStartCorner(
        points: points,
        heading: heading,
        neighbor: neighbor,
      );
      final adjusted = canSlideNeighbor
          ? _slideStartNeighborToPadding(
              points: inserted.points,
              heading: heading,
              desiredLength: fixedPadding,
              cornerInserted: true,
            )
          : null;
      return adjusted ?? inserted;
    }
    if (aligned) {
      if (canSlideNeighbor) {
        final adjusted = _slideStartNeighborToPadding(
          points: points,
          heading: heading,
          desiredLength: fixedPadding,
          cornerInserted: false,
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
    return _insertStartDirectionStub(
      points: points,
      heading: heading,
      neighbor: neighbor,
      allowExtend: false,
      padding: resolvedPadding,
    );
  }

  if (aligned && directionOk) {
    final adjusted = _alignStartSegmentLength(
      points: points,
      heading: heading,
      desiredLength: directionPadding,
    );
    if (adjusted != null) {
      return adjusted;
    }
    final slid = _slideStartCornerToPadding(
      points: points,
      heading: heading,
      desiredLength: directionPadding,
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
    updated[1] = _applyStartDirection(
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
      ? ElbowGeometry.isHorizontal(neighbor, points[2])
      : desiredHorizontal;
  final conflict = nextHorizontal == desiredHorizontal;
  final canShiftDirection =
      points.length <= 2 || (desiredHorizontal ? nextHorizontal : !nextHorizontal);

  if (!conflict && (directionOk || canShiftDirection)) {
    var updatedNeighbor = neighbor;
    if (!aligned) {
      updatedNeighbor = desiredHorizontal
          ? updatedNeighbor.copyWith(y: start.y)
          : updatedNeighbor.copyWith(x: start.x);
    }
    if (!directionOk && canShiftDirection) {
      updatedNeighbor = _applyStartDirection(
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

  return _insertStartDirectionStub(
    points: points,
    heading: heading,
    neighbor: neighbor,
    allowExtend: true,
    padding: resolvedPadding,
  );
}

_PerpendicularAdjustment _adjustPerpendicularEnd({
  required List<DrawPoint> points,
  required ArrowBinding binding,
  required Map<String, ElementState> elementsById,
  required double? directionPadding,
  bool? fixedNeighborAxis,
  required bool hasArrowhead,
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
          ? _slideEndNeighborToPadding(
              points: points,
              heading: heading,
              desiredLength: fixedPadding,
              cornerInserted: false,
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
      final inserted = _insertEndCorner(
        points: points,
        heading: heading,
        neighbor: neighbor,
      );
      final adjusted = canSlideNeighbor
          ? _slideEndNeighborToPadding(
              points: inserted.points,
              heading: heading,
              desiredLength: fixedPadding,
              cornerInserted: true,
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
        final adjusted = _slideEndNeighborToPadding(
          points: points,
          heading: heading,
          desiredLength: fixedPadding,
          cornerInserted: false,
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
    return _insertEndDirectionStub(
      points: points,
      heading: heading,
      neighbor: neighbor,
      allowExtend: false,
      padding: resolvedPadding,
    );
  }

  if (aligned && directionOk) {
    final adjusted = _alignEndSegmentLength(
      points: points,
      heading: heading,
      desiredLength: directionPadding,
    );
    if (adjusted != null) {
      return adjusted;
    }
    final slid = _slideEndCornerToPadding(
      points: points,
      heading: heading,
      desiredLength: directionPadding,
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
    updated[neighborIndex] = _applyEndDirection(
      neighbor,
      endPoint,
      requiredHeading,
      resolvedPadding,
    );
    return _PerpendicularAdjustment(
      points: updated,
      moved: true,
      inserted: false,
    );
  }

  final prevHorizontal = points.length > 2
      ? ElbowGeometry.isHorizontal(points[neighborIndex - 1], neighbor)
      : desiredHorizontal;
  final conflict = prevHorizontal == desiredHorizontal;
  final canShiftDirection =
      points.length <= 2 || (desiredHorizontal ? prevHorizontal : !prevHorizontal);

  if (!conflict && (directionOk || canShiftDirection)) {
    var updatedNeighbor = neighbor;
    if (!aligned) {
      updatedNeighbor = desiredHorizontal
          ? updatedNeighbor.copyWith(y: endPoint.y)
          : updatedNeighbor.copyWith(x: endPoint.x);
    }
    if (!directionOk && canShiftDirection) {
      updatedNeighbor = _applyEndDirection(
        updatedNeighbor,
        endPoint,
        requiredHeading,
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

  return _insertEndDirectionStub(
    points: points,
    heading: heading,
    neighbor: neighbor,
    allowExtend: true,
    padding: resolvedPadding,
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

bool _directionMatches(
  DrawPoint from,
  DrawPoint to,
  ElbowHeading heading,
) => switch (heading) {
  ElbowHeading.right => to.x - from.x > ElbowConstants.dedupThreshold,
  ElbowHeading.left => from.x - to.x > ElbowConstants.dedupThreshold,
  ElbowHeading.down => to.y - from.y > ElbowConstants.dedupThreshold,
  ElbowHeading.up => from.y - to.y > ElbowConstants.dedupThreshold,
};

DrawPoint _applyStartDirection(
  DrawPoint neighbor,
  DrawPoint start,
  ElbowHeading heading,
  double padding,
) => switch (heading) {
  ElbowHeading.right => neighbor.x > start.x + padding
      ? neighbor
      : neighbor.copyWith(x: start.x + padding),
  ElbowHeading.left => neighbor.x < start.x - padding
      ? neighbor
      : neighbor.copyWith(x: start.x - padding),
  ElbowHeading.down => neighbor.y > start.y + padding
      ? neighbor
      : neighbor.copyWith(y: start.y + padding),
  ElbowHeading.up => neighbor.y < start.y - padding
      ? neighbor
      : neighbor.copyWith(y: start.y - padding),
};

DrawPoint _applyEndDirection(
  DrawPoint neighbor,
  DrawPoint endPoint,
  ElbowHeading requiredHeading,
  double padding,
) => switch (requiredHeading) {
  ElbowHeading.right => neighbor.x < endPoint.x - padding
      ? neighbor
      : neighbor.copyWith(x: endPoint.x - padding),
  ElbowHeading.left => neighbor.x > endPoint.x + padding
      ? neighbor
      : neighbor.copyWith(x: endPoint.x + padding),
  ElbowHeading.down => neighbor.y < endPoint.y - padding
      ? neighbor
      : neighbor.copyWith(y: endPoint.y - padding),
  ElbowHeading.up => neighbor.y > endPoint.y + padding
      ? neighbor
      : neighbor.copyWith(y: endPoint.y + padding),
};

bool _canSlideFixedNeighbor({
  required bool? fixedNeighborAxis,
  required bool desiredHorizontal,
}) => fixedNeighborAxis != null && fixedNeighborAxis == desiredHorizontal;

double _resolveFixedNeighborPadding(bool hasArrowhead) {
  final gap = ArrowBindingUtils.elbowBindingGapBase *
      (hasArrowhead
          ? ArrowBindingUtils.elbowArrowheadGapMultiplier
          : ElbowConstants.elbowNoArrowheadGapMultiplier);
  final padding = ElbowConstants.basePadding - gap;
  if (!padding.isFinite || padding <= ElbowConstants.dedupThreshold) {
    return ElbowConstants.directionFixPadding;
  }
  return math.max(ElbowConstants.directionFixPadding, padding);
}

_PerpendicularAdjustment? _slideEndNeighborToPadding({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double? desiredLength,
  required bool cornerInserted,
}) {
  if (points.length < 3 ||
      desiredLength == null ||
      !desiredLength.isFinite ||
      desiredLength <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final neighborIndex = cornerInserted ? points.length - 3 : points.length - 2;
  final endIndex = points.length - 1;
  if (neighborIndex <= 0 || neighborIndex >= endIndex) {
    return null;
  }
  final startIndex = neighborIndex - 1;
  final start = points[startIndex];
  final neighbor = points[neighborIndex];
  final endPoint = points[endIndex];
  final target = _offsetPoint(endPoint, heading, desiredLength);
  final updatedNeighbor = heading.isHorizontal
      ? neighbor.copyWith(x: target.x)
      : neighbor.copyWith(y: target.y);
  final originalDelta = heading.isHorizontal
      ? neighbor.x - start.x
      : neighbor.y - start.y;
  final newDelta = heading.isHorizontal
      ? updatedNeighbor.x - start.x
      : updatedNeighbor.y - start.y;
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
    final cornerIndex = points.length - 2;
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

_PerpendicularAdjustment? _slideStartNeighborToPadding({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double? desiredLength,
  required bool cornerInserted,
}) {
  if (points.length < 3 ||
      desiredLength == null ||
      !desiredLength.isFinite ||
      desiredLength <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final neighborIndex = cornerInserted ? 2 : 1;
  if (neighborIndex + 1 >= points.length) {
    return null;
  }
  final neighbor = points[neighborIndex];
  final endOfFixed = points[neighborIndex + 1];
  final start = points.first;
  final target = _offsetPoint(start, heading, desiredLength);
  final updatedNeighbor = heading.isHorizontal
      ? neighbor.copyWith(x: target.x)
      : neighbor.copyWith(y: target.y);
  final originalDelta = heading.isHorizontal
      ? endOfFixed.x - neighbor.x
      : endOfFixed.y - neighbor.y;
  final newDelta = heading.isHorizontal
      ? endOfFixed.x - updatedNeighbor.x
      : endOfFixed.y - updatedNeighbor.y;
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
    final cornerIndex = 1;
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

_PerpendicularAdjustment _insertStartDirectionStub({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required DrawPoint neighbor,
  required bool allowExtend,
  required double padding,
}) {
  if (points.length < 2) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final start = points.first;
  final stub = _offsetPoint(start, heading, padding);
  final connector = heading.isHorizontal
      ? DrawPoint(x: stub.x, y: neighbor.y)
      : DrawPoint(x: neighbor.x, y: stub.y);

  final updated = List<DrawPoint>.from(points);
  var insertIndex = 1;
  var moved = false;
  var inserted = false;

  if (allowExtend && points.length > 2) {
    final next = points[2];
    final nextHorizontal = ElbowGeometry.isHorizontal(neighbor, next);
    final connectorHorizontal =
        (connector.y - neighbor.y).abs() <= ElbowConstants.dedupThreshold;
    final connectorVertical =
        (connector.x - neighbor.x).abs() <= ElbowConstants.dedupThreshold;
    final collinear =
        nextHorizontal ? connectorHorizontal : connectorVertical;
    if (collinear) {
      updated[1] = connector;
      moved = true;
    }
  }

  if (ElbowGeometry.manhattanDistance(stub, start) >
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

  return _PerpendicularAdjustment(
    points: updated,
    moved: moved,
    inserted: inserted,
  );
}

_PerpendicularAdjustment _insertEndDirectionStub({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required DrawPoint neighbor,
  required bool allowExtend,
  required double padding,
}) {
  if (points.length < 2) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final endPoint = points.last;
  final stub = _offsetPoint(endPoint, heading, padding);
  final connector = heading.isHorizontal
      ? DrawPoint(x: stub.x, y: neighbor.y)
      : DrawPoint(x: neighbor.x, y: stub.y);

  final updated = List<DrawPoint>.from(points);
  final neighborIndex = updated.length - 2;
  var insertIndex = updated.length - 1;
  var moved = false;
  var inserted = false;

  if (allowExtend && points.length > 2) {
    final prev = points[points.length - 3];
    final prevHorizontal = ElbowGeometry.isHorizontal(prev, neighbor);
    final connectorHorizontal =
        (connector.y - neighbor.y).abs() <= ElbowConstants.dedupThreshold;
    final connectorVertical =
        (connector.x - neighbor.x).abs() <= ElbowConstants.dedupThreshold;
    final collinear =
        prevHorizontal ? connectorHorizontal : connectorVertical;
    if (collinear) {
      updated[neighborIndex] = connector;
      moved = true;
    }
  }

  if (!moved &&
      ElbowGeometry.manhattanDistance(connector, neighbor) >
          ElbowConstants.dedupThreshold &&
      ElbowGeometry.manhattanDistance(connector, stub) >
          ElbowConstants.dedupThreshold) {
    updated.insert(insertIndex, connector);
    insertIndex++;
    inserted = true;
  }
  if (ElbowGeometry.manhattanDistance(stub, endPoint) >
      ElbowConstants.dedupThreshold) {
    updated.insert(insertIndex, stub);
    inserted = true;
  }

  return _PerpendicularAdjustment(
    points: updated,
    moved: moved,
    inserted: inserted,
  );
}

_PerpendicularAdjustment _insertStartCorner({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required DrawPoint neighbor,
}) {
  if (points.length < 2) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final start = points.first;
  final corner = heading.isHorizontal
      ? DrawPoint(x: neighbor.x, y: start.y)
      : DrawPoint(x: start.x, y: neighbor.y);

  if (ElbowGeometry.manhattanDistance(corner, start) <=
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
  updated.insert(1, corner);
  return _PerpendicularAdjustment(
    points: updated,
    moved: false,
    inserted: true,
  );
}

_PerpendicularAdjustment _insertEndCorner({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required DrawPoint neighbor,
}) {
  if (points.length < 2) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final endPoint = points.last;
  final corner = heading.isHorizontal
      ? DrawPoint(x: neighbor.x, y: endPoint.y)
      : DrawPoint(x: endPoint.x, y: neighbor.y);

  if (ElbowGeometry.manhattanDistance(corner, neighbor) <=
          ElbowConstants.dedupThreshold ||
      ElbowGeometry.manhattanDistance(corner, endPoint) <=
          ElbowConstants.dedupThreshold) {
    return _PerpendicularAdjustment(
      points: points,
      moved: false,
      inserted: false,
    );
  }

  final updated = List<DrawPoint>.from(points);
  updated.insert(updated.length - 1, corner);
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

DrawPoint _offsetPoint(
  DrawPoint point,
  ElbowHeading heading,
  double distance,
) => DrawPoint(
  x: point.x + heading.dx * distance,
  y: point.y + heading.dy * distance,
);
