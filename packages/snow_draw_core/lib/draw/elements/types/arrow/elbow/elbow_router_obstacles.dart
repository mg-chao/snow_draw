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

({DrawRect start, DrawRect end}) _splitOverlappingHorizontally({
  required DrawRect startBounds,
  required DrawRect endBounds,
  required DrawRect startObstacle,
  required DrawRect endObstacle,
  required double splitX,
  required double overlapMinX,
  required double overlapMaxX,
  required bool startBeforeEnd,
}) {
  var minSplit = startBeforeEnd ? startBounds.maxX : endBounds.maxX;
  var maxSplit = startBeforeEnd ? endBounds.minX : startBounds.minX;
  if (maxSplit < minSplit) {
    minSplit = overlapMinX;
    maxSplit = overlapMaxX;
  }
  if (maxSplit - minSplit <= ElbowConstants.intersectionEpsilon) {
    return (start: startObstacle, end: endObstacle);
  }
  final clamped = splitX.clamp(minSplit, maxSplit);
  if (startBeforeEnd) {
    final nextStart = startObstacle.copyWith(
      maxX: math.min(startObstacle.maxX, clamped),
    );
    final nextEnd = endObstacle.copyWith(
      minX: math.max(endObstacle.minX, clamped),
    );
    return (start: nextStart, end: nextEnd);
  }

  final nextStart = startObstacle.copyWith(
    minX: math.max(startObstacle.minX, clamped),
  );
  final nextEnd = endObstacle.copyWith(
    maxX: math.min(endObstacle.maxX, clamped),
  );
  return (start: nextStart, end: nextEnd);
}

({DrawRect start, DrawRect end}) _splitOverlappingVertically({
  required DrawRect startBounds,
  required DrawRect endBounds,
  required DrawRect startObstacle,
  required DrawRect endObstacle,
  required double splitY,
  required double overlapMinY,
  required double overlapMaxY,
  required bool startBeforeEnd,
}) {
  var minSplit = startBeforeEnd ? startBounds.maxY : endBounds.maxY;
  var maxSplit = startBeforeEnd ? endBounds.minY : startBounds.minY;
  if (maxSplit < minSplit) {
    minSplit = overlapMinY;
    maxSplit = overlapMaxY;
  }
  if (maxSplit - minSplit <= ElbowConstants.intersectionEpsilon) {
    return (start: startObstacle, end: endObstacle);
  }
  final clamped = splitY.clamp(minSplit, maxSplit);
  if (startBeforeEnd) {
    final nextStart = startObstacle.copyWith(
      maxY: math.min(startObstacle.maxY, clamped),
    );
    final nextEnd = endObstacle.copyWith(
      minY: math.max(endObstacle.minY, clamped),
    );
    return (start: nextStart, end: nextEnd);
  }

  final nextStart = startObstacle.copyWith(
    minY: math.max(startObstacle.minY, clamped),
  );
  final nextEnd = endObstacle.copyWith(
    maxY: math.min(endObstacle.maxY, clamped),
  );
  return (start: nextStart, end: nextEnd);
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
    return _splitOverlappingHorizontally(
      startBounds: startBounds,
      endBounds: endBounds,
      startObstacle: startObstacle,
      endObstacle: endObstacle,
      splitX: splitX,
      overlapMinX: overlapMinX,
      overlapMaxX: overlapMaxX,
      startBeforeEnd: startCenter.x <= endCenter.x,
    );
  }

  final splitY = (startCenter.y + endCenter.y) / 2;
  return _splitOverlappingVertically(
    startBounds: startBounds,
    endBounds: endBounds,
    startObstacle: startObstacle,
    endObstacle: endObstacle,
    splitY: splitY,
    overlapMinY: overlapMinY,
    overlapMaxY: overlapMaxY,
    startBeforeEnd: startCenter.y <= endCenter.y,
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
  // Expand each obstacle by a heading-aware padding and a separation split.
  final selfElement = selfElementBounds ?? self;
  final otherElement = otherElementBounds ?? other;
  final separatedX = self.minX > other.maxX || self.maxX < other.minX;
  final separatedY = self.minY > other.maxY || self.maxY < other.minY;
  final splitFromRight = (selfElement.minX + otherElement.maxX) / 2;
  final splitFromLeft = (selfElement.maxX + otherElement.minX) / 2;
  final splitFromBottom = (selfElement.minY + otherElement.maxY) / 2;
  final splitFromTop = (selfElement.maxY + otherElement.minY) / 2;

  double minX;
  if (self.minX > other.maxX) {
    minX = separatedY
        ? math.min(splitFromRight, self.minX - padding.left)
        : splitFromRight;
  } else if (self.minX > other.minX) {
    minX = self.minX - padding.left;
  } else {
    minX = common.minX - padding.left;
  }

  double minY;
  if (self.minY > other.maxY) {
    minY = separatedX
        ? math.min(splitFromBottom, self.minY - padding.top)
        : splitFromBottom;
  } else if (self.minY > other.minY) {
    minY = self.minY - padding.top;
  } else {
    minY = common.minY - padding.top;
  }

  double maxX;
  if (self.maxX < other.minX) {
    maxX = separatedY
        ? math.max(splitFromLeft, self.maxX + padding.right)
        : splitFromLeft;
  } else if (self.maxX < other.maxX) {
    maxX = self.maxX + padding.right;
  } else {
    maxX = common.maxX + padding.right;
  }

  double maxY;
  if (self.maxY < other.minY) {
    maxY = separatedX
        ? math.max(splitFromTop, self.maxY + padding.bottom)
        : splitFromTop;
  } else if (self.maxY < other.maxY) {
    maxY = self.maxY + padding.bottom;
  } else {
    maxY = common.maxY + padding.bottom;
  }

  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
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
}) {
  switch (heading) {
    case ElbowHeading.up:
      return DrawPoint(x: point.x, y: bounds.minY);
    case ElbowHeading.right:
      return DrawPoint(x: bounds.maxX, y: point.y);
    case ElbowHeading.down:
      return DrawPoint(x: point.x, y: bounds.maxY);
    case ElbowHeading.left:
      return DrawPoint(x: bounds.minX, y: point.y);
  }
}

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
@immutable
final class _ElbowObstacleLayoutBuilder {
  const _ElbowObstacleLayoutBuilder({required this.start, required this.end});

  final _ResolvedEndpoint start;
  final _ResolvedEndpoint end;

  _ElbowObstacleLayout resolve() {
    // Step 2: build padded obstacle bounds and exit points for routing.
    // 2a) Resolve heading-aware bounds for each bound endpoint.
    final endpointBounds = _resolveEndpointBounds(start: start, end: end);
    // 2b) Prefer point-sized bounds when endpoints overlap.
    final baseBounds = _resolveBaseBounds(
      boundsOverlap: endpointBounds.overlaps,
      startPoint: start.point,
      endPoint: end.point,
      startElbowBounds: endpointBounds.start,
      endElbowBounds: endpointBounds.end,
    );
    // 2c) Pick padding based on heading/arrowhead configuration.
    final padding = _resolveLayoutPadding(
      boundsOverlap: endpointBounds.overlaps,
      start: start,
      end: end,
    );

    // 2d) Expand the bounds to build the grid routing envelope.
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

    // 2e) Split overlapping obstacles to keep a passage open.
    final obstacleBounds = _resolveObstacleBounds(
      start: start,
      end: end,
      startBaseBounds: baseBounds.start,
      endBaseBounds: baseBounds.end,
      startDynamic: dynamicAabbs.start,
      endDynamic: dynamicAabbs.end,
    );

    // 2f) Derive shared bounds and exit points for the grid router.
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

  startObstacle = _clampObstacleExitToBasePadding(
    endpoint: start,
    obstacle: startObstacle,
  );
  endObstacle = _clampObstacleExitToBasePadding(
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

DrawRect _clampObstacleExitToBasePadding({
  required _ResolvedEndpoint endpoint,
  required DrawRect obstacle,
}) {
  if (!endpoint.isBound || endpoint.elementBounds == null) {
    return obstacle;
  }
  final bounds = endpoint.elementBounds!;
  switch (endpoint.heading) {
    case ElbowHeading.up:
      final target = bounds.minY - ElbowConstants.basePadding;
      if (obstacle.minY >= target) {
        return obstacle;
      }
      return obstacle.copyWith(minY: target);
    case ElbowHeading.right:
      final target = bounds.maxX + ElbowConstants.basePadding;
      if (obstacle.maxX <= target) {
        return obstacle;
      }
      return obstacle.copyWith(maxX: target);
    case ElbowHeading.down:
      final target = bounds.maxY + ElbowConstants.basePadding;
      if (obstacle.maxY <= target) {
        return obstacle;
      }
      return obstacle.copyWith(maxY: target);
    case ElbowHeading.left:
      final target = bounds.minX - ElbowConstants.basePadding;
      if (obstacle.minX >= target) {
        return obstacle;
      }
      return obstacle.copyWith(minX: target);
  }
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

  final startSpacing = _resolveObstacleSpacing(
    elementBounds: startBounds,
    obstacle: startObstacle,
    heading: start.heading,
  );
  final endSpacing = _resolveObstacleSpacing(
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
    _minBindingSpacing(hasArrowhead: start.hasArrowhead),
    _minBindingSpacing(hasArrowhead: end.hasArrowhead),
  );
  final resolvedSpacing = math.max(sharedSpacing, minAllowedSpacing);

  return (
    start: _clampBounds(
      _applyObstacleSpacing(
        obstacle: startObstacle,
        elementBounds: startBounds,
        heading: start.heading,
        spacing: resolvedSpacing,
      ),
    ),
    end: _clampBounds(
      _applyObstacleSpacing(
        obstacle: endObstacle,
        elementBounds: endBounds,
        heading: end.heading,
        spacing: resolvedSpacing,
      ),
    ),
  );
}

double? _resolveObstacleSpacing({
  required DrawRect elementBounds,
  required DrawRect obstacle,
  required ElbowHeading heading,
}) {
  final spacing = switch (heading) {
    ElbowHeading.up => elementBounds.minY - obstacle.minY,
    ElbowHeading.right => obstacle.maxX - elementBounds.maxX,
    ElbowHeading.down => obstacle.maxY - elementBounds.maxY,
    ElbowHeading.left => elementBounds.minX - obstacle.minX,
  };
  if (!spacing.isFinite || spacing <= ElbowConstants.intersectionEpsilon) {
    return null;
  }
  return spacing;
}

DrawRect _applyObstacleSpacing({
  required DrawRect obstacle,
  required DrawRect elementBounds,
  required ElbowHeading heading,
  required double spacing,
}) => switch (heading) {
  ElbowHeading.up => obstacle.copyWith(minY: elementBounds.minY - spacing),
  ElbowHeading.right => obstacle.copyWith(maxX: elementBounds.maxX + spacing),
  ElbowHeading.down => obstacle.copyWith(maxY: elementBounds.maxY + spacing),
  ElbowHeading.left => obstacle.copyWith(minX: elementBounds.minX - spacing),
};

double _minBindingSpacing({required bool hasArrowhead}) {
  final base = ArrowBindingUtils.elbowBindingGapBase;
  if (!hasArrowhead) {
    return base;
  }
  return base * ArrowBindingUtils.elbowArrowheadGapMultiplier;
}

_ElbowObstacleLayout _planObstacleLayout({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
}) => _ElbowObstacleLayoutBuilder(start: start, end: end).resolve();
