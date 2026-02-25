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
}) {
  final separatedVertically = self.minY > other.maxY || self.maxY < other.minY;
  final separatedHorizontally =
      self.minX > other.maxX || self.maxX < other.minX;

  return DrawRect(
    minX: _dynamicMinEdge(
      selfMin: self.minX,
      otherMin: other.minX,
      otherMax: other.maxX,
      commonMin: common.minX,
      pad: padding.left,
      separated: separatedVertically,
    ),
    minY: _dynamicMinEdge(
      selfMin: self.minY,
      otherMin: other.minY,
      otherMax: other.maxY,
      commonMin: common.minY,
      pad: padding.top,
      separated: separatedHorizontally,
    ),
    maxX: _dynamicMaxEdge(
      selfMax: self.maxX,
      otherMin: other.minX,
      otherMax: other.maxX,
      commonMax: common.maxX,
      pad: padding.right,
      separated: separatedVertically,
    ),
    maxY: _dynamicMaxEdge(
      selfMax: self.maxY,
      otherMin: other.minY,
      otherMax: other.maxY,
      commonMax: common.maxY,
      pad: padding.bottom,
      separated: separatedHorizontally,
    ),
  );
}

double _dynamicMinEdge({
  required double selfMin,
  required double otherMin,
  required double otherMax,
  required double commonMin,
  required double pad,
  required bool separated,
}) {
  if (selfMin > otherMax) {
    final split = (selfMin + otherMax) / 2;
    if (!separated) {
      return split;
    }
    return math.min(split, selfMin - pad);
  }
  if (selfMin > otherMin) {
    return selfMin - pad;
  }
  return commonMin - pad;
}

double _dynamicMaxEdge({
  required double selfMax,
  required double otherMin,
  required double otherMax,
  required double commonMax,
  required double pad,
  required bool separated,
}) {
  if (selfMax < otherMin) {
    final split = (selfMax + otherMin) / 2;
    if (!separated) {
      return split;
    }
    return math.max(split, selfMax + pad);
  }
  if (selfMax < otherMax) {
    return selfMax + pad;
  }
  return commonMax + pad;
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

  final common = _unionBounds([startBase, endBase]);
  final startObstacle = start.isBound
      ? _dynamicAabbFor(
          self: startBase,
          other: endBase,
          common: common,
          padding: startPad,
        )
      : startBase;
  final endObstacle = end.isBound
      ? _dynamicAabbFor(
          self: endBase,
          other: startBase,
          common: common,
          padding: endPad,
        )
      : endBase;

  final obs = _resolveObstacleBounds(
    start: start,
    end: end,
    startBaseBounds: startBase,
    endBaseBounds: endBase,
    startObstacle: startObstacle,
    endObstacle: endObstacle,
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
  required DrawRect startObstacle,
  required DrawRect endObstacle,
}) {
  var sObs = _clampBounds(startObstacle);
  var eObs = _clampBounds(endObstacle);
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
  final bounds = endpoint.elementBounds;
  if (bounds == null) {
    return obstacle;
  }
  const p = ElbowConstants.basePadding;
  return obstacle.copyWith(
    minX: math.max(obstacle.minX, bounds.minX - p),
    minY: math.max(obstacle.minY, bounds.minY - p),
    maxX: math.min(obstacle.maxX, bounds.maxX + p),
    maxY: math.min(obstacle.maxY, bounds.maxY + p),
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
  if (startBounds == null || endBounds == null) {
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
