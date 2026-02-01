part of 'elbow_router.dart';

/// Internal routing pipeline that coordinates endpoint resolution, obstacle
/// planning, grid routing, and final path cleanup.
@immutable
final class _ElbowRouteInputs {
  const _ElbowRouteInputs({
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

/// Step-by-step routing orchestration used by [routeElbowArrow].
final class _ElbowRoutePipeline {
  const _ElbowRoutePipeline(this.inputs);

  final _ElbowRouteInputs inputs;

  ElbowRouteResult run() {
    // Step 1: resolve bindings/headings into concrete endpoints.
    final endpoints = _resolveRouteEndpoints(inputs);

    // Steps 2-5: plan + route + post-process the elbow path.
    final routed = _ElbowRouteEngine(
      start: endpoints.start,
      end: endpoints.end,
    ).route();

    return _buildRouteResult(
      startPoint: endpoints.start.point,
      endPoint: endpoints.end.point,
      points: routed,
    );
  }
}

/// Attempts to route via the sparse grid. Falls back to the midpoint elbow
/// when the grid search fails.
List<DrawPoint> _routeViaGrid({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
  required _ElbowObstacleLayout layout,
}) {
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
        )
      : _postProcessPath(
          path: path,
          startPoint: start.point,
          endPoint: end.point,
          startExit: layout.startExit,
          endExit: layout.endExit,
        );
}

/// Executes the routing steps after endpoints are resolved.
final class _ElbowRouteEngine {
  const _ElbowRouteEngine({
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
    final layout = _planObstacleLayout(start: start, end: end);
    final direct = _tryDirectRoute(layout);
    if (direct != null) {
      return direct;
    }

    // Step 3/4: route around obstacles via the grid, then clean up.
    final routed = _routeViaGrid(
      start: start,
      end: end,
      layout: layout,
    );

    return _finalizeRoutedPath(points: routed, startHeading: start.heading);
  }

  bool get _usesFallbackPath => !start.isBound && !end.isBound;

  List<DrawPoint>? _tryDirectRoute(_ElbowObstacleLayout layout) =>
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
