import 'dart:math' as math;

import 'arrow_binding_core.dart';
import 'arrow_geom.dart';
import 'arrow_types.dart';

const double focusPointSize = 10 / 1.5;
const double FOCUS_POINT_SIZE = focusPointSize;

double _focusHitThreshold(double zoom) =>
    (focusPointSize * 1.5) / math.max(zoom, 1e-6);

Map<String, dynamic>? _asStringDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((key, entryValue) {
      if (key is String) {
        out[key] = entryValue;
      }
    });
    return out;
  }
  return null;
}

ArrowState? _readArrow(Object? value) => value is ArrowState ? value : null;

List<BindableState> _readBindables(Object? value) {
  if (value is List<BindableState>) {
    return value;
  }
  if (value is List) {
    return value.whereType<BindableState>().toList(growable: false);
  }
  return const <BindableState>[];
}

Point? _readPoint(Object? value) {
  if (value is! List || value.length < 2) {
    return null;
  }
  final x = value[0];
  final y = value[1];
  if (x is! num || y is! num || !x.isFinite || !y.isFinite) {
    return null;
  }
  return <double>[x.toDouble(), y.toDouble()];
}

Point _readPointOrZero(Object? value) => _readPoint(value) ?? <double>[0, 0];

double? _readFiniteDouble(Object? value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  return null;
}

EngineContext _readContext(Object? value) {
  if (value is EngineContext) {
    return value;
  }
  return normalizeEngineContext(_asStringDynamicMap(value));
}

ArrowEndpointEdge _readEdge(
  Object? value, {
  ArrowEndpointEdge fallback = arrowEndpointStart,
}) {
  if (value == arrowEndpointStart || value == 'start') {
    return arrowEndpointStart;
  }
  if (value == arrowEndpointEnd || value == 'end') {
    return arrowEndpointEnd;
  }
  return fallback;
}

Point _unrotateToLocal(Point point, BindableState bindable) {
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );
  return unrotatePoint(point, bindableCenter, bindable.angle);
}

List<Point> _getDiamondVertices(BindableState bindable) {
  final topX = (bindable.width / 2).floorToDouble() + 1;
  final rightY = (bindable.height / 2).floorToDouble() + 1;
  final top = <double>[bindable.x + topX, bindable.y];
  final right = <double>[bindable.x + bindable.width, bindable.y + rightY];
  final bottom = <double>[bindable.x + topX, bindable.y + bindable.height];
  final left = <double>[bindable.x, bindable.y + rightY];
  return <Point>[top, right, bottom, left];
}

bool _isPointInConvexPolygon(Point point, List<Point> vertices) {
  var referenceSign = 0;
  for (var index = 0; index < vertices.length; index += 1) {
    final from = vertices[index];
    final to = vertices[(index + 1) % vertices.length];
    final cross =
        (to[0] - from[0]) * (point[1] - from[1]) -
        (to[1] - from[1]) * (point[0] - from[0]);
    if (cross.abs() <= 1e-9) {
      continue;
    }
    final sign = cross > 0 ? 1 : -1;
    if (referenceSign == 0) {
      referenceSign = sign;
      continue;
    }
    if (sign != referenceSign) {
      return false;
    }
  }
  return true;
}

bool _isPointInBindable(Point point, BindableState bindable) {
  final shape = canonicalizeBindableShape(bindable.shape);
  final local = _unrotateToLocal(point, bindable);
  final x = local[0];
  final y = local[1];

  if (shape == 'rectangle') {
    return x >= bindable.x &&
        y >= bindable.y &&
        x <= bindable.x + bindable.width &&
        y <= bindable.y + bindable.height;
  }

  if (shape == 'ellipse') {
    final cx = bindable.x + bindable.width / 2;
    final cy = bindable.y + bindable.height / 2;
    final rx = math.max(bindable.width / 2, 1e-6);
    final ry = math.max(bindable.height / 2, 1e-6);
    final nx = (x - cx) / rx;
    final ny = (y - cy) / ry;
    return nx * nx + ny * ny <= 1;
  }

  return _isPointInConvexPolygon(local, _getDiamondVertices(bindable));
}

double _pointSegmentDistance(Point point, Point from, Point to) {
  final abx = to[0] - from[0];
  final aby = to[1] - from[1];
  final apx = point[0] - from[0];
  final apy = point[1] - from[1];
  final lengthSq = abx * abx + aby * aby;
  if (lengthSq <= 1e-9) {
    return distance(point, from);
  }
  final t = clamp((apx * abx + apy * aby) / lengthSq, 0, 1);
  final projection = <double>[from[0] + abx * t, from[1] + aby * t];
  return distance(point, projection);
}

double _distanceToRectangleOutline(Point point, BindableState bindable) {
  final local = _unrotateToLocal(point, bindable);
  final minX = bindable.x;
  final minY = bindable.y;
  final maxX = bindable.x + bindable.width;
  final maxY = bindable.y + bindable.height;
  final inside =
      local[0] >= minX &&
      local[0] <= maxX &&
      local[1] >= minY &&
      local[1] <= maxY;

  if (inside) {
    return math.min(
      math.min((local[0] - minX).abs(), (maxX - local[0]).abs()),
      math.min((local[1] - minY).abs(), (maxY - local[1]).abs()),
    );
  }

  final clampedX = clamp(local[0], minX, maxX);
  final clampedY = clamp(local[1], minY, maxY);
  return distance(local, <double>[clampedX, clampedY]);
}

double _distanceToEllipseOutline(Point point, BindableState bindable) {
  final local = _unrotateToLocal(point, bindable);
  final cx = bindable.x + bindable.width / 2;
  final cy = bindable.y + bindable.height / 2;
  final rx = math.max(bindable.width / 2, 1e-6);
  final ry = math.max(bindable.height / 2, 1e-6);
  final dx = local[0] - cx;
  final dy = local[1] - cy;

  if (dx.abs() < 1e-9 && dy.abs() < 1e-9) {
    return math.min(rx, ry);
  }

  final scale = 1 / math.sqrt((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry));
  final projection = <double>[cx + dx * scale, cy + dy * scale];
  return distance(local, projection);
}

double _distanceToDiamondOutline(Point point, BindableState bindable) {
  final local = _unrotateToLocal(point, bindable);
  final vertices = _getDiamondVertices(bindable);
  final top = vertices[0];
  final right = vertices[1];
  final bottom = vertices[2];
  final left = vertices[3];
  final distances = <double>[
    _pointSegmentDistance(local, top, right),
    _pointSegmentDistance(local, right, bottom),
    _pointSegmentDistance(local, bottom, left),
    _pointSegmentDistance(local, left, top),
  ];
  return distances.reduce(math.min);
}

double _distanceToBindableOutline(Point point, BindableState bindable) {
  switch (canonicalizeBindableShape(bindable.shape)) {
    case 'rectangle':
      return _distanceToRectangleOutline(point, bindable);
    case 'ellipse':
      return _distanceToEllipseOutline(point, bindable);
    case 'diamond':
    default:
      return _distanceToDiamondOutline(point, bindable);
  }
}

bool _isBindableVisibleAtPoint(Point point, BindableState bindable) {
  final bounds = bindable.visibilityBounds;
  if (bounds == null) {
    return true;
  }
  if (bounds.length != 4) {
    return false;
  }
  return point[0] >= bounds[0] &&
      point[1] >= bounds[1] &&
      point[0] <= bounds[2] &&
      point[1] <= bounds[3];
}

ArrowPatch _computePatchFromLocalPoints(
  ArrowState arrow,
  List<Point> points,
  double maxCoordinate,
) {
  final globalPoints = points
      .map((point) => toGlobalPoint(arrow, point))
      .toList(growable: false);
  final normalized = normalizeArrowFromGlobalPoints(
    globalPoints,
    maxCoordinate,
  );
  return <String, dynamic>{
    'x': normalized.x,
    'y': normalized.y,
    'points': normalized.points,
    'width': normalized.width,
    'height': normalized.height,
  };
}

Point _snapPointToGrid(Point point, double? gridSize) {
  if (gridSize == null || !gridSize.isFinite || gridSize <= 0) {
    return point;
  }
  return <double>[
    (point[0] / gridSize).roundToDouble() * gridSize,
    (point[1] / gridSize).roundToDouble() * gridSize,
  ];
}

void _collectBindingTransition({
  required String arrowId,
  required ArrowEndpointEdge edge,
  required FixedPointBinding? previousBinding,
  required FixedPointBinding? nextBinding,
  required List<BindablePatch> bindablePatches,
  required List<ArrowEngineEvent> events,
  required Set<String> reorderTargets,
}) {
  if (previousBinding != null &&
      (nextBinding == null ||
          previousBinding.elementId != nextBinding.elementId)) {
    bindablePatches.add(
      BindablePatch(id: previousBinding.elementId, removeBoundArrowId: arrowId),
    );
    if (nextBinding == null) {
      events.add(BindingBrokenEvent(arrowId: arrowId, edge: edge));
    }
  }

  if (nextBinding != null &&
      (previousBinding == null ||
          previousBinding.elementId != nextBinding.elementId)) {
    bindablePatches.add(
      BindablePatch(id: nextBinding.elementId, addBoundArrowId: arrowId),
    );
    if (!reorderTargets.contains(nextBinding.elementId)) {
      reorderTargets.add(nextBinding.elementId);
      events.add(
        ReorderArrowEvent(arrowId: arrowId, bindableId: nextBinding.elementId),
      );
    }
  }
}

bool isFocusPointVisible({
  required ArrowState arrow,
  required ArrowEndpointEdge edge,
  required FixedPointBinding binding,
  required BindableState bindable,
  required Object? context,
  bool ignoreOverlap = false,
}) {
  final resolvedContext = _readContext(context);
  final normalizedEdge = _readEdge(edge);

  if (arrow.elbowed ||
      !resolvedContext.isBindingEnabled ||
      arrow.points.length != 2) {
    return false;
  }

  final focusPoint = getGlobalFixedPoint(binding, bindable);
  if (!_isBindableVisibleAtPoint(focusPoint, bindable)) {
    return false;
  }

  if (!ignoreOverlap) {
    final associatedIndex = arrow.startBinding?.elementId == bindable.id
        ? 0
        : arrow.points.length - 1;
    final associatedPoint = getPointAtIndexGlobal(
      arrow,
      associatedIndex == 0 ? 0 : -1,
    );
    if (distance(focusPoint, associatedPoint) <
        _focusHitThreshold(resolvedContext.zoom)) {
      return false;
    }
  }

  final endpoint = getPointAtIndexGlobal(
    arrow,
    normalizedEdge == arrowEndpointStart ? 0 : -1,
  );
  final insideOrNearOutline =
      _isPointInBindable(focusPoint, bindable) ||
      _distanceToBindableOutline(focusPoint, bindable) <=
          getBindingGap(bindable, arrow.elbowed);

  return distance(focusPoint, endpoint) >=
          _focusHitThreshold(resolvedContext.zoom) &&
      insideOrNearOutline;
}

List<FocusPointDescriptor> listVisibleFocusPoints(
  ListVisibleFocusPointsInput input,
) {
  final arrow = _readArrow(input['arrow']);
  if (arrow == null) {
    return <FocusPointDescriptor>[];
  }

  final bindables = _readBindables(input['bindables']);
  final context = _readContext(input['context']);
  final options = _asStringDynamicMap(input['options']);
  final ignoreOverlap = options?['ignoreOverlap'] == true;
  final bindablesById = <String, BindableState>{
    for (final bindable in bindables) bindable.id: bindable,
  };

  final out = <FocusPointDescriptor>[];
  final startBinding = arrow.startBinding;
  if (startBinding != null) {
    final bindable = bindablesById[startBinding.elementId];
    if (bindable != null &&
        isFocusPointVisible(
          arrow: arrow,
          edge: arrowEndpointStart,
          binding: startBinding,
          bindable: bindable,
          context: context,
          ignoreOverlap: ignoreOverlap,
        )) {
      out.add(
        FocusPointDescriptor(
          edge: arrowEndpointStart,
          binding: startBinding,
          point: getGlobalFixedPoint(startBinding, bindable),
        ),
      );
    }
  }

  final endBinding = arrow.endBinding;
  if (endBinding != null) {
    final bindable = bindablesById[endBinding.elementId];
    if (bindable != null &&
        isFocusPointVisible(
          arrow: arrow,
          edge: arrowEndpointEnd,
          binding: endBinding,
          bindable: bindable,
          context: context,
          ignoreOverlap: ignoreOverlap,
        )) {
      out.add(
        FocusPointDescriptor(
          edge: arrowEndpointEnd,
          binding: endBinding,
          point: getGlobalFixedPoint(endBinding, bindable),
        ),
      );
    }
  }

  return out;
}

ArrowEndpointEdge? pickFocusPoint(PickFocusPointInput input) {
  final pointer = _readPointOrZero(input['pointer']);
  final context = _readContext(input['context']);
  final focusPoints = listVisibleFocusPoints(<String, dynamic>{
    'arrow': input['arrow'],
    'bindables': input['bindables'],
    'context': context,
    'options': input['options'],
  });
  final threshold = _focusHitThreshold(context.zoom);
  for (final focusPoint in focusPoints) {
    if (distance(pointer, focusPoint.point) <= threshold) {
      return focusPoint.edge;
    }
  }
  return null;
}

FocusPointHit pickFocusPointWithOffset(PickFocusPointWithOffsetInput input) {
  final pointer = _readPointOrZero(input['pointer']);
  final context = _readContext(input['context']);
  final focusPoints = listVisibleFocusPoints(<String, dynamic>{
    'arrow': input['arrow'],
    'bindables': input['bindables'],
    'context': context,
    'options': input['options'],
  });
  final threshold = _focusHitThreshold(context.zoom);
  for (final focusPoint in focusPoints) {
    if (distance(pointer, focusPoint.point) <= threshold) {
      return FocusPointHit(
        edge: focusPoint.edge,
        pointerOffset: <double>[
          pointer[0] - focusPoint.point[0],
          pointer[1] - focusPoint.point[1],
        ],
      );
    }
  }
  return const FocusPointHit(edge: null, pointerOffset: <double>[0, 0]);
}

EngineResult computeFocusPointDrag(ComputeFocusPointDragInput input) {
  final arrow = _readArrow(input['arrow']);
  final pointer = _readPoint(input['pointer']);
  if (arrow == null || pointer == null) {
    return const EngineResult(
      arrowPatch: <String, dynamic>{},
      bindablePatches: <BindablePatch>[],
      suggestedBinding: null,
      events: <ArrowEngineEvent>[],
    );
  }

  final bindables = _readBindables(input['bindables']);
  final context = _readContext(input['context']);
  if (arrow.elbowed || arrow.points.length < 2) {
    return const EngineResult(
      arrowPatch: <String, dynamic>{},
      bindablePatches: <BindablePatch>[],
      suggestedBinding: null,
      events: <ArrowEngineEvent>[],
    );
  }

  final options = _asStringDynamicMap(input['options']);
  final switchToInsideBinding = options?['switchToInsideBinding'] == true;
  final gridSize = _readFiniteDouble(options?['gridSize']);

  final draggedEdge = _readEdge(input['draggedEdge']);
  final otherEdge = draggedEdge == arrowEndpointStart
      ? arrowEndpointEnd
      : arrowEndpointStart;
  final draggedIndex = draggedEdge == arrowEndpointStart
      ? 0
      : arrow.points.length - 1;
  final otherIndex = otherEdge == arrowEndpointStart
      ? 0
      : arrow.points.length - 1;

  final bindablesById = <String, BindableState>{
    for (final bindable in bindables) bindable.id: bindable,
  };

  FixedPointBinding? startBinding = arrow.startBinding;
  FixedPointBinding? endBinding = arrow.endBinding;

  FixedPointBinding? getBinding(ArrowEndpointEdge edge) =>
      edge == arrowEndpointStart ? startBinding : endBinding;
  void setBinding(ArrowEndpointEdge edge, FixedPointBinding? binding) {
    if (edge == arrowEndpointStart) {
      startBinding = binding;
    } else {
      endBinding = binding;
    }
  }

  final nextPoints = arrow.points
      .map((point) => <double>[point[0], point[1]])
      .toList(growable: true);
  var simulatedArrow = arrow.copyWith(
    points: nextPoints,
    startBinding: startBinding,
    setStartBinding: true,
    endBinding: endBinding,
    setEndBinding: true,
  );

  final hovered = context.isBindingEnabled && bindables.isNotEmpty
      ? pickHoveredBindable(
          pointer,
          bindables,
          maxBindingDistance(context.zoom),
        )
      : null;

  final currentDraggedBinding = getBinding(draggedEdge);
  if (hovered != null) {
    var mode = currentDraggedBinding?.mode ?? bindModeOrbit;
    if (switchToInsideBinding && mode == bindModeOrbit) {
      mode = bindModeInside;
    } else if (!switchToInsideBinding && mode == bindModeInside) {
      mode = bindModeOrbit;
    }
    setBinding(
      draggedEdge,
      calculateFixedPointForBinding(
        point: pointer,
        bindable: hovered,
        mode: mode,
      ),
    );
  } else {
    setBinding(draggedEdge, null);
    final snappedPointer = _snapPointToGrid(pointer, gridSize);
    nextPoints[draggedIndex] = toLocalPoint(arrow, snappedPointer);
  }

  final draggedBinding = getBinding(draggedEdge);
  final draggedBindable = draggedBinding == null
      ? null
      : bindablesById[draggedBinding.elementId];

  if (draggedBinding != null && draggedBindable != null) {
    final oppositeBinding = getBinding(otherEdge);
    final boundToSameElement =
        oppositeBinding != null &&
        oppositeBinding.elementId == draggedBinding.elementId;
    final updatedDraggedBinding = draggedBinding.copyWith(
      mode: switchToInsideBinding || boundToSameElement
          ? bindModeInside
          : bindModeOrbit,
    );
    setBinding(draggedEdge, updatedDraggedBinding);
    simulatedArrow = simulatedArrow.copyWith(
      points: nextPoints,
      startBinding: startBinding,
      setStartBinding: true,
      endBinding: endBinding,
      setEndBinding: true,
    );

    final draggedUpdate = updateBoundPoint(
      arrow: simulatedArrow,
      edge: draggedEdge,
      binding: updatedDraggedBinding,
      bindable: draggedBindable,
      bindablesById: bindablesById,
      dragging: true,
    );
    if (draggedUpdate != null) {
      nextPoints[draggedIndex] = draggedUpdate;
      simulatedArrow = simulatedArrow.copyWith(points: nextPoints);
    }
  }

  final otherBinding = getBinding(otherEdge);
  if (otherBinding != null && otherBinding.mode == bindModeOrbit) {
    final otherBindable = bindablesById[otherBinding.elementId];
    if (otherBindable != null && context.isBindingEnabled) {
      final boundToSameAfterUpdate =
          draggedBindable != null &&
          otherBinding.elementId == draggedBindable.id;
      final updatedOtherBinding = otherBinding.copyWith(
        mode: switchToInsideBinding || boundToSameAfterUpdate
            ? bindModeInside
            : bindModeOrbit,
      );
      setBinding(otherEdge, updatedOtherBinding);
      simulatedArrow = simulatedArrow.copyWith(
        points: nextPoints,
        startBinding: startBinding,
        setStartBinding: true,
        endBinding: endBinding,
        setEndBinding: true,
      );

      final otherUpdate = updateBoundPoint(
        arrow: simulatedArrow,
        edge: otherEdge,
        binding: updatedOtherBinding,
        bindable: otherBindable,
        bindablesById: bindablesById,
      );
      if (otherUpdate != null) {
        nextPoints[otherIndex] = otherUpdate;
      }
    }
  }

  final finalPatch = _computePatchFromLocalPoints(
    arrow,
    nextPoints,
    context.maxCoordinate,
  );

  final bindablePatches = <BindablePatch>[];
  final events = <ArrowEngineEvent>[];
  final reorderTargets = <String>{};

  _collectBindingTransition(
    arrowId: arrow.id,
    edge: arrowEndpointStart,
    previousBinding: arrow.startBinding,
    nextBinding: startBinding,
    bindablePatches: bindablePatches,
    events: events,
    reorderTargets: reorderTargets,
  );
  _collectBindingTransition(
    arrowId: arrow.id,
    edge: arrowEndpointEnd,
    previousBinding: arrow.endBinding,
    nextBinding: endBinding,
    bindablePatches: bindablePatches,
    events: events,
    reorderTargets: reorderTargets,
  );

  return EngineResult(
    arrowPatch: <String, dynamic>{
      ...finalPatch,
      'startBinding': startBinding,
      'endBinding': endBinding,
    },
    bindablePatches: bindablePatches,
    suggestedBinding: hovered == null
        ? null
        : SuggestedBinding(
            bindableId: hovered.id,
            element: hovered,
            midPoint: getSnapOutlineMidPoint(pointer, hovered, context.zoom),
          ),
    events: events,
  );
}

bool isPointNearBindableForFocus(
  Point point,
  BindableState bindable,
  double zoom,
) =>
    _isBindableVisibleAtPoint(point, bindable) &&
    (_isPointInBindable(point, bindable) ||
        _distanceToBindableOutline(point, bindable) <=
            maxBindingDistance(zoom) + bindable.strokeWidth / 2);

final handleFocusPointHover = pickFocusPoint;
final handleFocusPointDrag = computeFocusPointDrag;
final handleFocusPointPointerDown = pickFocusPointWithOffset;
