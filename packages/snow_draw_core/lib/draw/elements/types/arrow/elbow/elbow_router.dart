import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../../core/coordinates/element_space.dart';
import '../../../../models/element_state.dart';
import '../../../../types/draw_point.dart';
import '../../../../types/draw_rect.dart';
import '../../../../types/element_style.dart';
import '../../../../utils/selection_calculator.dart';
import '../arrow_binding.dart';
import '../arrow_data.dart';
import '../arrow_geometry.dart';
import 'elbow_geometry.dart';
import 'elbow_heading.dart';

export 'elbow_heading.dart';

const double _basePadding = 42;
const double _dedupThreshold = 1;
const double _minArrowLength = 8;
const double _maxPosition = 1000000;
const double _donglePointPadding = 2;
const double _elbowNoArrowheadGapMultiplier = 2;
const double _elementSidePadding = 8;
const _intersectionEpsilon = 1e-6;

/// Elbow routing overview:
/// 1) Resolve bindings into concrete endpoints + headings.
/// 2) Build padded obstacle bounds around bound elements.
/// 3) Attempt a direct orthogonal route when aligned.
/// 4) Route via a sparse grid (A*) when detours are needed.
/// 5) Post-process to keep only orthogonal corner points.
/// Routing result in world space (with resolved endpoints).
@immutable
final class ElbowRouteResult {
  const ElbowRouteResult({
    required this.points,
    required this.startPoint,
    required this.endPoint,
  });

  final List<DrawPoint> points;
  final DrawPoint startPoint;
  final DrawPoint endPoint;
}

/// Local + world points for an element-routed elbow arrow.
@immutable
final class ElbowRoutedPoints {
  const ElbowRoutedPoints({
    required this.localPoints,
    required this.worldPoints,
  });

  final List<DrawPoint> localPoints;
  final List<DrawPoint> worldPoints;
}

ElbowHeading _vectorToHeading(double dx, double dy) {
  final absX = dx.abs();
  final absY = dy.abs();
  if (absX >= absY) {
    return dx >= 0 ? ElbowHeading.right : ElbowHeading.left;
  }
  return dy >= 0 ? ElbowHeading.down : ElbowHeading.up;
}

@immutable
final class _EndpointInfo {
  const _EndpointInfo({
    required this.point,
    required this.element,
    required this.elementBounds,
    required this.anchor,
  });

  final DrawPoint point;
  final ElementState? element;
  final DrawRect? elementBounds;
  final DrawPoint? anchor;

  bool get isBound => element != null;
  DrawPoint get anchorOrPoint => anchor ?? point;
}

_EndpointInfo _unboundEndpointInfo(DrawPoint point) => _EndpointInfo(
  point: point,
  element: null,
  elementBounds: null,
  anchor: null,
);

_EndpointInfo _resolveEndpointInfo({
  required DrawPoint point,
  required ArrowBinding? binding,
  required Map<String, ElementState> elementsById,
  required bool hasArrowhead,
}) {
  if (binding == null) {
    return _unboundEndpointInfo(point);
  }
  final element = elementsById[binding.elementId];
  if (element == null) {
    return _unboundEndpointInfo(point);
  }

  final resolved =
      ArrowBindingUtils.resolveElbowBoundPoint(
        binding: binding,
        target: element,
        hasArrowhead: hasArrowhead,
      ) ??
      point;
  final anchor = ArrowBindingUtils.resolveElbowAnchorPoint(
    binding: binding,
    target: element,
  );
  final bounds = SelectionCalculator.computeElementWorldAabb(element);
  return _EndpointInfo(
    point: resolved,
    element: element,
    elementBounds: bounds,
    anchor: anchor,
  );
}

ElbowHeading _resolveEndpointHeading({
  required DrawRect? elementBounds,
  required DrawPoint point,
  required DrawPoint? anchor,
  required ElbowHeading fallback,
}) {
  if (elementBounds == null) {
    return fallback;
  }
  return ElbowGeometry.headingForPointOnBounds(elementBounds, anchor ?? point);
}

@immutable
final class _ResolvedEndpoint {
  const _ResolvedEndpoint({
    required this.info,
    required this.heading,
    required this.hasArrowhead,
  });

  final _EndpointInfo info;
  final ElbowHeading heading;
  final bool hasArrowhead;

  DrawPoint get point => info.point;
  DrawRect? get elementBounds => info.elementBounds;
  bool get isBound => info.isBound;
  DrawPoint get anchorOrPoint => info.anchorOrPoint;
}

@immutable
final class _ResolvedEndpoints {
  const _ResolvedEndpoints({
    required this.start,
    required this.end,
  });

  final _ResolvedEndpoint start;
  final _ResolvedEndpoint end;
}

_ResolvedEndpoints _resolveRouteEndpoints({
  required DrawPoint start,
  required DrawPoint end,
  required Map<String, ElementState> elementsById,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
}) {
  // Step 1: resolve bindings, arrowhead gaps, and endpoint headings.
  ElbowHeading _resolveHeadingFor(
    _EndpointInfo info,
    ElbowHeading fallback,
  ) => _resolveEndpointHeading(
    elementBounds: info.elementBounds,
    point: info.point,
    anchor: info.anchor,
    fallback: fallback,
  );

  final hasStartArrowhead = startArrowhead != ArrowheadStyle.none;
  final hasEndArrowhead = endArrowhead != ArrowheadStyle.none;
  final startInfo = _resolveEndpointInfo(
    point: start,
    binding: startBinding,
    elementsById: elementsById,
    hasArrowhead: hasStartArrowhead,
  );
  final endInfo = _resolveEndpointInfo(
    point: end,
    binding: endBinding,
    elementsById: elementsById,
    hasArrowhead: hasEndArrowhead,
  );

  final startPoint = startInfo.point;
  final endPoint = endInfo.point;

  final vectorHeading = _vectorToHeading(
    endPoint.x - startPoint.x,
    endPoint.y - startPoint.y,
  );
  final reverseVectorHeading = _vectorToHeading(
    startPoint.x - endPoint.x,
    startPoint.y - endPoint.y,
  );
  final startHeading = _resolveHeadingFor(startInfo, vectorHeading);
  final endHeading = _resolveHeadingFor(endInfo, reverseVectorHeading);

  return _ResolvedEndpoints(
    start: _ResolvedEndpoint(
      info: startInfo,
      heading: startHeading,
      hasArrowhead: hasStartArrowhead,
    ),
    end: _ResolvedEndpoint(
      info: endInfo,
      heading: endHeading,
      hasArrowhead: hasEndArrowhead,
    ),
  );
}

double _manhattanDistance(DrawPoint a, DrawPoint b) =>
    (a.x - b.x).abs() + (a.y - b.y).abs();

DrawRect _inflateBounds(DrawRect rect, double padding) => DrawRect(
  minX: rect.minX - padding,
  minY: rect.minY - padding,
  maxX: rect.maxX + padding,
  maxY: rect.maxY + padding,
);

DrawRect _clampBounds(DrawRect rect) => DrawRect(
  minX: rect.minX.clamp(-_maxPosition, _maxPosition),
  minY: rect.minY.clamp(-_maxPosition, _maxPosition),
  maxX: rect.maxX.clamp(-_maxPosition, _maxPosition),
  maxY: rect.maxY.clamp(-_maxPosition, _maxPosition),
);

DrawPoint _clampPoint(DrawPoint point) => DrawPoint(
  x: point.x.clamp(-_maxPosition, _maxPosition),
  y: point.y.clamp(-_maxPosition, _maxPosition),
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
  if (maxSplit - minSplit <= _intersectionEpsilon) {
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
  if (maxSplit - minSplit <= _intersectionEpsilon) {
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

double _arrowheadGapMultiplier(bool hasArrowhead) => hasArrowhead
    ? ArrowBindingUtils.elbowArrowheadGapMultiplier
    : _elbowNoArrowheadGapMultiplier;

double _arrowheadGap(bool hasArrowhead) =>
    ArrowBindingUtils.elbowBindingGapBase *
    _arrowheadGapMultiplier(hasArrowhead);

double _headPadding(bool hasArrowhead) {
  final padding = _basePadding - _arrowheadGap(hasArrowhead);
  return math.max(0, padding);
}

DrawRect _elementBoundsForElbow({
  required DrawPoint point,
  required DrawRect? elementBounds,
  required ElbowHeading heading,
  required bool hasArrowhead,
}) {
  if (elementBounds == null) {
    return _pointBounds(point, 0);
  }

  final headOffset = _arrowheadGap(hasArrowhead);
  final padding = _paddingFromHeading(heading, headOffset, _elementSidePadding);
  return DrawRect(
    minX: elementBounds.minX - padding.left,
    minY: elementBounds.minY - padding.top,
    maxX: elementBounds.maxX + padding.right,
    maxY: elementBounds.maxY + padding.bottom,
  );
}

_BoundsPadding _overlapPadding(ElbowHeading heading) =>
    _paddingFromHeading(heading, _basePadding, 0);

_BoundsPadding _routingPadding({
  required ElbowHeading heading,
  required bool hasArrowhead,
}) => _paddingFromHeading(heading, _headPadding(hasArrowhead), _basePadding);

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

DrawPoint _donglePosition({
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
final class _ObstacleLayout {
  const _ObstacleLayout({
    required this.commonBounds,
    required this.startDongle,
    required this.endDongle,
    required this.obstacles,
  });

  final DrawRect commonBounds;
  final DrawPoint startDongle;
  final DrawPoint endDongle;
  final List<DrawRect> obstacles;
}

({
  DrawRect startElbowBounds,
  DrawRect endElbowBounds,
  bool boundsOverlap,
}) _elbowBoundsForLayout({
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

  final boundsOverlap = start.isBound &&
      end.isBound &&
      _boundsOverlap(startElbowBounds, endElbowBounds);

  return (
    startElbowBounds: startElbowBounds,
    endElbowBounds: endElbowBounds,
    boundsOverlap: boundsOverlap,
  );
}

({DrawRect start, DrawRect end}) _baseBoundsForLayout({
  required bool boundsOverlap,
  required DrawPoint startPoint,
  required DrawPoint endPoint,
  required DrawRect startElbowBounds,
  required DrawRect endElbowBounds,
}) {
  final startBaseBounds = boundsOverlap
      ? _pointBounds(startPoint, _donglePointPadding)
      : startElbowBounds;
  final endBaseBounds = boundsOverlap
      ? _pointBounds(endPoint, _donglePointPadding)
      : endElbowBounds;
  return (start: startBaseBounds, end: endBaseBounds);
}

({_BoundsPadding start, _BoundsPadding end}) _layoutPaddingFor({
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
      : _routingPadding(
          heading: end.heading,
          hasArrowhead: end.hasArrowhead,
        );
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

  return (start: startObstacle, end: endObstacle);
}

DrawRect _commonBoundsForObstacles({
  required DrawRect startObstacle,
  required DrawRect endObstacle,
}) =>
    _clampBounds(
      _inflateBounds(
        _unionBounds([startObstacle, endObstacle]),
        _basePadding,
      ),
    );

_ObstacleLayout _buildObstacleLayout({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
}) {
  // Step 2: build padded obstacle bounds and dongle points for routing.
  final elbowBounds = _elbowBoundsForLayout(start: start, end: end);
  final baseBounds = _baseBoundsForLayout(
    boundsOverlap: elbowBounds.boundsOverlap,
    startPoint: start.point,
    endPoint: end.point,
    startElbowBounds: elbowBounds.startElbowBounds,
    endElbowBounds: elbowBounds.endElbowBounds,
  );
  final padding = _layoutPaddingFor(
    boundsOverlap: elbowBounds.boundsOverlap,
    start: start,
    end: end,
  );

  final dynamicAabbs = _generateDynamicAabbs(
    start: baseBounds.start,
    end: baseBounds.end,
    startPadding: padding.start,
    endPadding: padding.end,
    startElementBounds: _aabbElementBounds(
      boundsOverlap: elbowBounds.boundsOverlap,
      isBound: start.isBound,
      elbowBounds: elbowBounds.startElbowBounds,
    ),
    endElementBounds: _aabbElementBounds(
      boundsOverlap: elbowBounds.boundsOverlap,
      isBound: end.isBound,
      elbowBounds: elbowBounds.endElbowBounds,
    ),
  );

  final obstacleBounds = _resolveObstacleBounds(
    start: start,
    end: end,
    startBaseBounds: baseBounds.start,
    endBaseBounds: baseBounds.end,
    startDynamic: dynamicAabbs.start,
    endDynamic: dynamicAabbs.end,
  );

  final commonBounds = _commonBoundsForObstacles(
    startObstacle: obstacleBounds.start,
    endObstacle: obstacleBounds.end,
  );

  final startDongle = _donglePosition(
    bounds: obstacleBounds.start,
    heading: start.heading,
    point: start.point,
  );
  final endDongle = _donglePosition(
    bounds: obstacleBounds.end,
    heading: end.heading,
    point: end.point,
  );

  return _ObstacleLayout(
    commonBounds: commonBounds,
    startDongle: startDongle,
    endDongle: endDongle,
    obstacles: <DrawRect>[obstacleBounds.start, obstacleBounds.end],
  );
}

List<DrawPoint> _routeViaGrid({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
  required DrawPoint startDongle,
  required DrawPoint endDongle,
  required DrawRect commonBounds,
  required List<DrawRect> obstacles,
}) {
  // Step 4: route through a sparse grid using A* with bend penalties.
  final grid = _buildGrid(
    obstacles: obstacles,
    start: startDongle,
    startHeading: start.heading,
    end: endDongle,
    endHeading: end.heading,
    bounds: commonBounds,
  );

  final path = _tryRouteGridPath(
    grid: grid,
    start: start,
    end: end,
    startDongle: startDongle,
    endDongle: endDongle,
    obstacles: obstacles,
  );

  return path == null
      ? _fallbackPath(
          start: start.point,
          end: end.point,
          startHeading: start.heading,
        )
      : _postProcessPath(
          path: path,
          startPoint: start.point,
          endPoint: end.point,
          startDongle: startDongle,
          endDongle: endDongle,
        );
}

List<DrawPoint> _finalizeRoutedPath({
  required List<DrawPoint> points,
  required ElbowHeading startHeading,
}) {
  // Step 5: enforce orthogonality, remove tiny segments, and clamp.
  final orthogonalized = _ensureOrthogonalPath(
    points: points,
    startHeading: startHeading,
  );
  final cleaned = _getCornerPoints(_removeShortSegments(orthogonalized));
  return cleaned.map(_clampPoint).toList(growable: false);
}

final class _ElbowRoutePlanner {
  const _ElbowRoutePlanner({
    required this.start,
    required this.end,
  });

  final _ResolvedEndpoint start;
  final _ResolvedEndpoint end;

  List<DrawPoint> route() {
    // Step 0: if nothing is bound, prefer the simple fallback path.
    if (_usesFallbackPath) {
      return _fallbackPath(
        start: start.point,
        end: end.point,
        startHeading: start.heading,
      );
    }

    // Step 2: derive obstacles and try the shortest possible route first.
    final layout = _buildObstacleLayout(start: start, end: end);
    final direct = _tryDirectRoute(layout);
    if (direct != null) {
      return direct;
    }

    // Step 3/4: route around obstacles via the grid, then clean up.
    final routed = _routeViaGrid(
      start: start,
      end: end,
      startDongle: layout.startDongle,
      endDongle: layout.endDongle,
      commonBounds: layout.commonBounds,
      obstacles: layout.obstacles,
    );

    return _finalizeRoutedPath(points: routed, startHeading: start.heading);
  }

  bool get _usesFallbackPath => !start.isBound && !end.isBound;

  List<DrawPoint>? _tryDirectRoute(_ObstacleLayout layout) =>
      _directPathIfClear(
        start: start.point,
        end: end.point,
        obstacles: layout.obstacles,
        startHeading: start.heading,
        endHeading: end.heading,
        startConstrained: start.isBound,
        endConstrained: end.isBound,
      );
}

ElbowRouteResult _buildRouteResult({
  required DrawPoint startPoint,
  required DrawPoint endPoint,
  required List<DrawPoint> points,
}) => ElbowRouteResult(
  points: points,
  startPoint: startPoint,
  endPoint: endPoint,
);

/// Routes an elbow arrow in world space.
///
/// The returned points are orthogonal, avoid bound element obstacles, and
/// respect arrowhead spacing for bound endpoints.
ElbowRouteResult routeElbowArrow({
  required DrawPoint start,
  required DrawPoint end,
  required Map<String, ElementState> elementsById,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
  ArrowheadStyle startArrowhead = ArrowheadStyle.none,
  ArrowheadStyle endArrowhead = ArrowheadStyle.none,
}) {
  // Step 1: resolve bindings/headings into concrete endpoints.
  final endpoints = _resolveRouteEndpoints(
    start: start,
    end: end,
    elementsById: elementsById,
    startBinding: startBinding,
    endBinding: endBinding,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );
  final startEndpoint = endpoints.start;
  final endEndpoint = endpoints.end;
  final startPoint = startEndpoint.point;
  final endPoint = endEndpoint.point;

  // Steps 2-5: plan + route + post-process the elbow path.
  final routed = _ElbowRoutePlanner(
    start: startEndpoint,
    end: endEndpoint,
  ).route();

  return _buildRouteResult(
    startPoint: startPoint,
    endPoint: endPoint,
    points: routed,
  );
}

/// Routes an elbow arrow for an element and returns both local + world points.
ElbowRoutedPoints routeElbowArrowForElement({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  DrawPoint? startOverride,
  DrawPoint? endOverride,
}) {
  final basePoints = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  ).map((point) => DrawPoint(x: point.dx, y: point.dy)).toList();
  final localStart = startOverride ?? basePoints.first;
  final localEnd = endOverride ?? basePoints.last;

  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  final worldStart = space.toWorld(localStart);
  final worldEnd = space.toWorld(localEnd);

  final routed = routeElbowArrow(
    start: worldStart,
    end: worldEnd,
    startBinding: data.startBinding,
    endBinding: data.endBinding,
    elementsById: elementsById,
    startArrowhead: data.startArrowhead,
    endArrowhead: data.endArrowhead,
  );

  final localPoints = routed.points
      .map(space.fromWorld)
      .toList(growable: false);

  return ElbowRoutedPoints(
    localPoints: localPoints,
    worldPoints: routed.points,
  );
}

({bool alignedX, bool alignedY}) _axisAlignment(
  DrawPoint start,
  DrawPoint end,
) => (
  alignedX: (start.x - end.x).abs() <= _dedupThreshold,
  alignedY: (start.y - end.y).abs() <= _dedupThreshold,
);

bool _headingsCompatibleWithAlignment({
  required bool alignedX,
  required bool alignedY,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
}) {
  if (alignedY && (!startHeading.isHorizontal || !endHeading.isHorizontal)) {
    return false;
  }
  if (alignedX && (startHeading.isHorizontal || endHeading.isHorizontal)) {
    return false;
  }
  return true;
}

bool _segmentRespectsEndpointConstraints({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required bool startConstrained,
  required bool endConstrained,
}) {
  final segmentHeading = _segmentHeading(start, end);
  if (startConstrained && segmentHeading != startHeading) {
    return false;
  }
  if (endConstrained && segmentHeading != endHeading.opposite) {
    return false;
  }
  return true;
}

List<DrawPoint>? _directPathIfClear({
  required DrawPoint start,
  required DrawPoint end,
  required List<DrawRect> obstacles,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required bool startConstrained,
  required bool endConstrained,
}) {
  final alignment = _axisAlignment(start, end);
  if (!alignment.alignedX && !alignment.alignedY) {
    return null;
  }
  if (!_headingsCompatibleWithAlignment(
    alignedX: alignment.alignedX,
    alignedY: alignment.alignedY,
    startHeading: startHeading,
    endHeading: endHeading,
  )) {
    return null;
  }

  if (!_segmentRespectsEndpointConstraints(
    start: start,
    end: end,
    startHeading: startHeading,
    endHeading: endHeading,
    startConstrained: startConstrained,
    endConstrained: endConstrained,
  )) {
    return null;
  }

  if (_segmentIntersectsAnyBounds(start, end, obstacles)) {
    return null;
  }
  return [start, end];
}

bool _segmentIntersectsBounds(DrawPoint start, DrawPoint end, DrawRect bounds) {
  final innerBounds = _shrinkBounds(bounds, _intersectionEpsilon);
  if (!_hasArea(innerBounds)) {
    return false;
  }

  final dx = (start.x - end.x).abs();
  final dy = (start.y - end.y).abs();
  if (dx <= _dedupThreshold) {
    return _verticalSegmentIntersectsBounds(start, end, innerBounds);
  }
  if (dy <= _dedupThreshold) {
    return _horizontalSegmentIntersectsBounds(start, end, innerBounds);
  }
  return _diagonalSegmentIntersectsBounds(start, end, innerBounds);
}

DrawRect _shrinkBounds(DrawRect bounds, double inset) => DrawRect(
  minX: bounds.minX + inset,
  minY: bounds.minY + inset,
  maxX: bounds.maxX - inset,
  maxY: bounds.maxY - inset,
);

bool _hasArea(DrawRect bounds) =>
    bounds.minX < bounds.maxX && bounds.minY < bounds.maxY;

double _overlapLength(
  double minA,
  double maxA,
  double minB,
  double maxB,
) => math.min(maxA, maxB) - math.max(minA, minB);

bool _verticalSegmentIntersectsBounds(
  DrawPoint start,
  DrawPoint end,
  DrawRect bounds,
) {
  final x = (start.x + end.x) / 2;
  if (x < bounds.minX || x > bounds.maxX) {
    return false;
  }
  final segMinY = math.min(start.y, end.y);
  final segMaxY = math.max(start.y, end.y);
  return _overlapLength(segMinY, segMaxY, bounds.minY, bounds.maxY) >
      _intersectionEpsilon;
}

bool _horizontalSegmentIntersectsBounds(
  DrawPoint start,
  DrawPoint end,
  DrawRect bounds,
) {
  final y = (start.y + end.y) / 2;
  if (y < bounds.minY || y > bounds.maxY) {
    return false;
  }
  final segMinX = math.min(start.x, end.x);
  final segMaxX = math.max(start.x, end.x);
  return _overlapLength(segMinX, segMaxX, bounds.minX, bounds.maxX) >
      _intersectionEpsilon;
}

bool _diagonalSegmentIntersectsBounds(
  DrawPoint start,
  DrawPoint end,
  DrawRect bounds,
) {
  final segMinX = math.min(start.x, end.x);
  final segMaxX = math.max(start.x, end.x);
  final segMinY = math.min(start.y, end.y);
  final segMaxY = math.max(start.y, end.y);
  if (segMaxX < bounds.minX ||
      segMinX > bounds.maxX ||
      segMaxY < bounds.minY ||
      segMinY > bounds.maxY) {
    return false;
  }
  return true;
}

List<DrawPoint> _fallbackPath({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowHeading startHeading,
}) {
  if (_manhattanDistance(start, end) < _minArrowLength) {
    final midY = (start.y + end.y) / 2;
    return [
      start,
      DrawPoint(x: start.x, y: midY),
      DrawPoint(x: end.x, y: midY),
      end,
    ];
  }

  if ((start.x - end.x).abs() <= _dedupThreshold ||
      (start.y - end.y).abs() <= _dedupThreshold) {
    return [start, end];
  }

  if (startHeading.isHorizontal) {
    final midX = (start.x + end.x) / 2;
    return [
      start,
      DrawPoint(x: midX, y: start.y),
      DrawPoint(x: midX, y: end.y),
      end,
    ];
  }

  final midY = (start.y + end.y) / 2;
  return [
    start,
    DrawPoint(x: start.x, y: midY),
    DrawPoint(x: end.x, y: midY),
    end,
  ];
}

List<DrawPoint> _postProcessPath({
  required List<_GridNode> path,
  required DrawPoint startPoint,
  required DrawPoint endPoint,
  required DrawPoint startDongle,
  required DrawPoint endDongle,
}) {
  if (path.isEmpty) {
    return [startPoint, endPoint];
  }
  final points = <DrawPoint>[];
  if (startDongle != startPoint && path.first.pos != startPoint) {
    points.add(startPoint);
  }
  for (final node in path) {
    points.add(node.pos);
  }
  if (endDongle != endPoint && points.last != endPoint) {
    points.add(endPoint);
  }
  return points;
}

List<DrawPoint> _removeShortSegments(List<DrawPoint> points) {
  if (points.length < 4) {
    return points;
  }
  final filtered = <DrawPoint>[];
  for (var i = 0; i < points.length; i++) {
    if (i == 0 || i == points.length - 1) {
      filtered.add(points[i]);
      continue;
    }
    if (_manhattanDistance(points[i - 1], points[i]) > _dedupThreshold) {
      filtered.add(points[i]);
    }
  }
  return filtered;
}

List<DrawPoint> _getCornerPoints(List<DrawPoint> points) {
  if (points.length <= 2) {
    return points;
  }

  var previousIsHorizontal = _isHorizontal(points[0], points[1]);
  final result = <DrawPoint>[points.first];
  for (var i = 1; i < points.length - 1; i++) {
    final nextIsHorizontal = _isHorizontal(points[i], points[i + 1]);
    if (previousIsHorizontal != nextIsHorizontal) {
      result.add(points[i]);
    }
    previousIsHorizontal = nextIsHorizontal;
  }
  result.add(points.last);
  return result;
}

@immutable
class _Grid {
  const _Grid({
    required this.rows,
    required this.cols,
    required this.nodes,
    required this.xIndex,
    required this.yIndex,
  });

  final int rows;
  final int cols;
  final List<_GridNode> nodes;
  final Map<double, int> xIndex;
  final Map<double, int> yIndex;

  _GridNode? nodeAt(int col, int row) {
    if (col < 0 || row < 0 || col >= cols || row >= rows) {
      return null;
    }
    return nodes[row * cols + col];
  }

  _GridNode? nodeForPoint(DrawPoint point) {
    final col = xIndex[point.x];
    final row = yIndex[point.y];
    if (col == null || row == null) {
      return null;
    }
    return nodeAt(col, row);
  }
}

class _GridNode {
  _GridNode({required this.pos, required this.addr});

  final DrawPoint pos;
  final _GridAddress addr;
  double f = 0;
  double g = 0;
  double h = 0;
  var closed = false;
  var visited = false;
  _GridNode? parent;
}

@immutable
class _GridAddress {
  const _GridAddress({required this.col, required this.row});

  final int col;
  final int row;
}

void _addBoundsToAxes(Set<double> xs, Set<double> ys, DrawRect bounds) {
  xs
    ..add(bounds.minX)
    ..add(bounds.maxX);
  ys
    ..add(bounds.minY)
    ..add(bounds.maxY);
}

void _addPointToAxes(Set<double> xs, Set<double> ys, DrawPoint point) {
  xs.add(point.x);
  ys.add(point.y);
}

Map<double, int> _buildAxisIndex(List<double> sortedAxis) => <double, int>{
  for (var i = 0; i < sortedAxis.length; i++) sortedAxis[i]: i,
};

_Grid _buildGrid({
  required List<DrawRect> obstacles,
  required DrawPoint start,
  required ElbowHeading startHeading,
  required DrawPoint end,
  required ElbowHeading endHeading,
  required DrawRect bounds,
}) {
  // Build a sparse grid from obstacle edges + endpoints for A* routing.
  final xs = <double>{};
  final ys = <double>{};

  for (final obstacle in obstacles) {
    _addBoundsToAxes(xs, ys, obstacle);
  }

  _addPointToAxes(xs, ys, start);
  _addPointToAxes(xs, ys, end);

  _addBoundsToAxes(xs, ys, bounds);

  if (startHeading.isHorizontal) {
    ys.add(start.y);
  } else {
    xs.add(start.x);
  }
  if (endHeading.isHorizontal) {
    ys.add(end.y);
  } else {
    xs.add(end.x);
  }

  final sortedX = xs.toList()..sort();
  final sortedY = ys.toList()..sort();
  final xIndex = _buildAxisIndex(sortedX);
  final yIndex = _buildAxisIndex(sortedY);

  final nodes = <_GridNode>[];
  for (var row = 0; row < sortedY.length; row++) {
    for (var col = 0; col < sortedX.length; col++) {
      nodes.add(
        _GridNode(
          pos: DrawPoint(x: sortedX[col], y: sortedY[row]),
          addr: _GridAddress(col: col, row: row),
        ),
      );
    }
  }

  return _Grid(
    rows: sortedY.length,
    cols: sortedX.length,
    nodes: nodes,
    xIndex: xIndex,
    yIndex: yIndex,
  );
}

@immutable
class _BendPenalty {
  const _BendPenalty(double base)
    : squared = base * base,
      cubed = base * base * base;

  final double squared;
  final double cubed;
}

bool _canTraverseNeighbor({
  required _GridNode current,
  required _GridNode next,
  required bool isStartNode,
  required _GridAddress endAddress,
  required ElbowHeading previousHeading,
  required ElbowHeading neighborHeading,
  required bool startConstrained,
  required bool endConstrained,
  required ElbowHeading startHeading,
  required ElbowHeading startHeadingFlip,
  required ElbowHeading endHeadingFlip,
  required List<DrawRect> obstacles,
}) {
  if (_segmentIntersectsAnyBounds(current.pos, next.pos, obstacles)) {
    return false;
  }

  if (neighborHeading == previousHeading.opposite) {
    return false;
  }

  if (isStartNode &&
      !_allowsHeadingFromStart(
        constrained: startConstrained,
        neighborHeading: neighborHeading,
        startHeading: startHeading,
        startHeadingFlip: startHeadingFlip,
      )) {
    return false;
  }

  if (next.addr == endAddress &&
      !_allowsHeadingIntoEnd(
        constrained: endConstrained,
        neighborHeading: neighborHeading,
        endHeadingFlip: endHeadingFlip,
      )) {
    return false;
  }

  return true;
}

double _heuristicScore({
  required DrawPoint from,
  required DrawPoint to,
  required ElbowHeading fromHeading,
  required ElbowHeading endHeading,
  required double bendPenaltySquared,
}) =>
    _manhattanDistance(from, to) +
    _estimatedBendPenalty(
      start: from,
      end: to,
      startHeading: fromHeading,
      endHeading: endHeading,
      bendPenaltySquared: bendPenaltySquared,
    );

List<_GridNode> _astar({
  required _Grid grid,
  required _GridNode start,
  required _GridNode end,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required bool startConstrained,
  required bool endConstrained,
  required List<DrawRect> obstacles,
}) {
  // A* with bend penalties to discourage unnecessary elbows.
  final openSet = _BinaryHeap<_GridNode>((node) => node.f)..push(start);

  final bendPenalty = _BendPenalty(_manhattanDistance(start.pos, end.pos));
  final startHeadingFlip = startHeading.opposite;
  final endHeadingFlip = endHeading.opposite;

  while (openSet.isNotEmpty) {
    final current = openSet.pop();
    if (current == null) {
      break;
    }
    if (current.closed) {
      continue;
    }
    if (current.addr == end.addr) {
      return _reconstructPath(current, start);
    }

    current.closed = true;

    final previousHeading = current.parent == null
        ? startHeading
        : _headingBetween(current.pos, current.parent!.pos);
    final isStartNode = current.addr == start.addr;
    final col = current.addr.col;
    final row = current.addr.row;

    for (final offset in _neighborOffsets) {
      final next = grid.nodeAt(col + offset.dx, row + offset.dy);
      if (next == null) {
        continue;
      }
      if (next.closed) {
        continue;
      }

      final neighborHeading = offset.heading;

      if (!_canTraverseNeighbor(
        current: current,
        next: next,
        isStartNode: isStartNode,
        endAddress: end.addr,
        previousHeading: previousHeading,
        neighborHeading: neighborHeading,
        startConstrained: startConstrained,
        endConstrained: endConstrained,
        startHeading: startHeading,
        startHeadingFlip: startHeadingFlip,
        endHeadingFlip: endHeadingFlip,
        obstacles: obstacles,
      )) {
        continue;
      }

      final directionChanged = neighborHeading != previousHeading;
      final moveCost = _manhattanDistance(current.pos, next.pos);
      final bendCost = directionChanged ? bendPenalty.cubed : 0;
      final gScore = current.g + moveCost + bendCost;

      if (!next.visited || gScore < next.g) {
        final hScore = _heuristicScore(
          from: next.pos,
          to: end.pos,
          fromHeading: neighborHeading,
          endHeading: endHeadingFlip,
          bendPenaltySquared: bendPenalty.squared,
        );
        next
          ..parent = current
          ..g = gScore
          ..h = hScore
          ..f = gScore + hScore;
        if (!next.visited) {
          next.visited = true;
          openSet.push(next);
        } else {
          openSet.rescore(next);
        }
      }
    }
  }

  return const <_GridNode>[];
}

double _estimatedBendPenalty({
  required DrawPoint start,
  required DrawPoint end,
  required ElbowHeading startHeading,
  required ElbowHeading endHeading,
  required double bendPenaltySquared,
}) {
  final sameAxis = startHeading.isHorizontal == endHeading.isHorizontal;
  if (!sameAxis) {
    return bendPenaltySquared;
  }

  final alignedOnAxis = startHeading.isHorizontal
      ? (start.y - end.y).abs() <= _dedupThreshold
      : (start.x - end.x).abs() <= _dedupThreshold;
  return alignedOnAxis ? 0 : bendPenaltySquared;
}

List<_GridNode>? _tryRouteGridPath({
  required _Grid grid,
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
  required DrawPoint startDongle,
  required DrawPoint endDongle,
  required List<DrawRect> obstacles,
}) {
  final startNode = grid.nodeForPoint(startDongle);
  final endNode = grid.nodeForPoint(endDongle);
  if (startNode == null || endNode == null) {
    return null;
  }

  return _astar(
    grid: grid,
    start: startNode,
    end: endNode,
    startHeading: start.heading,
    endHeading: end.heading,
    startConstrained: start.isBound,
    endConstrained: end.isBound,
    obstacles: obstacles,
  );
}

bool _allowsHeadingFromStart({
  required bool constrained,
  required ElbowHeading neighborHeading,
  required ElbowHeading startHeading,
  required ElbowHeading startHeadingFlip,
}) {
  if (constrained) {
    return neighborHeading == startHeading;
  }
  return neighborHeading != startHeadingFlip;
}

bool _allowsHeadingIntoEnd({
  required bool constrained,
  required ElbowHeading neighborHeading,
  required ElbowHeading endHeadingFlip,
}) {
  if (constrained) {
    return neighborHeading == endHeadingFlip;
  }
  return neighborHeading != endHeadingFlip;
}

ElbowHeading _headingBetween(DrawPoint from, DrawPoint to) =>
    _vectorToHeading(from.x - to.x, from.y - to.y);

ElbowHeading _segmentHeading(DrawPoint from, DrawPoint to) =>
    _vectorToHeading(to.x - from.x, to.y - from.y);

bool _segmentIntersectsAnyBounds(
  DrawPoint start,
  DrawPoint end,
  List<DrawRect> obstacles,
) {
  for (final obstacle in obstacles) {
    if (_segmentIntersectsBounds(start, end, obstacle)) {
      return true;
    }
  }
  return false;
}

List<DrawPoint> _ensureOrthogonalPath({
  required List<DrawPoint> points,
  required ElbowHeading startHeading,
}) {
  // Insert a midpoint when a diagonal would appear between consecutive points.
  if (points.length < 2) {
    return points;
  }
  final result = <DrawPoint>[points.first];
  for (var i = 1; i < points.length; i++) {
    final previous = result.last;
    final next = points[i];
    final dx = (next.x - previous.x).abs();
    final dy = (next.y - previous.y).abs();
    if (dx <= _dedupThreshold || dy <= _dedupThreshold) {
      if (next != previous) {
        result.add(next);
      }
      continue;
    }

    final preferHorizontal = result.length > 1
        ? _isHorizontal(result[result.length - 2], previous)
        : startHeading.isHorizontal;
    final mid = preferHorizontal
        ? DrawPoint(x: next.x, y: previous.y)
        : DrawPoint(x: previous.x, y: next.y);
    if (mid != previous) {
      result.add(mid);
    }
    if (next != mid) {
      result.add(next);
    }
  }
  return result;
}

bool _isHorizontal(DrawPoint a, DrawPoint b) =>
    (a.y - b.y).abs() <= (a.x - b.x).abs();

List<_GridNode> _reconstructPath(_GridNode current, _GridNode start) {
  final reversed = <_GridNode>[];
  var node = current;
  while (true) {
    reversed.add(node);
    final parent = node.parent;
    if (parent == null) {
      break;
    }
    node = parent;
  }
  if (reversed.isEmpty) {
    return [start];
  }
  final path = reversed.reversed.toList(growable: true);
  if (path.first.addr != start.addr) {
    path.insert(0, start);
  }
  return path;
}

@immutable
class _NeighborOffset {
  const _NeighborOffset(this.dx, this.dy, this.heading);

  final int dx;
  final int dy;
  final ElbowHeading heading;
}

const List<_NeighborOffset> _neighborOffsets = [
  _NeighborOffset(0, -1, ElbowHeading.up),
  _NeighborOffset(1, 0, ElbowHeading.right),
  _NeighborOffset(0, 1, ElbowHeading.down),
  _NeighborOffset(-1, 0, ElbowHeading.left),
];

class _BinaryHeap<T> {
  _BinaryHeap(double Function(T) score)
    : _score = ((value) => score(value as T));

  final double Function(Object?) _score;
  final List<T> _content = [];

  bool get isNotEmpty => _content.isNotEmpty;

  void push(T element) {
    _content.add(element);
    _sinkDown(_content.length - 1);
  }

  T? pop() {
    if (_content.isEmpty) {
      return null;
    }
    final result = _content.first;
    final end = _content.removeLast();
    if (_content.isNotEmpty) {
      _content[0] = end;
      _bubbleUp(0);
    }
    return result;
  }

  bool contains(T element) => _content.contains(element);

  void rescore(T element) {
    final index = _content.indexOf(element);
    if (index >= 0) {
      _sinkDown(index);
    }
  }

  void _sinkDown(int n) {
    final element = _content[n];
    final elementScore = _score(element);
    while (n > 0) {
      final parentN = ((n + 1) >> 1) - 1;
      final parent = _content[parentN];
      if (elementScore < _score(parent)) {
        _content[parentN] = element;
        _content[n] = parent;
        n = parentN;
      } else {
        break;
      }
    }
  }

  void _bubbleUp(int n) {
    final length = _content.length;
    final element = _content[n];
    final elemScore = _score(element);

    while (true) {
      final child2N = (n + 1) << 1;
      final child1N = child2N - 1;
      int? swap;
      var child1Score = 0.0;

      if (child1N < length) {
        final child1 = _content[child1N];
        child1Score = _score(child1);
        if (child1Score < elemScore) {
          swap = child1N;
        }
      }

      if (child2N < length) {
        final child2 = _content[child2N];
        final child2Score = _score(child2);
        if (child2Score < (swap == null ? elemScore : child1Score)) {
          swap = child2N;
        }
      }

      if (swap != null) {
        _content[n] = _content[swap];
        _content[swap] = element;
        n = swap;
      } else {
        break;
      }
    }
  }
}
