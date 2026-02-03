part of 'elbow_router.dart';

/// Endpoint resolution for elbow routing.
///
/// This step resolves bindings into concrete world-space points, anchors,
/// and headings so the rest of the router can treat each endpoint uniformly.

// Endpoint resolution: bindings + anchors + headings.
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
  // Step 1: resolve bindings, arrowhead gaps, and endpoint headings.
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
