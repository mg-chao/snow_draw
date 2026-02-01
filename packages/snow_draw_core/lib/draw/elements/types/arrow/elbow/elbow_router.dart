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
import 'elbow_constants.dart';
import 'elbow_geometry.dart';
import 'elbow_heading.dart';

export 'elbow_heading.dart';

part 'elbow_router_endpoints.dart';
part 'elbow_router_obstacles.dart';
part 'elbow_router_path.dart';
part 'elbow_router_grid.dart';
part 'elbow_router_pipeline.dart';

/// Elbow arrow routing entry points.
/// See docs/elbow_arrows.md for the full step-by-step pipeline.
///
/// Routing overview:
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
    _ElbowRouteRequest(
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
