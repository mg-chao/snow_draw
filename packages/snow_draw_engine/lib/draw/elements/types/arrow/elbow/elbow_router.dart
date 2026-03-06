import 'package:meta/meta.dart';

import '../../../../core/coordinates/element_space.dart';
import '../../../../models/element_state.dart';
import '../../../../types/draw_point.dart';
import '../../../../types/element_style.dart';
import '../arrow_binding.dart';
import '../arrow_core.dart' as core;
import '../arrow_core_bridge.dart';
import '../arrow_core_geometry_adapter.dart';
import '../arrow_core_ops.dart';
import '../arrow_data.dart';
import 'elbow_fixed_segment.dart';

/// Elbow arrow routing entry points.
///
/// Routing is delegated to the shared arrow helpers and then projected back to
/// engine point types.
@immutable
final class ElbowRouteResult {
  const ElbowRouteResult({
    required this.points,
    required this.startPoint,
    required this.endPoint,
    required this.startBinding,
    required this.endBinding,
    required this.fixedSegments,
    required this.startIsSpecial,
    required this.endIsSpecial,
  });

  final List<DrawPoint> points;
  final DrawPoint startPoint;
  final DrawPoint endPoint;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final List<ElbowFixedSegment>? fixedSegments;
  final bool? startIsSpecial;
  final bool? endIsSpecial;
}

@immutable
final class ElbowRoutedPoints {
  const ElbowRoutedPoints({
    required this.localPoints,
    required this.worldPoints,
    required this.localFixedSegments,
    required this.startBinding,
    required this.endBinding,
    required this.startIsSpecial,
    required this.endIsSpecial,
  });

  final List<DrawPoint> localPoints;
  final List<DrawPoint> worldPoints;
  final List<ElbowFixedSegment>? localFixedSegments;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final bool? startIsSpecial;
  final bool? endIsSpecial;
}

ElbowRouteResult routeElbowArrow({
  required DrawPoint start,
  required DrawPoint end,
  required Map<String, ElementState> elementsById,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
  ArrowheadStyle startArrowhead = ArrowheadStyle.none,
  ArrowheadStyle endArrowhead = ArrowheadStyle.none,
  core.EngineContext? engineContext,
}) {
  final baseArrow = _buildCoreRouteArrow(
    start: start,
    end: end,
    startBinding: startBinding,
    endBinding: endBinding,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );
  final bindables = collectCoreBindables(elementsById.values);
  final patch = recomputeCoreElbowPatch(
    arrow: baseArrow,
    bindables: bindables,
    context: engineContext ?? core.defaultEngineContext,
  );
  final routedArrow = core.applyArrowPatch(baseArrow, patch);
  final points = coreArrowWorldPoints(routedArrow);
  if (points.length < 2) {
    return ElbowRouteResult(
      points: <DrawPoint>[start, end],
      startPoint: start,
      endPoint: end,
      startBinding: startBinding,
      endBinding: endBinding,
      fixedSegments: null,
      startIsSpecial: null,
      endIsSpecial: null,
    );
  }
  return ElbowRouteResult(
    points: points,
    startPoint: points.first,
    endPoint: points.last,
    startBinding: fromCoreBinding(routedArrow.startBinding),
    endBinding: fromCoreBinding(routedArrow.endBinding),
    fixedSegments: coreArrowWorldFixedSegments(routedArrow),
    startIsSpecial: routedArrow.startIsSpecial,
    endIsSpecial: routedArrow.endIsSpecial,
  );
}

ElbowRoutedPoints routeElbowArrowForElement({
  required ElementState element,
  required ArrowData data,
  required Map<String, ElementState> elementsById,
  DrawPoint? startOverride,
  DrawPoint? endOverride,
  core.EngineContext? engineContext,
}) {
  final resolvedPoints = resolveArrowWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );
  final startPoint = startOverride ?? resolvedPoints.first;
  final endPoint = endOverride ?? resolvedPoints.last;

  return routeElbowArrowForElementPoints(
    element: element,
    startLocal: startPoint,
    endLocal: endPoint,
    elementsById: elementsById,
    startBinding: data.startBinding,
    endBinding: data.endBinding,
    startArrowhead: data.startArrowhead,
    endArrowhead: data.endArrowhead,
    engineContext: engineContext,
  );
}

ElbowRoutedPoints routeElbowArrowForElementPoints({
  required ElementState element,
  required DrawPoint startLocal,
  required DrawPoint endLocal,
  required Map<String, ElementState> elementsById,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
  ArrowheadStyle startArrowhead = ArrowheadStyle.none,
  ArrowheadStyle endArrowhead = ArrowheadStyle.none,
  core.EngineContext? engineContext,
}) {
  final space = ElementSpace(
    rotation: element.rotation,
    origin: element.rect.center,
  );
  final worldStart = space.toWorld(startLocal);
  final worldEnd = space.toWorld(endLocal);

  final routed = routeElbowArrow(
    start: worldStart,
    end: worldEnd,
    startBinding: startBinding,
    endBinding: endBinding,
    elementsById: elementsById,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
    engineContext: engineContext,
  );

  final localPoints = routed.points
      .map(space.fromWorld)
      .toList(growable: false);
  final localFixedSegments = routed.fixedSegments
      ?.map(
        (segment) => segment.copyWith(
          start: space.fromWorld(segment.start),
          end: space.fromWorld(segment.end),
        ),
      )
      .toList(growable: false);
  return ElbowRoutedPoints(
    localPoints: localPoints,
    worldPoints: routed.points,
    localFixedSegments: localFixedSegments == null
        ? null
        : List<ElbowFixedSegment>.unmodifiable(localFixedSegments),
    startBinding: routed.startBinding,
    endBinding: routed.endBinding,
    startIsSpecial: routed.startIsSpecial,
    endIsSpecial: routed.endIsSpecial,
  );
}

core.ArrowState _buildCoreRouteArrow({
  required DrawPoint start,
  required DrawPoint end,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
}) {
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  return core.ArrowState(
    id: '__route__',
    x: start.x,
    y: start.y,
    width: dx.abs(),
    height: dy.abs(),
    points: <core.Point>[
      <double>[0, 0],
      <double>[dx, dy],
    ],
    startBinding: toCoreBinding(startBinding),
    endBinding: toCoreBinding(endBinding),
    startArrowhead: toCoreArrowhead(startArrowhead),
    endArrowhead: toCoreArrowhead(endArrowhead),
    elbowed: true,
    // Excalidraw parity: new elbow arrows initialize with an empty fixed
    // segment list and explicit non-special endpoint flags. Passing `null`
    // here collapses the default route into a 3-point L-shape.
    fixedSegments: const <core.FixedSegment>[],
    startIsSpecial: false,
    endIsSpecial: false,
  );
}
