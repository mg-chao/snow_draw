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

  if (!endpoints.start.isBound && !endpoints.end.isBound) {
    return _buildRouteResult(
      startPoint: endpoints.start.point,
      endPoint: endpoints.end.point,
      points: _fallbackPath(
        start: endpoints.start.point,
        end: endpoints.end.point,
        startHeading: endpoints.start.heading,
        endHeading: endpoints.end.heading,
      ),
    );
  }

  final layout = _planObstacleLayout(
    start: endpoints.start,
    end: endpoints.end,
  );
  final direct = _directPathIfClear(
    start: endpoints.start.point,
    end: endpoints.end.point,
    obstacles: layout.obstacles,
    startHeading: endpoints.start.heading,
    endHeading: endpoints.end.heading,
    startConstrained: endpoints.start.isBound,
    endConstrained: endpoints.end.isBound,
  );
  if (direct != null) {
    return _buildRouteResult(
      startPoint: endpoints.start.point,
      endPoint: endpoints.end.point,
      points: direct,
    );
  }

  final routed = _routeViaGridOrFallback(
    start: endpoints.start,
    end: endpoints.end,
    layout: layout,
  );
  final finalized = _finalizeRoutedPath(
    points: routed,
    startHeading: endpoints.start.heading,
    obstacles: layout.obstacles,
  );
  final harmonized = _harmonizeBoundSpacing(
    points: finalized,
    start: endpoints.start,
    end: endpoints.end,
  );

  return _buildRouteResult(
    startPoint: endpoints.start.point,
    endPoint: endpoints.end.point,
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

  return [
    if (layout.startExit != start.point) start.point,
    for (final node in path) node.pos,
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

// ---------------------------------------------------------------------------
// Endpoint resolution (merged from elbow_router_endpoints.dart)
// ---------------------------------------------------------------------------

/// Fully resolved endpoint for elbow routing.
@immutable
final class _ResolvedEndpoint {
  const _ResolvedEndpoint({
    required this.point,
    required this.heading,
    required this.hasArrowhead,
    this.element,
    this.elementBounds,
    this.anchor,
  });

  final DrawPoint point;
  final ElbowHeading heading;
  final bool hasArrowhead;
  final ElementState? element;
  final DrawRect? elementBounds;
  final DrawPoint? anchor;

  bool get isBound => element != null;
  DrawPoint get anchorOrPoint => anchor ?? point;
}

@immutable
final class _ResolvedEndpoints {
  const _ResolvedEndpoints({required this.start, required this.end});

  final _ResolvedEndpoint start;
  final _ResolvedEndpoint end;
}

_ResolvedEndpoint _resolveEndpoint({
  required DrawPoint point,
  required ArrowBinding? binding,
  required Map<String, ElementState> elementsById,
  required bool hasArrowhead,
  required ElbowHeading fallbackHeading,
}) {
  if (binding == null) {
    return _ResolvedEndpoint(
      point: point,
      heading: fallbackHeading,
      hasArrowhead: hasArrowhead,
    );
  }

  final element = elementsById[binding.elementId];
  if (element == null) {
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
    element: element,
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
  return _ResolvedEndpoints(start: start, end: end);
}
