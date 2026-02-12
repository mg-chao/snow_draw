part of 'elbow_router.dart';

/// Internal routing pipeline that coordinates endpoint resolution, obstacle
/// planning, grid routing, and final path cleanup.
@immutable
final class _ElbowRouteRequest {
  const _ElbowRouteRequest({
    required this.start,
    required this.end,
    required this.elementsById,
    required this.startBinding,
    required this.endBinding,
    required this.startArrowhead,
    required this.endArrowhead,
  });

  final DrawPoint start;
  final DrawPoint end;
  final Map<String, ElementState> elementsById;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final ArrowheadStyle startArrowhead;
  final ArrowheadStyle endArrowhead;
}

/// Shared routing context for a single elbow routing run.
@immutable
final class _ElbowRouteContext {
  const _ElbowRouteContext({required this.request, required this.endpoints});

  final _ElbowRouteRequest request;
  final _ResolvedEndpoints endpoints;

  bool get hasAnyBinding => endpoints.start.isBound || endpoints.end.isBound;
}

/// Step-by-step routing orchestration used by [routeElbowArrow].
final class _ElbowRoutePipeline {
  const _ElbowRoutePipeline(this.request);

  final _ElbowRouteRequest request;

  ElbowRouteResult run() {
    // Step 1: resolve bindings/headings into concrete endpoints.
    final context = _ElbowRouteContext(
      request: request,
      endpoints: _resolveRouteEndpoints(request),
    );

    // Step 2: if nothing is bound, prefer the simple fallback path.
    final unboundFallback = _tryUnboundFallback(context);
    if (unboundFallback != null) {
      return unboundFallback;
    }

    // Step 3: plan obstacles and attempt a direct route first.
    final plan = _ElbowRoutePlan.fromEndpoints(context.endpoints);
    final direct = plan.tryDirectRoute();
    if (direct != null) {
      return _buildRouteResult(
        startPoint: context.endpoints.start.point,
        endPoint: context.endpoints.end.point,
        points: direct,
      );
    }

    // Step 4/5: route via the sparse grid and post-process.
    final routed = plan.routeViaGrid();
    final finalized = _finalizeRoutedPath(
      points: routed,
      startHeading: plan.start.heading,
      obstacles: plan.layout.obstacles,
    );
    final harmonized = _harmonizeBoundSpacing(
      points: finalized,
      start: plan.start,
      end: plan.end,
    );

    return _buildRouteResult(
      startPoint: context.endpoints.start.point,
      endPoint: context.endpoints.end.point,
      points: harmonized,
    );
  }

  /// Builds the simple fallback route when both endpoints are unbound.
  ElbowRouteResult? _tryUnboundFallback(_ElbowRouteContext context) {
    if (context.hasAnyBinding) {
      return null;
    }
    final endpoints = context.endpoints;
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
}

/// Planned routing context: resolved endpoints + obstacle layout.
@immutable
final class _ElbowRoutePlan {
  const _ElbowRoutePlan({
    required this.start,
    required this.end,
    required this.layout,
  });

  factory _ElbowRoutePlan.fromEndpoints(_ResolvedEndpoints endpoints) =>
      _ElbowRoutePlan(
        start: endpoints.start,
        end: endpoints.end,
        layout: _planObstacleLayout(start: endpoints.start, end: endpoints.end),
      );

  final _ResolvedEndpoint start;
  final _ResolvedEndpoint end;
  final _ElbowObstacleLayout layout;

  List<DrawPoint>? tryDirectRoute() => _directPathIfClear(
    start: start.point,
    end: end.point,
    obstacles: layout.obstacles,
    startHeading: start.heading,
    endHeading: end.heading,
    startConstrained: start.isBound,
    endConstrained: end.isBound,
  );

  /// Attempts a sparse-grid route. Falls back to a midpoint elbow if A* fails.
  List<DrawPoint> routeViaGrid() {
    // Step 4: route through a sparse grid using A* with bend penalties.
    final grid = _buildGrid(
      obstacles: layout.obstacles,
      start: layout.startExit,
      startHeading: start.heading,
      end: layout.endExit,
      endHeading: end.heading,
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
    final points = [
      if (layout.startExit != start.point &&
          path.first.pos != start.point)
        start.point,
      for (final node in path) node.pos,
      if (layout.endExit != end.point &&
          path.last.pos != end.point)
        end.point,
    ];
    return points.isEmpty ? [start.point, end.point] : points;
  }
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

/// Resolved binding info for a single endpoint before heading assignment.
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
  const _ResolvedEndpoints({required this.start, required this.end});

  final _ResolvedEndpoint start;
  final _ResolvedEndpoint end;
}

_ResolvedEndpoints _resolveRouteEndpoints(_ElbowRouteRequest request) {
  ElbowHeading resolveHeadingFor(_EndpointInfo info, ElbowHeading fallback) =>
      _resolveEndpointHeading(
        elementBounds: info.elementBounds,
        point: info.point,
        anchor: info.anchor,
        fallback: fallback,
      );

  final hasStartArrowhead = request.startArrowhead != ArrowheadStyle.none;
  final hasEndArrowhead = request.endArrowhead != ArrowheadStyle.none;
  final startInfo = _resolveEndpointInfo(
    point: request.start,
    binding: request.startBinding,
    elementsById: request.elementsById,
    hasArrowhead: hasStartArrowhead,
  );
  final endInfo = _resolveEndpointInfo(
    point: request.end,
    binding: request.endBinding,
    elementsById: request.elementsById,
    hasArrowhead: hasEndArrowhead,
  );

  final startPoint = startInfo.point;
  final endPoint = endInfo.point;

  final vectorHeading = ElbowGeometry.headingForVector(
    endPoint.x - startPoint.x,
    endPoint.y - startPoint.y,
  );
  final reverseVectorHeading = ElbowGeometry.headingForVector(
    startPoint.x - endPoint.x,
    startPoint.y - endPoint.y,
  );
  final startHeading = resolveHeadingFor(startInfo, vectorHeading);
  final endHeading = resolveHeadingFor(endInfo, reverseVectorHeading);

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
