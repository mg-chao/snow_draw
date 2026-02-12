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

DrawRect _clampBounds(DrawRect rect) => DrawRect(
  minX: rect.minX.clamp(
    -ElbowConstants.maxPosition,
    ElbowConstants.maxPosition,
  ),
  minY: rect.minY.clamp(
    -ElbowConstants.maxPosition,
    ElbowConstants.maxPosition,
  ),
  maxX: rect.maxX.clamp(
    -ElbowConstants.maxPosition,
    ElbowConstants.maxPosition,
  ),
  maxY: rect.maxY.clamp(
    -ElbowConstants.maxPosition,
    ElbowConstants.maxPosition,
  ),
);

DrawPoint _clampPoint(DrawPoint point) => DrawPoint(
  x: point.x.clamp(-ElbowConstants.maxPosition, ElbowConstants.maxPosition),
  y: point.y.clamp(-ElbowConstants.maxPosition, ElbowConstants.maxPosition),
);

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

DrawRect? _aabbElementBounds({
  required bool boundsOverlap,
  required bool isBound,
  required DrawRect elbowBounds,
}) => boundsOverlap || !isBound ? null : elbowBounds;

DrawRect _dynamicAabbFor({
  required DrawRect self,
  required DrawRect other,
  required DrawRect common,
  required _BoundsPadding padding,
  DrawRect? selfElementBounds,
  DrawRect? otherElementBounds,
}) {
  final selfElement = selfElementBounds ?? self;
  final otherElement = otherElementBounds ?? other;

  final minX = _computeMinEdge(
    selfMin: self.minX,
    selfMax: self.maxX,
    otherMin: other.minX,
    otherMax: other.maxX,
    commonMin: common.minX,
    padding: padding.left,
    selfElement: selfElement.minX,
    otherElement: otherElement.maxX,
    separated: self.minY > other.maxY || self.maxY < other.minY,
  );

  final minY = _computeMinEdge(
    selfMin: self.minY,
    selfMax: self.maxY,
    otherMin: other.minY,
    otherMax: other.maxY,
    commonMin: common.minY,
    padding: padding.top,
    selfElement: selfElement.minY,
    otherElement: otherElement.maxY,
    separated: self.minX > other.maxX || self.maxX < other.minX,
  );

  final maxX = _computeMaxEdge(
    selfMin: self.minX,
    selfMax: self.maxX,
    otherMin: other.minX,
    otherMax: other.maxX,
    commonMax: common.maxX,
    padding: padding.right,
    selfElement: selfElement.maxX,
    otherElement: otherElement.minX,
    separated: self.minY > other.maxY || self.maxY < other.minY,
  );

  final maxY = _computeMaxEdge(
    selfMin: self.minY,
    selfMax: self.maxY,
    otherMin: other.minY,
    otherMax: other.maxY,
    commonMax: common.maxY,
    padding: padding.bottom,
    selfElement: selfElement.maxY,
    otherElement: otherElement.minY,
    separated: self.minX > other.maxX || self.maxX < other.minX,
  );

  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

double _computeMinEdge({
  required double selfMin,
  required double selfMax,
  required double otherMin,
  required double otherMax,
  required double commonMin,
  required double padding,
  required double selfElement,
  required double otherElement,
  required bool separated,
}) {
  if (selfMin > otherMax) {
    final split = (selfElement + otherElement) / 2;
    return separated ? math.min(split, selfMin - padding) : split;
  }
  if (selfMin > otherMin) {
    return selfMin - padding;
  }
  return commonMin - padding;
}

double _computeMaxEdge({
  required double selfMin,
  required double selfMax,
  required double otherMin,
  required double otherMax,
  required double commonMax,
  required double padding,
  required double selfElement,
  required double otherElement,
  required bool separated,
}) {
  if (selfMax < otherMin) {
    final split = (selfElement + otherElement) / 2;
    return separated ? math.max(split, selfMax + padding) : split;
  }
  if (selfMax < otherMax) {
    return selfMax + padding;
  }
  return commonMax + padding;
}

DrawRect _selectObstacleBounds({
  required _ResolvedEndpoint endpoint,
  required DrawRect baseBounds,
  required DrawRect dynamicBounds,
}) => _clampBounds(endpoint.isBound ? dynamicBounds : baseBounds);

({DrawRect start, DrawRect end}) _generateDynamicAabbs({
  required DrawRect start,
  required DrawRect end,
  required _BoundsPadding startPadding,
  required _BoundsPadding endPadding,
  DrawRect? startElementBounds,
  DrawRect? endElementBounds,
}) {
  final common = _unionBounds([start, end]);
  final startAabb = _dynamicAabbFor(
    self: start,
    other: end,
    common: common,
    padding: startPadding,
    selfElementBounds: startElementBounds,
    otherElementBounds: endElementBounds,
  );
  final endAabb = _dynamicAabbFor(
    self: end,
    other: start,
    common: common,
    padding: endPadding,
    selfElementBounds: endElementBounds,
    otherElementBounds: startElementBounds,
  );

  return (start: startAabb, end: endAabb);
}

_BoundsPadding _paddingFromHeading(
  ElbowHeading heading,
  double headOffset,
  double sideOffset,
) => switch (heading) {
  ElbowHeading.up => _BoundsPadding(
    top: headOffset,
    right: sideOffset,
    bottom: sideOffset,
    left: sideOffset,
  ),
  ElbowHeading.right => _BoundsPadding(
    top: sideOffset,
    right: headOffset,
    bottom: sideOffset,
    left: sideOffset,
  ),
  ElbowHeading.down => _BoundsPadding(
    top: sideOffset,
    right: sideOffset,
    bottom: headOffset,
    left: sideOffset,
  ),
  ElbowHeading.left => _BoundsPadding(
    top: sideOffset,
    right: sideOffset,
    bottom: sideOffset,
    left: headOffset,
  ),
};

@immutable
class _BoundsPadding {
  const _BoundsPadding({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  final double top;
  final double right;
  final double bottom;
  final double left;
}

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

@immutable
final class _ElbowObstacleLayout {
  const _ElbowObstacleLayout({
    required this.commonBounds,
    required this.startExit,
    required this.endExit,
    required this.obstacles,
  });

  final DrawRect commonBounds;
  final DrawPoint startExit;
  final DrawPoint endExit;
  final List<DrawRect> obstacles;
}

/// Start/end obstacle bounds with a precomputed overlap flag.
@immutable
final class _ElbowEndpointBounds {
  const _ElbowEndpointBounds({
    required this.start,
    required this.end,
    required this.overlaps,
  });

  final DrawRect start;
  final DrawRect end;
  final bool overlaps;
}

/// Builds the obstacle layout for a single routed elbow path.
///
/// Orchestrates endpoint bounds resolution, dynamic AABB expansion,
/// overlap splitting, spacing harmonization, and exit point computation
/// as a flat sequence of named steps.
_ElbowObstacleLayout _planObstacleLayout({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
}) {
  // 1. Resolve heading-aware bounds for each bound endpoint.
  final endpointBounds = _resolveEndpointBounds(start: start, end: end);

  // 2. Prefer point-sized bounds when endpoints overlap.
  final baseBounds = _resolveBaseBounds(
    boundsOverlap: endpointBounds.overlaps,
    startPoint: start.point,
    endPoint: end.point,
    startElbowBounds: endpointBounds.start,
    endElbowBounds: endpointBounds.end,
  );

  // 3. Pick padding based on heading/arrowhead configuration.
  final padding = _resolveLayoutPadding(
    boundsOverlap: endpointBounds.overlaps,
    start: start,
    end: end,
  );

  // 4. Expand the bounds to build the grid routing envelope.
  final dynamicAabbs = _generateDynamicAabbs(
    start: baseBounds.start,
    end: baseBounds.end,
    startPadding: padding.start,
    endPadding: padding.end,
    startElementBounds: _aabbElementBounds(
      boundsOverlap: endpointBounds.overlaps,
      isBound: start.isBound,
      elbowBounds: endpointBounds.start,
    ),
    endElementBounds: _aabbElementBounds(
      boundsOverlap: endpointBounds.overlaps,
      isBound: end.isBound,
      elbowBounds: endpointBounds.end,
    ),
  );

  // 5. Split overlapping obstacles and harmonize exit spacing.
  final obstacleBounds = _resolveObstacleBounds(
    start: start,
    end: end,
    startBaseBounds: baseBounds.start,
    endBaseBounds: baseBounds.end,
    startDynamic: dynamicAabbs.start,
    endDynamic: dynamicAabbs.end,
  );

  // 6. Derive shared bounds and exit points for the grid router.
  final commonBounds = _resolveCommonBounds(
    startObstacle: obstacleBounds.start,
    endObstacle: obstacleBounds.end,
  );
  final startExit = _exitPosition(
    bounds: obstacleBounds.start,
    heading: start.heading,
    point: start.point,
  );
  final endExit = _exitPosition(
    bounds: obstacleBounds.end,
    heading: end.heading,
    point: end.point,
  );

  return _ElbowObstacleLayout(
    commonBounds: commonBounds,
    startExit: startExit,
    endExit: endExit,
    obstacles: <DrawRect>[obstacleBounds.start, obstacleBounds.end],
  );
}

_ElbowEndpointBounds _resolveEndpointBounds({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
}) {
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

  return _ElbowEndpointBounds(
    start: startElbowBounds,
    end: endElbowBounds,
    overlaps: boundsOverlap,
  );
}

({DrawRect start, DrawRect end}) _resolveBaseBounds({
  required bool boundsOverlap,
  required DrawPoint startPoint,
  required DrawPoint endPoint,
  required DrawRect startElbowBounds,
  required DrawRect endElbowBounds,
}) {
  final startBaseBounds = boundsOverlap
      ? _pointBounds(startPoint, ElbowConstants.exitPointPadding)
      : startElbowBounds;
  final endBaseBounds = boundsOverlap
      ? _pointBounds(endPoint, ElbowConstants.exitPointPadding)
      : endElbowBounds;
  return (start: startBaseBounds, end: endBaseBounds);
}

({_BoundsPadding start, _BoundsPadding end}) _resolveLayoutPadding({
  required bool boundsOverlap,
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
}) {
  final startPadding = boundsOverlap
      ? _overlapPadding(start.heading)
      : _routingPadding(
          heading: start.heading,
          hasArrowhead: start.hasArrowhead,
        );
  final endPadding = boundsOverlap
      ? _overlapPadding(end.heading)
      : _routingPadding(heading: end.heading, hasArrowhead: end.hasArrowhead);
  return (start: startPadding, end: endPadding);
}

({DrawRect start, DrawRect end}) _resolveObstacleBounds({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
  required DrawRect startBaseBounds,
  required DrawRect endBaseBounds,
  required DrawRect startDynamic,
  required DrawRect endDynamic,
}) {
  var startObstacle = _selectObstacleBounds(
    endpoint: start,
    baseBounds: startBaseBounds,
    dynamicBounds: startDynamic,
  );
  var endObstacle = _selectObstacleBounds(
    endpoint: end,
    baseBounds: endBaseBounds,
    dynamicBounds: endDynamic,
  );
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

DrawRect _resolveCommonBounds({
  required DrawRect startObstacle,
  required DrawRect endObstacle,
}) => _clampBounds(
  _inflateBounds(
    _unionBounds([startObstacle, endObstacle]),
    ElbowConstants.basePadding,
  ),
);

DrawRect _clampObstacleToBoundsPadding({
  required _ResolvedEndpoint endpoint,
  required DrawRect obstacle,
}) {
  if (!endpoint.isBound || endpoint.elementBounds == null) {
    return obstacle;
  }
  final bounds = endpoint.elementBounds!;
  const padding = ElbowConstants.basePadding;

  // Clamp every side so the obstacle never extends further than
  // basePadding from the element bounds.  This keeps the gap between
  // routed segments and the element consistent regardless of which
  // side the endpoint heading points to.
  return obstacle.copyWith(
    minY: math.max(obstacle.minY, bounds.minY - padding),
    maxX: math.min(obstacle.maxX, bounds.maxX + padding),
    maxY: math.min(obstacle.maxY, bounds.maxY + padding),
    minX: math.max(obstacle.minX, bounds.minX - padding),
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
  if (startSpacing == null || endSpacing == null) {
    return (start: startObstacle, end: endObstacle);
  }

  final sharedSpacing = math.min(startSpacing, endSpacing);
  if (!sharedSpacing.isFinite) {
    return (start: startObstacle, end: endObstacle);
  }

  final minAllowedSpacing = math.max(
    ElbowSpacing.minBindingSpacing(hasArrowhead: start.hasArrowhead),
    ElbowSpacing.minBindingSpacing(hasArrowhead: end.hasArrowhead),
  );
  final resolvedSpacing = math.max(sharedSpacing, minAllowedSpacing);

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
