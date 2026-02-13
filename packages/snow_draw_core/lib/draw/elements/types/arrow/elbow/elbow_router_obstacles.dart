part of 'elbow_router.dart';

/// Obstacle layout utilities for elbow routing.
///
/// These helpers inflate bound element bounds with heading-aware padding,
/// split overlaps to keep the grid searchable, and compute exit points
/// where the route leaves each obstacle.

// Shared layout helpers.
DrawRect _inflateBounds(DrawRect rect, double padding) => DrawRect(
  minX: rect.minX - padding,
  minY: rect.minY - padding,
  maxX: rect.maxX + padding,
  maxY: rect.maxY + padding,
);

DrawRect _clampBounds(DrawRect rect) {
  const max = ElbowConstants.maxPosition;
  return DrawRect(
    minX: rect.minX.clamp(-max, max),
    minY: rect.minY.clamp(-max, max),
    maxX: rect.maxX.clamp(-max, max),
    maxY: rect.maxY.clamp(-max, max),
  );
}

DrawPoint _clampPoint(DrawPoint point) {
  const max = ElbowConstants.maxPosition;
  return DrawPoint(x: point.x.clamp(-max, max), y: point.y.clamp(-max, max));
}

DrawRect _unionBounds(List<DrawRect> bounds) {
  var minX = bounds.first.minX;
  var minY = bounds.first.minY;
  var maxX = bounds.first.maxX;
  var maxY = bounds.first.maxY;
  for (final rect in bounds.skip(1)) {
    minX = math.min(minX, rect.minX);
    minY = math.min(minY, rect.minY);
    maxX = math.max(maxX, rect.maxX);
    maxY = math.max(maxY, rect.maxY);
  }
  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

bool _boundsOverlap(DrawRect a, DrawRect b) =>
    a.minX < b.maxX && a.maxX > b.minX && a.minY < b.maxY && a.maxY > b.minY;

({DrawRect start, DrawRect end}) _splitOverlappingOnAxis({
  required DrawRect startBounds,
  required DrawRect endBounds,
  required DrawRect startObstacle,
  required DrawRect endObstacle,
  required double splitValue,
  required double overlapMin,
  required double overlapMax,
  required bool startBeforeEnd,
  required bool horizontal,
}) {
  var minSplit = horizontal
      ? (startBeforeEnd ? startBounds.maxX : endBounds.maxX)
      : (startBeforeEnd ? startBounds.maxY : endBounds.maxY);
  var maxSplit = horizontal
      ? (startBeforeEnd ? endBounds.minX : startBounds.minX)
      : (startBeforeEnd ? endBounds.minY : startBounds.minY);

  if (maxSplit < minSplit) {
    minSplit = overlapMin;
    maxSplit = overlapMax;
  }
  if (maxSplit - minSplit <= ElbowConstants.intersectionEpsilon) {
    return (start: startObstacle, end: endObstacle);
  }

  final clamped = splitValue.clamp(minSplit, maxSplit);

  // Apply the split: the "before" obstacle gets clamped on its far edge,
  // the "after" obstacle gets clamped on its near edge.
  late final DrawRect clampStart;
  late final DrawRect clampEnd;
  if (horizontal) {
    clampStart = startBeforeEnd
        ? startObstacle.copyWith(maxX: math.min(startObstacle.maxX, clamped))
        : startObstacle.copyWith(minX: math.max(startObstacle.minX, clamped));
    clampEnd = startBeforeEnd
        ? endObstacle.copyWith(minX: math.max(endObstacle.minX, clamped))
        : endObstacle.copyWith(maxX: math.min(endObstacle.maxX, clamped));
  } else {
    clampStart = startBeforeEnd
        ? startObstacle.copyWith(maxY: math.min(startObstacle.maxY, clamped))
        : startObstacle.copyWith(minY: math.max(startObstacle.minY, clamped));
    clampEnd = startBeforeEnd
        ? endObstacle.copyWith(minY: math.max(endObstacle.minY, clamped))
        : endObstacle.copyWith(maxY: math.min(endObstacle.maxY, clamped));
  }
  return (start: clampStart, end: clampEnd);
}

({DrawRect start, DrawRect end}) _splitOverlappingObstacles({
  required DrawRect startBounds,
  required DrawRect endBounds,
  required DrawRect startObstacle,
  required DrawRect endObstacle,
  DrawPoint? startPivot,
  DrawPoint? endPivot,
}) {
  // Split the overlap so the grid can route between bound obstacles.
  if (!_boundsOverlap(startObstacle, endObstacle)) {
    return (start: startObstacle, end: endObstacle);
  }

  final startCenter = startPivot ?? startBounds.center;
  final endCenter = endPivot ?? endBounds.center;
  final dx = (startCenter.x - endCenter.x).abs();
  final dy = (startCenter.y - endCenter.y).abs();
  final overlapMinX = math.max(startObstacle.minX, endObstacle.minX);
  final overlapMaxX = math.min(startObstacle.maxX, endObstacle.maxX);
  final overlapMinY = math.max(startObstacle.minY, endObstacle.minY);
  final overlapMaxY = math.min(startObstacle.maxY, endObstacle.maxY);

  if (dx >= dy) {
    final splitX = (startCenter.x + endCenter.x) / 2;
    return _splitOverlappingOnAxis(
      startBounds: startBounds,
      endBounds: endBounds,
      startObstacle: startObstacle,
      endObstacle: endObstacle,
      splitValue: splitX,
      overlapMin: overlapMinX,
      overlapMax: overlapMaxX,
      startBeforeEnd: startCenter.x <= endCenter.x,
      horizontal: true,
    );
  }

  final splitY = (startCenter.y + endCenter.y) / 2;
  return _splitOverlappingOnAxis(
    startBounds: startBounds,
    endBounds: endBounds,
    startObstacle: startObstacle,
    endObstacle: endObstacle,
    splitValue: splitY,
    overlapMin: overlapMinY,
    overlapMax: overlapMaxY,
    startBeforeEnd: startCenter.y <= endCenter.y,
    horizontal: false,
  );
}

DrawRect _pointBounds(DrawPoint point, double padding) => DrawRect(
  minX: point.x - padding,
  minY: point.y - padding,
  maxX: point.x + padding,
  maxY: point.y + padding,
);

DrawRect _elementBoundsForElbow({
  required DrawPoint point,
  required DrawRect? elementBounds,
  required ElbowHeading heading,
  required bool hasArrowhead,
}) {
  if (elementBounds == null) {
    return _pointBounds(point, 0);
  }

  final headOffset = ElbowSpacing.bindingGap(hasArrowhead: hasArrowhead);
  final padding = _paddingFromHeading(
    heading,
    headOffset,
    ElbowConstants.elementSidePadding,
  );
  return DrawRect(
    minX: elementBounds.minX - padding.left,
    minY: elementBounds.minY - padding.top,
    maxX: elementBounds.maxX + padding.right,
    maxY: elementBounds.maxY + padding.bottom,
  );
}

_BoundsPadding _overlapPadding(ElbowHeading heading) =>
    _paddingFromHeading(heading, ElbowConstants.basePadding, 0);

_BoundsPadding _routingPadding({
  required ElbowHeading heading,
  required bool hasArrowhead,
}) => _paddingFromHeading(
  heading,
  ElbowSpacing.headPadding(hasArrowhead: hasArrowhead),
  ElbowConstants.basePadding,
);

DrawRect _dynamicAabbFor({
  required DrawRect self,
  required DrawRect other,
  required DrawRect common,
  required _BoundsPadding padding,
  DrawRect? selfElementBounds,
  DrawRect? otherElementBounds,
}) {
  final selfEl = selfElementBounds ?? self;
  final otherEl = otherElementBounds ?? other;
  final sepY = self.minY > other.maxY || self.maxY < other.minY;
  final sepX = self.minX > other.maxX || self.maxX < other.minX;

  return DrawRect(
    minX: _aabbEdge(
      selfNear: self.minX,
      selfFar: self.maxX,
      otherNear: other.minX,
      otherFar: other.maxX,
      commonEdge: common.minX,
      pad: padding.left,
      selfEl: selfEl.minX,
      otherEl: otherEl.maxX,
      separated: sepY,
      isMin: true,
    ),
    minY: _aabbEdge(
      selfNear: self.minY,
      selfFar: self.maxY,
      otherNear: other.minY,
      otherFar: other.maxY,
      commonEdge: common.minY,
      pad: padding.top,
      selfEl: selfEl.minY,
      otherEl: otherEl.maxY,
      separated: sepX,
      isMin: true,
    ),
    maxX: _aabbEdge(
      selfNear: self.maxX,
      selfFar: self.minX,
      otherNear: other.maxX,
      otherFar: other.minX,
      commonEdge: common.maxX,
      pad: padding.right,
      selfEl: selfEl.maxX,
      otherEl: otherEl.minX,
      separated: sepY,
      isMin: false,
    ),
    maxY: _aabbEdge(
      selfNear: self.maxY,
      selfFar: self.minY,
      otherNear: other.maxY,
      otherFar: other.minY,
      commonEdge: common.maxY,
      pad: padding.bottom,
      selfEl: selfEl.maxY,
      otherEl: otherEl.minY,
      separated: sepX,
      isMin: false,
    ),
  );
}

double _aabbEdge({
  required double selfNear,
  required double selfFar,
  required double otherNear,
  required double otherFar,
  required double commonEdge,
  required double pad,
  required double selfEl,
  required double otherEl,
  required bool separated,
  required bool isMin,
}) {
  if (isMin ? selfNear > otherFar : selfNear < otherFar) {
    final split = (selfEl + otherEl) / 2;
    final padded = isMin ? selfNear - pad : selfNear + pad;
    return separated
        ? (isMin ? math.min(split, padded) : math.max(split, padded))
        : split;
  }
  if (isMin ? selfNear > otherNear : selfNear < otherNear) {
    return isMin ? selfNear - pad : selfNear + pad;
  }
  return isMin ? commonEdge - pad : commonEdge + pad;
}

_BoundsPadding _paddingFromHeading(
  ElbowHeading heading,
  double headOffset,
  double sideOffset,
) => switch (heading) {
  ElbowHeading.up => (
    top: headOffset,
    right: sideOffset,
    bottom: sideOffset,
    left: sideOffset,
  ),
  ElbowHeading.right => (
    top: sideOffset,
    right: headOffset,
    bottom: sideOffset,
    left: sideOffset,
  ),
  ElbowHeading.down => (
    top: sideOffset,
    right: sideOffset,
    bottom: headOffset,
    left: sideOffset,
  ),
  ElbowHeading.left => (
    top: sideOffset,
    right: sideOffset,
    bottom: sideOffset,
    left: headOffset,
  ),
};

typedef _BoundsPadding = ({
  double top,
  double right,
  double bottom,
  double left,
});

DrawPoint _exitPosition({
  required DrawRect bounds,
  required ElbowHeading heading,
  required DrawPoint point,
}) => switch (heading) {
  ElbowHeading.up => DrawPoint(x: point.x, y: bounds.minY),
  ElbowHeading.right => DrawPoint(x: bounds.maxX, y: point.y),
  ElbowHeading.down => DrawPoint(x: point.x, y: bounds.maxY),
  ElbowHeading.left => DrawPoint(x: bounds.minX, y: point.y),
};

typedef _ElbowObstacleLayout = ({
  DrawRect commonBounds,
  DrawPoint startExit,
  DrawPoint endExit,
  List<DrawRect> obstacles,
});

/// Builds the obstacle layout for a single routed elbow path.
_ElbowObstacleLayout _planObstacleLayout({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
}) {
  final startElbow = _elementBoundsForElbow(
    point: start.point,
    elementBounds: start.elementBounds,
    heading: start.heading,
    hasArrowhead: start.hasArrowhead,
  );
  final endElbow = _elementBoundsForElbow(
    point: end.point,
    elementBounds: end.elementBounds,
    heading: end.heading,
    hasArrowhead: end.hasArrowhead,
  );
  final overlap =
      start.isBound && end.isBound && _boundsOverlap(startElbow, endElbow);

  final startBase = overlap
      ? _pointBounds(start.point, ElbowConstants.exitPointPadding)
      : startElbow;
  final endBase = overlap
      ? _pointBounds(end.point, ElbowConstants.exitPointPadding)
      : endElbow;

  final startPad = overlap
      ? _overlapPadding(start.heading)
      : _routingPadding(
          heading: start.heading,
          hasArrowhead: start.hasArrowhead,
        );
  final endPad = overlap
      ? _overlapPadding(end.heading)
      : _routingPadding(heading: end.heading, hasArrowhead: end.hasArrowhead);

  final startEl = overlap || !start.isBound ? null : startElbow;
  final endEl = overlap || !end.isBound ? null : endElbow;
  final common = _unionBounds([startBase, endBase]);
  final startDyn = _dynamicAabbFor(
    self: startBase,
    other: endBase,
    common: common,
    padding: startPad,
    selfElementBounds: startEl,
    otherElementBounds: endEl,
  );
  final endDyn = _dynamicAabbFor(
    self: endBase,
    other: startBase,
    common: common,
    padding: endPad,
    selfElementBounds: endEl,
    otherElementBounds: startEl,
  );

  final obs = _resolveObstacleBounds(
    start: start,
    end: end,
    startBaseBounds: startBase,
    endBaseBounds: endBase,
    startDynamic: startDyn,
    endDynamic: endDyn,
  );

  final commonBounds = _clampBounds(
    _inflateBounds(
      _unionBounds([obs.start, obs.end]),
      ElbowConstants.basePadding,
    ),
  );

  return (
    commonBounds: commonBounds,
    startExit: _exitPosition(
      bounds: obs.start,
      heading: start.heading,
      point: start.point,
    ),
    endExit: _exitPosition(
      bounds: obs.end,
      heading: end.heading,
      point: end.point,
    ),
    obstacles: <DrawRect>[obs.start, obs.end],
  );
}

({DrawRect start, DrawRect end}) _resolveObstacleBounds({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
  required DrawRect startBaseBounds,
  required DrawRect endBaseBounds,
  required DrawRect startDynamic,
  required DrawRect endDynamic,
}) {
  var sObs = _clampBounds(start.isBound ? startDynamic : startBaseBounds);
  var eObs = _clampBounds(end.isBound ? endDynamic : endBaseBounds);
  if (_boundsOverlap(sObs, eObs)) {
    final split = _splitOverlappingObstacles(
      startBounds: startBaseBounds,
      endBounds: endBaseBounds,
      startObstacle: sObs,
      endObstacle: eObs,
      startPivot: start.anchorOrPoint,
      endPivot: end.anchorOrPoint,
    );
    sObs = _clampBounds(split.start);
    eObs = _clampBounds(split.end);
  }
  sObs = _clampObstacleToBoundsPadding(endpoint: start, obstacle: sObs);
  eObs = _clampObstacleToBoundsPadding(endpoint: end, obstacle: eObs);
  final h = _harmonizeObstacleExitSpacing(
    start: start,
    end: end,
    startObstacle: sObs,
    endObstacle: eObs,
  );
  return (start: h.start, end: h.end);
}

DrawRect _clampObstacleToBoundsPadding({
  required _ResolvedEndpoint endpoint,
  required DrawRect obstacle,
}) {
  if (!endpoint.isBound || endpoint.elementBounds == null) {
    return obstacle;
  }
  final b = endpoint.elementBounds!;
  const p = ElbowConstants.basePadding;
  return obstacle.copyWith(
    minX: math.max(obstacle.minX, b.minX - p),
    minY: math.max(obstacle.minY, b.minY - p),
    maxX: math.min(obstacle.maxX, b.maxX + p),
    maxY: math.min(obstacle.maxY, b.maxY + p),
  );
}

({DrawRect start, DrawRect end}) _harmonizeObstacleExitSpacing({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
  required DrawRect startObstacle,
  required DrawRect endObstacle,
}) {
  final noChange = (start: startObstacle, end: endObstacle);
  final startBounds = start.elementBounds;
  final endBounds = end.elementBounds;
  if (!start.isBound ||
      !end.isBound ||
      startBounds == null ||
      endBounds == null) {
    return noChange;
  }
  final spacing = ElbowSpacing.resolveSharedSpacing(
    startSpacing: ElbowSpacing.resolveObstacleSpacing(
      elementBounds: startBounds,
      obstacle: startObstacle,
      heading: start.heading,
    ),
    endSpacing: ElbowSpacing.resolveObstacleSpacing(
      elementBounds: endBounds,
      obstacle: endObstacle,
      heading: end.heading,
    ),
    startHasArrowhead: start.hasArrowhead,
    endHasArrowhead: end.hasArrowhead,
  );
  if (spacing == null) {
    return noChange;
  }
  return (
    start: _clampBounds(
      ElbowSpacing.applyObstacleSpacing(
        obstacle: startObstacle,
        elementBounds: startBounds,
        heading: start.heading,
        spacing: spacing,
      ),
    ),
    end: _clampBounds(
      ElbowSpacing.applyObstacleSpacing(
        obstacle: endObstacle,
        elementBounds: endBounds,
        heading: end.heading,
        spacing: spacing,
      ),
    ),
  );
}
