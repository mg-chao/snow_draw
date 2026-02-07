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

    return _buildRouteResult(
      startPoint: context.endpoints.start.point,
      endPoint: context.endpoints.end.point,
      points: finalized,
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

    return path == null
        ? _fallbackPath(
            start: start.point,
            end: end.point,
            startHeading: start.heading,
            endHeading: end.heading,
            startConstrained: start.isBound,
            endConstrained: end.isBound,
          )
        : _postProcessPath(
            path: path,
            startPoint: start.point,
            endPoint: end.point,
            startExit: layout.startExit,
            endExit: layout.endExit,
          );
  }
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
