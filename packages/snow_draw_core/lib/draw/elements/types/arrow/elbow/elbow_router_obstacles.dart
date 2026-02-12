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
  var minSplit = startBeforeEnd
      ? (horizontal ? startBounds.maxX : startBounds.maxY)
      : (horizontal ? endBounds.maxX : endBounds.maxY);
  var maxSplit = startBeforeEnd
      ? (horizontal ? endBounds.minX : endBounds.minY)
      : (horizontal ? startBounds.minX : startBounds.minY);

  if (maxSplit < minSplit) {
    minSplit = overlapMin;
    maxSplit = overlapMax;
  }
  if (maxSplit - minSplit <= ElbowConstants.intersectionEpsilon) {
    return (start: startObstacle, end: endObstacle);
  }

  final clamped = splitValue.clamp(minSplit, maxSplit);

  if (horizontal) {
    if (startBeforeEnd) {
      return (
        start: startObstacle.copyWith(
          maxX: math.min(startObstacle.maxX, clamped),
        ),
        end: endObstacle.copyWith(minX: math.max(endObstacle.minX, clamped)),
      );
    }
    return (
      start: startObstacle.copyWith(
        minX: math.max(startObstacle.minX, clamped),
      ),
      end: endObstacle.copyWith(maxX: math.min(endObstacle.maxX, clamped)),
    );
  }

  if (startBeforeEnd) {
    return (
      start: startObstacle.copyWith(
        maxY: math.min(startObstacle.maxY, clamped),
      ),
      end: endObstacle.copyWith(minY: math.max(endObstacle.minY, clamped)),
    );
  }
  return (
    start: startObstacle.copyWith(minY: math.max(startObstacle.minY, clamped)),
    end: endObstacle.copyWith(maxY: math.min(endObstacle.maxY, clamped)),
  );
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
  final separatedY = self.minY > other.maxY || self.maxY < other.minY;
  final separatedX = self.minX > other.maxX || self.maxX < other.minX;

  return DrawRect(
    minX: _computeEdge(
      selfNear: self.minX,
      selfFar: self.maxX,
      otherNear: other.minX,
      otherFar: other.maxX,
      commonEdge: common.minX,
      padding: padding.left,
      selfElement: selfEl.minX,
      otherElement: otherEl.maxX,
      separated: separatedY,
      isMin: true,
    ),
    minY: _computeEdge(
      selfNear: self.minY,
      selfFar: self.maxY,
      otherNear: other.minY,
      otherFar: other.maxY,
      commonEdge: common.minY,
      padding: padding.top,
      selfElement: selfEl.minY,
      otherElement: otherEl.maxY,
      separated: separatedX,
      isMin: true,
    ),
    maxX: _computeEdge(
      selfNear: self.maxX,
      selfFar: self.minX,
      otherNear: other.maxX,
      otherFar: other.minX,
      commonEdge: common.maxX,
      padding: padding.right,
      selfElement: selfEl.maxX,
      otherElement: otherEl.minX,
      separated: separatedY,
      isMin: false,
    ),
    maxY: _computeEdge(
      selfNear: self.maxY,
      selfFar: self.minY,
      otherNear: other.maxY,
      otherFar: other.minY,
      commonEdge: common.maxY,
      padding: padding.bottom,
      selfElement: selfEl.maxY,
      otherElement: otherEl.minY,
      separated: separatedX,
      isMin: false,
    ),
  );
}

/// Computes a single edge of the dynamic AABB.
///
/// For min edges: [selfNear] = selfMin, [selfFar] = selfMax,
///   [otherNear] = otherMin, [otherFar] = otherMax.
/// For max edges: [selfNear] = selfMax, [selfFar] = selfMin,
///   [otherNear] = otherMax, [otherFar] = otherMin.
double _computeEdge({
  required double selfNear,
  required double selfFar,
  required double otherNear,
  required double otherFar,
  required double commonEdge,
  required double padding,
  required double selfElement,
  required double otherElement,
  required bool separated,
  required bool isMin,
}) {
  final beyondOther = isMin ? selfNear > otherFar : selfNear < otherFar;
  if (beyondOther) {
    final split = (selfElement + otherElement) / 2;
    final padded = isMin ? selfNear - padding : selfNear + padding;
    return separated
        ? (isMin ? math.min(split, padded) : math.max(split, padded))
        : split;
  }
  final pastOtherNear = isMin ? selfNear > otherNear : selfNear < otherNear;
  if (pastOtherNear) {
    return isMin ? selfNear - padding : selfNear + padding;
  }
  return isMin ? commonEdge - padding : commonEdge + padding;
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
///
/// Orchestrates endpoint bounds resolution, dynamic AABB expansion,
/// overlap splitting, spacing harmonization, and exit point computation.
_ElbowObstacleLayout _planObstacleLayout({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
}) {
  // 1. Resolve heading-aware bounds for each bound endpoint.
  final startElbowBounds = _elementBoundsForElbow(
    point: start.point,
    elementBounds: start.elementBounds,
    heading: start.heading,
    hasArrowhead: start.hasArrowhead,
  );
  final endElbowBounds = _elementBoundsForElbow(
    point: end.point,
    elementBounds: end.elementBounds,
    heading: end.heading,
    hasArrowhead: end.hasArrowhead,
  );
  final boundsOverlap =
      start.isBound &&
      end.isBound &&
      _boundsOverlap(startElbowBounds, endElbowBounds);

  // 2. Prefer point-sized bounds when endpoints overlap.
  final startBase = boundsOverlap
      ? _pointBounds(start.point, ElbowConstants.exitPointPadding)
      : startElbowBounds;
  final endBase = boundsOverlap
      ? _pointBounds(end.point, ElbowConstants.exitPointPadding)
      : endElbowBounds;

  // 3. Pick padding based on heading/arrowhead configuration.
  final startPadding = boundsOverlap
      ? _overlapPadding(start.heading)
      : _routingPadding(
          heading: start.heading,
          hasArrowhead: start.hasArrowhead,
        );
  final endPadding = boundsOverlap
      ? _overlapPadding(end.heading)
      : _routingPadding(heading: end.heading, hasArrowhead: end.hasArrowhead);

  // 4. Expand the bounds to build the grid routing envelope.
  final startElBounds = boundsOverlap || !start.isBound
      ? null
      : startElbowBounds;
  final endElBounds = boundsOverlap || !end.isBound ? null : endElbowBounds;
  final common = _unionBounds([startBase, endBase]);
  final startDynamic = _dynamicAabbFor(
    self: startBase,
    other: endBase,
    common: common,
    padding: startPadding,
    selfElementBounds: startElBounds,
    otherElementBounds: endElBounds,
  );
  final endDynamic = _dynamicAabbFor(
    self: endBase,
    other: startBase,
    common: common,
    padding: endPadding,
    selfElementBounds: endElBounds,
    otherElementBounds: startElBounds,
  );

  // 5. Split overlapping obstacles and harmonize exit spacing.
  final obstacleBounds = _resolveObstacleBounds(
    start: start,
    end: end,
    startBaseBounds: startBase,
    endBaseBounds: endBase,
    startDynamic: startDynamic,
    endDynamic: endDynamic,
  );

  // 6. Derive shared bounds and exit points for the grid router.
  final commonBounds = _clampBounds(
    _inflateBounds(
      _unionBounds([obstacleBounds.start, obstacleBounds.end]),
      ElbowConstants.basePadding,
    ),
  );

  return (
    commonBounds: commonBounds,
    startExit: _exitPosition(
      bounds: obstacleBounds.start,
      heading: start.heading,
      point: start.point,
    ),
    endExit: _exitPosition(
      bounds: obstacleBounds.end,
      heading: end.heading,
      point: end.point,
    ),
    obstacles: <DrawRect>[obstacleBounds.start, obstacleBounds.end],
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
  var startObstacle = _clampBounds(
    start.isBound ? startDynamic : startBaseBounds,
  );
  var endObstacle = _clampBounds(end.isBound ? endDynamic : endBaseBounds);
  if (_boundsOverlap(startObstacle, endObstacle)) {
    final split = _splitOverlappingObstacles(
      startBounds: startBaseBounds,
      endBounds: endBaseBounds,
      startObstacle: startObstacle,
      endObstacle: endObstacle,
      startPivot: start.anchorOrPoint,
      endPivot: end.anchorOrPoint,
    );
    startObstacle = _clampBounds(split.start);
    endObstacle = _clampBounds(split.end);
  }

  startObstacle = _clampObstacleToBoundsPadding(
    endpoint: start,
    obstacle: startObstacle,
  );
  endObstacle = _clampObstacleToBoundsPadding(
    endpoint: end,
    obstacle: endObstacle,
  );

  final harmonized = _harmonizeObstacleExitSpacing(
    start: start,
    end: end,
    startObstacle: startObstacle,
    endObstacle: endObstacle,
  );

  return (start: harmonized.start, end: harmonized.end);
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
    minY: math.max(obstacle.minY, b.minY - p),
    maxX: math.min(obstacle.maxX, b.maxX + p),
    maxY: math.min(obstacle.maxY, b.maxY + p),
    minX: math.max(obstacle.minX, b.minX - p),
  );
}

({DrawRect start, DrawRect end}) _harmonizeObstacleExitSpacing({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
  required DrawRect startObstacle,
  required DrawRect endObstacle,
}) {
  if (!start.isBound || !end.isBound) {
    return (start: startObstacle, end: endObstacle);
  }
  final startBounds = start.elementBounds;
  final endBounds = end.elementBounds;
  if (startBounds == null || endBounds == null) {
    return (start: startObstacle, end: endObstacle);
  }

  final startSpacing = ElbowSpacing.resolveObstacleSpacing(
    elementBounds: startBounds,
    obstacle: startObstacle,
    heading: start.heading,
  );
  final endSpacing = ElbowSpacing.resolveObstacleSpacing(
    elementBounds: endBounds,
    obstacle: endObstacle,
    heading: end.heading,
  );
  final resolvedSpacing = ElbowSpacing.resolveSharedSpacing(
    startSpacing: startSpacing,
    endSpacing: endSpacing,
    startHasArrowhead: start.hasArrowhead,
    endHasArrowhead: end.hasArrowhead,
  );
  if (resolvedSpacing == null) {
    return (start: startObstacle, end: endObstacle);
  }

  return (
    start: _clampBounds(
      ElbowSpacing.applyObstacleSpacing(
        obstacle: startObstacle,
        elementBounds: startBounds,
        heading: start.heading,
        spacing: resolvedSpacing,
      ),
    ),
    end: _clampBounds(
      ElbowSpacing.applyObstacleSpacing(
        obstacle: endObstacle,
        elementBounds: endBounds,
        heading: end.heading,
        spacing: resolvedSpacing,
      ),
    ),
  );
}
