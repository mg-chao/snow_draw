part of 'elbow_router.dart';

/// Internal routing flow for [routeElbowArrow].
ElbowRouteResult _routeElbowArrowInternal({
  required DrawPoint start,
  required DrawPoint end,
  required Map<String, ElementState> elementsById,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
}) {
  final endpoints = _resolveRouteEndpoints(
    startPoint: start,
    endPoint: end,
    elementsById: elementsById,
    startBinding: startBinding,
    endBinding: endBinding,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );
  final startEndpoint = endpoints.start;
  final endEndpoint = endpoints.end;

  if (!startEndpoint.isBound && !endEndpoint.isBound) {
    return _buildRouteResult(
      startPoint: startEndpoint.point,
      endPoint: endEndpoint.point,
      points: _fallbackPath(
        start: startEndpoint.point,
        end: endEndpoint.point,
        startHeading: startEndpoint.heading,
        endHeading: endEndpoint.heading,
      ),
    );
  }

  final layout = _planObstacleLayout(start: startEndpoint, end: endEndpoint);
  final direct = _directPathIfClear(
    start: startEndpoint.point,
    end: endEndpoint.point,
    obstacles: layout.obstacles,
    startHeading: startEndpoint.heading,
    endHeading: endEndpoint.heading,
    startConstrained: startEndpoint.isBound,
    endConstrained: endEndpoint.isBound,
  );
  if (direct != null) {
    return _buildRouteResult(
      startPoint: startEndpoint.point,
      endPoint: endEndpoint.point,
      points: direct,
    );
  }

  final routed = _routeViaGridOrFallback(
    start: startEndpoint,
    end: endEndpoint,
    layout: layout,
  );
  final finalized = _finalizeRoutedPath(
    points: routed,
    startHeading: startEndpoint.heading,
    obstacles: layout.obstacles,
  );
  final harmonized = _harmonizeBoundSpacing(
    points: finalized,
    start: startEndpoint,
    end: endEndpoint,
  );

  return _buildRouteResult(
    startPoint: startEndpoint.point,
    endPoint: endEndpoint.point,
    points: harmonized,
  );
}

List<DrawPoint> _routeViaGridOrFallback({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
  required _ElbowObstacleLayout layout,
}) {
  final grid = _buildGrid(
    obstacles: layout.obstacles,
    start: layout.startExit,
    end: layout.endExit,
    bounds: layout.commonBounds,
  );

  final path = _tryRouteGridPath(
    grid: grid,
    start: start,
    end: end,
    startExit: layout.startExit,
    endExit: layout.endExit,
    obstacles: layout.obstacles,
  );

  if (path == null) {
    return _fallbackPath(
      start: start.point,
      end: end.point,
      startHeading: start.heading,
      endHeading: end.heading,
      startConstrained: start.isBound,
      endConstrained: end.isBound,
    );
  }

  final points = path.map((node) => node.pos);
  return [
    if (layout.startExit != start.point) start.point,
    ...points,
    if (layout.endExit != end.point) end.point,
  ];
}

ElbowRouteResult _buildRouteResult({
  required DrawPoint startPoint,
  required DrawPoint endPoint,
  required List<DrawPoint> points,
}) => ElbowRouteResult(
  points: ElbowGeometry.mergeConsecutiveSameHeading(points),
  startPoint: startPoint,
  endPoint: endPoint,
);

/// Fully resolved endpoint for elbow routing.
@immutable
final class _ResolvedEndpoint {
  const _ResolvedEndpoint({
    required this.point,
    required this.heading,
    required this.hasArrowhead,
    this.elementBounds,
    this.anchor,
  });

  final DrawPoint point;
  final ElbowHeading heading;
  final bool hasArrowhead;
  final DrawRect? elementBounds;
  final DrawPoint? anchor;

  bool get isBound => elementBounds != null;
  DrawPoint get anchorOrPoint => anchor ?? point;
}

typedef _ResolvedEndpoints = ({_ResolvedEndpoint start, _ResolvedEndpoint end});

_ResolvedEndpoint _resolveEndpoint({
  required DrawPoint point,
  required ArrowBinding? binding,
  required Map<String, ElementState> elementsById,
  required bool hasArrowhead,
  required ElbowHeading fallbackHeading,
}) {
  final element = binding == null ? null : elementsById[binding.elementId];
  if (binding == null || element == null) {
    return _ResolvedEndpoint(
      point: point,
      heading: fallbackHeading,
      hasArrowhead: hasArrowhead,
    );
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
  final heading = ElbowGeometry.headingForPointOnBounds(
    bounds,
    anchor ?? resolved,
  );
  return _ResolvedEndpoint(
    point: resolved,
    heading: heading,
    hasArrowhead: hasArrowhead,
    elementBounds: bounds,
    anchor: anchor,
  );
}

_ResolvedEndpoints _resolveRouteEndpoints({
  required DrawPoint startPoint,
  required DrawPoint endPoint,
  required Map<String, ElementState> elementsById,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
}) {
  final start = _resolveEndpoint(
    point: startPoint,
    binding: startBinding,
    elementsById: elementsById,
    hasArrowhead: startArrowhead != ArrowheadStyle.none,
    fallbackHeading: ElbowGeometry.headingForVector(
      endPoint.x - startPoint.x,
      endPoint.y - startPoint.y,
    ),
  );
  final end = _resolveEndpoint(
    point: endPoint,
    binding: endBinding,
    elementsById: elementsById,
    hasArrowhead: endArrowhead != ArrowheadStyle.none,
    fallbackHeading: ElbowGeometry.headingForVector(
      startPoint.x - endPoint.x,
      startPoint.y - endPoint.y,
    ),
  );
  return (start: start, end: end);
}
