part of 'elbow_editing.dart';

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
  if (points.length < 2 || (startBinding == null && endBinding == null)) {
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
  var updatedFixed = fixedSegments;
  var localPoints = points;
  final baselinePadding = () {
    if (points.length < 2 ||
        (startBinding == null && endBinding == null)) {
      return (start: null as double?, end: null as double?);
    }
    final routed = routeElbowArrow(
      start: space.toWorld(points.first),
      end: space.toWorld(points.last),
      startBinding: startBinding,
      endBinding: endBinding,
      elementsById: elementsById,
      startArrowhead: startArrowhead,
      endArrowhead: endArrowhead,
    ).points;
    if (routed.length < 3) {
      return (start: null as double?, end: null as double?);
    }
    double? len(DrawPoint a, DrawPoint b) {
      final d = ElbowGeometry.manhattanDistance(a, b);
      return d.isFinite && d > ElbowConstants.dedupThreshold ? d : null;
    }

    return (
      start: startBinding == null ? null : len(routed.first, routed[1]),
      end: endBinding == null
          ? null
          : len(routed[routed.length - 2], routed.last),
    );
  }();

  for (final isStart in const [true, false]) {
    final binding = isStart ? startBinding : endBinding;
    if (binding == null) {
      continue;
    }
    bool? neighborAxis;
    if (isStart) {
      neighborAxis = _fixedSegmentIsHorizontal(updatedFixed, 2);
    } else {
      final ni = math.max(2, localPoints.length - 2);
      neighborAxis =
          _fixedSegmentIsHorizontal(updatedFixed, ni) ??
          (_endpointHasCorner(points: localPoints, isStart: false)
              ? _fixedSegmentIsHorizontal(updatedFixed, ni - 1)
              : null);
    }
    final adjustment = _adjustPerpendicularEndpoint(
      points: worldPoints,
      binding: binding,
      elementsById: elementsById,
      directionPadding: isStart ? baselinePadding.start : baselinePadding.end,
      fixedNeighborAxis: neighborAxis,
      hasArrowhead:
          (isStart ? startArrowhead : endArrowhead) != ArrowheadStyle.none,
      fixedSegments: updatedFixed,
      isStart: isStart,
    );
    worldPoints = adjustment.points;
    if (adjustment.inserted || adjustment.moved) {
      localPoints = worldPoints.map(space.fromWorld).toList(growable: false);
      updatedFixed = adjustment.inserted
          ? _reindexFixedSegments(localPoints, updatedFixed)
          : _syncFixedSegmentsToPoints(localPoints, updatedFixed);
    }
  }

  if (identical(localPoints, points) && worldPoints.length != points.length) {
    localPoints = worldPoints.map(space.fromWorld).toList(growable: false);
    updatedFixed = _reindexFixedSegments(localPoints, updatedFixed);
  }
  return _mergeFixedSegmentsWithCollinearNeighbors(
    points: localPoints,
    fixedSegments: updatedFixed,
    allowDirectionFlip: true,
  );
}

bool _endpointHasCorner({
  required List<DrawPoint> points,
  required bool isStart,
}) {
  if (points.length < 3) {
    return false;
  }
  final a = isStart ? points[0] : points[points.length - 3];
  final b = isStart ? points[1] : points[points.length - 2];
  final c = isStart ? points[2] : points[points.length - 1];
  final abHorizontal = (a.y - b.y).abs() <= ElbowConstants.dedupThreshold;
  final bcHorizontal = (b.y - c.y).abs() <= ElbowConstants.dedupThreshold;
  return abHorizontal != bcHorizontal;
}

/// Slides one or two points (neighbor and optional corner) along the
/// heading axis so the first segment reaches [desiredLength].
///
/// Returns `null` when the slide is invalid (would collapse or reverse
/// an adjacent segment, or the path is too short).
///
/// [neighborIndex] and [cornerIndex] identify which points to move.
/// [referenceIndex] is the point on the far side of the neighbor used
/// to validate that the slide preserves segment direction.
_PerpendicularAdjustment? _slideAlongHeadingAxis({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double desiredLength,
  required bool isStart,
  required int neighborIndex,
  int? cornerIndex,
  int? referenceIndex,
}) {
  if (points.length < 2 ||
      neighborIndex < 0 ||
      neighborIndex >= points.length) {
    return null;
  }
  final h = heading.isHorizontal;
  double main(DrawPoint p) => h ? p.x : p.y;

  final endpoint = isStart ? points.first : points.last;
  final neighbor = points[neighborIndex];
  final target = ElbowGeometry.offsetPoint(endpoint, heading, desiredLength);
  final targetMain = main(target);
  final neighborMain = main(neighbor);
  if ((neighborMain - targetMain).abs() <= ElbowConstants.dedupThreshold) {
    return null;
  }

  // Validate against the reference point (the segment beyond the
  // neighbor) to ensure the slide doesn't collapse or reverse it.
  if (referenceIndex != null &&
      referenceIndex >= 0 &&
      referenceIndex < points.length) {
    final reference = points[referenceIndex];
    final originalDelta = isStart
        ? main(reference) - main(neighbor)
        : main(neighbor) - main(reference);
    final newDelta = isStart
        ? main(reference) - targetMain
        : targetMain - main(reference);
    if (originalDelta.abs() <= ElbowConstants.dedupThreshold ||
        newDelta.abs() <= ElbowConstants.dedupThreshold ||
        originalDelta.sign != newDelta.sign ||
        newDelta.abs() <= originalDelta.abs() * 0.5) {
      return null;
    }
  }

  final updated = List<DrawPoint>.from(points);
  updated[neighborIndex] = h
      ? neighbor.copyWith(x: targetMain)
      : neighbor.copyWith(y: targetMain);
  if (cornerIndex != null && cornerIndex >= 0 && cornerIndex < points.length) {
    final corner = points[cornerIndex];
    updated[cornerIndex] = h
        ? corner.copyWith(x: targetMain)
        : corner.copyWith(y: targetMain);
  }
  return _PerpendicularAdjustment(
    points: updated,
    moved: true,
    inserted: cornerIndex != null,
  );
}

_PerpendicularAdjustment? _slideEndpointToPadding({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double? desiredLength,
  required bool isStart,
  int? cornerIndex,
}) {
  if (desiredLength == null ||
      !desiredLength.isFinite ||
      desiredLength <= ElbowConstants.dedupThreshold) {
    return null;
  }
  final h = heading.isHorizontal;
  final lastIndex = points.length - 1;
  final neighborIndex = isStart ? 1 : lastIndex - 1;

  if (cornerIndex == null) {
    // Simple segment-length mode: adjacent axis must match heading.
    if (points.length > 2) {
      final adjacentIndex = isStart ? neighborIndex + 1 : neighborIndex - 1;
      if (adjacentIndex >= 0 && adjacentIndex < points.length) {
        if (ElbowGeometry.segmentIsHorizontal(
              points[neighborIndex],
              points[adjacentIndex],
            ) !=
            h) {
          return null;
        }
      }
    }
    return _slideAlongHeadingAxis(
      points: points,
      heading: heading,
      desiredLength: desiredLength,
      isStart: isStart,
      neighborIndex: neighborIndex,
    );
  }

  // Corner mode: need 閳? points and alternating axis pattern.
  if (points.length < 4) {
    return null;
  }
  final outerIndex = isStart ? cornerIndex + 1 : cornerIndex - 1;
  if (outerIndex < 0 || outerIndex >= points.length) {
    return null;
  }
  double main(DrawPoint p) => h ? p.x : p.y;
  double cross(DrawPoint p) => h ? p.y : p.x;
  final endpoint = isStart ? points.first : points.last;
  final neighbor = points[neighborIndex];
  final corner = points[cornerIndex];
  final outer = points[outerIndex];
  if ((cross(neighbor) - cross(endpoint)).abs() >
          ElbowConstants.dedupThreshold ||
      (main(corner) - main(neighbor)).abs() > ElbowConstants.dedupThreshold ||
      (cross(outer) - cross(corner)).abs() > ElbowConstants.dedupThreshold) {
    return null;
  }
  return _slideAlongHeadingAxis(
    points: points,
    heading: heading,
    desiredLength: desiredLength,
    isStart: isStart,
    neighborIndex: neighborIndex,
    cornerIndex: cornerIndex,
    referenceIndex: outerIndex,
  );
}

_PerpendicularAdjustment _adjustPerpendicularEndpoint({
  required List<DrawPoint> points,
  required ArrowBinding binding,
  required Map<String, ElementState> elementsById,
  required double? directionPadding,
  required bool hasArrowhead,
  required List<ElbowFixedSegment> fixedSegments,
  required bool isStart,
  bool? fixedNeighborAxis,
}) {
  _PerpendicularAdjustment unchanged() =>
      _PerpendicularAdjustment(points: points, moved: false, inserted: false);

  if (points.length < 2) {
    return unchanged();
  }

  final endpoint = isStart ? points.first : points.last;
  final heading = ElbowGeometry.resolveBoundHeading(
    binding: binding,
    elementsById: elementsById,
    point: endpoint,
  );
  if (heading == null) {
    return unchanged();
  }

  final desiredHorizontal = heading.isHorizontal;
  final resolvedPadding = directionPadding == null ||
          !directionPadding.isFinite ||
          directionPadding <= ElbowConstants.dedupThreshold
      ? ElbowConstants.directionFixPadding
      : math.max(ElbowConstants.directionFixPadding, directionPadding);
  final lastIndex = points.length - 1;
  final neighborIndex = isStart ? 1 : lastIndex - 1;
  final neighbor = points[neighborIndex];
  final aligned = desiredHorizontal
      ? (neighbor.y - endpoint.y).abs() <= ElbowConstants.dedupThreshold
      : (neighbor.x - endpoint.x).abs() <= ElbowConstants.dedupThreshold;

  final directionFrom = isStart ? endpoint : neighbor;
  final directionTo = isStart ? neighbor : endpoint;
  final directionHeading = isStart ? heading : heading.opposite;
  final directionOk = _directionMatches(
    directionFrom,
    directionTo,
    directionHeading,
  );

  if (fixedNeighborAxis != null) {
    return _adjustPreservedNeighbor(
      points: points,
      heading: heading,
      resolvedPadding: resolvedPadding,
      fixedSegments: fixedSegments,
      fixedNeighborAxis: fixedNeighborAxis,
      hasArrowhead: hasArrowhead,
      aligned: aligned,
      directionOk: directionOk,
      isStart: isStart,
      binding: binding,
      elementsById: elementsById,
    );
  }

  return _adjustFreeNeighbor(
    points: points,
    heading: heading,
    resolvedPadding: resolvedPadding,
    directionPadding: directionPadding,
    fixedSegments: fixedSegments,
    aligned: aligned,
    directionOk: directionOk,
    isStart: isStart,
  );
}

/// Adjusts an endpoint whose neighbor is constrained by a fixed segment.
_PerpendicularAdjustment _adjustPreservedNeighbor({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double resolvedPadding,
  required List<ElbowFixedSegment> fixedSegments,
  required bool fixedNeighborAxis,
  required bool hasArrowhead,
  required bool aligned,
  required bool directionOk,
  required bool isStart,
  required ArrowBinding binding,
  required Map<String, ElementState> elementsById,
}) {
  _PerpendicularAdjustment unchanged() =>
      _PerpendicularAdjustment(points: points, moved: false, inserted: false);

  final desiredHorizontal = heading.isHorizontal;
  final canSlideNeighbor = fixedNeighborAxis == desiredHorizontal;
  final lastIndex = points.length - 1;
  final neighborIndex = isStart ? 1 : lastIndex - 1;
  final neighbor = points[neighborIndex];
  final fixedPadding = ElbowSpacing.fixedNeighborPadding(
    hasArrowhead: hasArrowhead,
  );

  _PerpendicularAdjustment? trySlide(
    List<DrawPoint> pts, {
    required bool cornerInserted,
  }) {
    if (!canSlideNeighbor) {
      return null;
    }
    return _slideEndpointNeighborToPadding(
      points: pts,
      heading: heading,
      desiredLength: fixedPadding,
      cornerInserted: cornerInserted,
      isStart: isStart,
    );
  }

  if (aligned && directionOk) {
    final cornerFixedIndex = isStart ? 2 : points.length - 3;
    final cornerInserted =
        _endpointHasCorner(points: points, isStart: isStart) &&
        _fixedSegmentIsHorizontal(fixedSegments, cornerFixedIndex) != null;
    return trySlide(points, cornerInserted: cornerInserted) ?? unchanged();
  }

  if (!aligned && directionOk) {
    final inserted = _insertEndpointCorner(
      points: points,
      heading: heading,
      neighbor: neighbor,
      isStart: isStart,
    );
    return trySlide(inserted.points, cornerInserted: true) ?? inserted;
  }

  // End-only: try snapping to the fixed axis at the anchor point.
  if (!isStart &&
      !directionOk &&
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
    return trySlide(points, cornerInserted: false) ?? unchanged();
  }

  return _insertEndpointDirectionStub(
    points: points,
    heading: heading,
    neighbor: neighbor,
    allowExtend: false,
    padding: resolvedPadding,
    isStart: isStart,
  );
}

/// Adjusts an endpoint whose neighbor is free (no fixed segment).
_PerpendicularAdjustment _adjustFreeNeighbor({
  required List<DrawPoint> points,
  required ElbowHeading heading,
  required double resolvedPadding,
  required double? directionPadding,
  required List<ElbowFixedSegment> fixedSegments,
  required bool aligned,
  required bool directionOk,
  required bool isStart,
}) {
  _PerpendicularAdjustment unchanged() =>
      _PerpendicularAdjustment(points: points, moved: false, inserted: false);

  final desiredHorizontal = heading.isHorizontal;
  final lastIndex = points.length - 1;
  final neighborIndex = isStart ? 1 : lastIndex - 1;
  final neighbor = points[neighborIndex];
  final endpoint = isStart ? points.first : points.last;
  final stubPadding = _capDirectionPaddingForAxis(
    padding: resolvedPadding,
    endpoint: endpoint,
    heading: heading,
    axis: _resolveFixedAxisLimit(
      points: points,
      fixedSegments: fixedSegments,
      isStart: isStart,
      heading: heading,
    ),
  );

  if (aligned && directionOk) {
    return _slideEndpointToPadding(
          points: points,
          heading: heading,
          desiredLength: directionPadding,
          isStart: isStart,
        ) ??
        _slideEndpointToPadding(
          points: points,
          heading: heading,
          desiredLength: directionPadding,
          isStart: isStart,
          cornerIndex: isStart ? 2 : lastIndex - 2,
        ) ??
        unchanged();
  }

  if (aligned && !directionOk) {
    final updated = List<DrawPoint>.from(points);
    updated[neighborIndex] = _applyEndpointDirection(
      neighbor,
      endpoint,
      heading,
      resolvedPadding,
    );
    return _PerpendicularAdjustment(
      points: updated,
      moved: true,
      inserted: false,
    );
  }

  // Not aligned: check the adjacent segment for axis conflicts.
  final adjacentIndex = isStart ? neighborIndex + 1 : neighborIndex - 1;
  final adjacentHorizontal =
      points.length > 2 && adjacentIndex >= 0 && adjacentIndex < points.length
      ? ElbowGeometry.segmentIsHorizontal(
          isStart ? neighbor : points[adjacentIndex],
          isStart ? points[adjacentIndex] : neighbor,
        )
      : desiredHorizontal;
  final conflict = adjacentHorizontal == desiredHorizontal;
  final canShiftDirection =
      points.length <= 2 ||
      (desiredHorizontal ? adjacentHorizontal : !adjacentHorizontal);

  if (!conflict && (directionOk || canShiftDirection)) {
    var updatedNeighbor = neighbor;
    if (!aligned) {
      updatedNeighbor = desiredHorizontal
          ? updatedNeighbor.copyWith(y: endpoint.y)
          : updatedNeighbor.copyWith(x: endpoint.x);
    }
    if (!directionOk && canShiftDirection) {
      updatedNeighbor = _applyEndpointDirection(
        updatedNeighbor,
        endpoint,
        heading,
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
    isStart: isStart,
  );
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
) {
  final target = ElbowGeometry.offsetPoint(endpoint, heading, padding);
  final h = heading.isHorizontal;
  final neighborVal = h ? neighbor.x : neighbor.y;
  final targetVal = h ? target.x : target.y;
  final endpointVal = h ? endpoint.x : endpoint.y;
  // Keep the neighbor if it's already past the target in the heading
  // direction.
  final alreadyPast =
      (neighborVal - endpointVal).sign == (targetVal - endpointVal).sign &&
      (neighborVal - endpointVal).abs() >= (targetVal - endpointVal).abs();
  if (alreadyPast) {
    return neighbor;
  }
  return h ? neighbor.copyWith(x: targetVal) : neighbor.copyWith(y: targetVal);
}

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

  final referenceIndex = isStart ? neighborIndex + 1 : neighborIndex - 1;
  final corner = cornerInserted ? (isStart ? 1 : lastIndex - 1) : null;
  return _slideAlongHeadingAxis(
    points: points,
    heading: heading,
    desiredLength: desiredLength,
    isStart: isStart,
    neighborIndex: neighborIndex,
    cornerIndex: corner,
    referenceIndex: referenceIndex,
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
  final stub = ElbowGeometry.offsetPoint(endpoint, heading, padding);
  final connector = heading.isHorizontal
      ? DrawPoint(x: stub.x, y: neighbor.y)
      : DrawPoint(x: neighbor.x, y: stub.y);

  final updated = List<DrawPoint>.from(points);
  final ni = isStart ? 1 : updated.length - 2;
  var insertIndex = isStart ? 1 : updated.length - 1;
  var moved = false;
  var inserted = false;

  if (allowExtend && points.length > 2) {
    final adjacent = isStart ? points[2] : points[points.length - 3];
    final adjH = ElbowGeometry.segmentIsHorizontal(neighbor, adjacent);
    final aligned = adjH
        ? (connector.y - neighbor.y).abs() <= ElbowConstants.dedupThreshold
        : (connector.x - neighbor.x).abs() <= ElbowConstants.dedupThreshold;
    if (aligned) {
      updated[ni] = connector;
      moved = true;
    }
  }

  final hasStub =
      ElbowGeometry.manhattanDistance(stub, endpoint) >
      ElbowConstants.dedupThreshold;
  final hasConnector =
      !moved &&
      ElbowGeometry.manhattanDistance(connector, neighbor) >
          ElbowConstants.dedupThreshold &&
      ElbowGeometry.manhattanDistance(connector, stub) >
          ElbowConstants.dedupThreshold;
  final toInsert = isStart
      ? [if (hasStub) stub, if (hasConnector) connector]
      : [if (hasConnector) connector, if (hasStub) stub];
  for (final point in toInsert) {
    updated.insert(insertIndex, point);
    insertIndex++;
    inserted = true;
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
  final slid = _slideRun(
    points: points,
    startIndex: neighborIndex,
    horizontal: false,
    target: anchor.x,
    direction: 1,
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
    if (segment.index <= 0 || segment.index >= points.length) {
      continue;
    }
    if (segment.isHorizontal != wantHorizontal) {
      continue;
    }
    return segment.axisValue;
  }
  return null;
}

double _capDirectionPaddingForAxis({
  required double padding,
  required DrawPoint endpoint,
  required ElbowHeading heading,
  required double? axis,
}) {
  if (!padding.isFinite || padding <= 0 || axis == null || !axis.isFinite) {
    return padding;
  }
  final maxPadding = switch (heading) {
    ElbowHeading.left => endpoint.x - axis,
    ElbowHeading.right => axis - endpoint.x,
    ElbowHeading.up => endpoint.y - axis,
    ElbowHeading.down => axis - endpoint.y,
  };
  if (maxPadding <= ElbowConstants.dedupThreshold) {
    return padding;
  }
  return math.min(padding, maxPadding);
}
