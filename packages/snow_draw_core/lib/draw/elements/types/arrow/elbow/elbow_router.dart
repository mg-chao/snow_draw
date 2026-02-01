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

part 'elbow_router_endpoints.dart';
part 'elbow_router_obstacles.dart';
part 'elbow_router_path.dart';
part 'elbow_router_grid.dart';

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

List<DrawPoint> _routeViaGrid({
  required _ResolvedEndpoint start,
  required _ResolvedEndpoint end,
  required _ObstacleLayout layout,
}) {
  // Step 4: route through a sparse grid using A* with bend penalties.
  final grid = _buildGrid(
    obstacles: layout.obstacles,
    start: layout.startDongle,
    startHeading: start.heading,
    end: layout.endDongle,
    endHeading: end.heading,
    bounds: layout.commonBounds,
  );

  final path = _tryRouteGridPath(
    grid: grid,
    start: start,
    end: end,
    startDongle: layout.startDongle,
    endDongle: layout.endDongle,
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
          startDongle: layout.startDongle,
          endDongle: layout.endDongle,
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
    final layout = _buildObstacleLayout(start: start, end: end);
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
  // Route through the explicit step-based pipeline for readability.
  return _ElbowRoutePipeline(
    _ElbowRouteInputs(
      start: start,
      end: end,
      elementsById: elementsById,
      startBinding: startBinding,
      endBinding: endBinding,
      startArrowhead: startArrowhead,
      endArrowhead: endArrowhead,
    ),
  ).run();
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
