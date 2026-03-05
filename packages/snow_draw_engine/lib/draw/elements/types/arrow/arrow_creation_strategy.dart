import 'package:meta/meta.dart';
import '../../../config/draw_config.dart';
import '../../../elements/core/creation_strategy.dart';
import '../../../elements/core/element_data.dart';
import '../../../models/document_state.dart';
import '../../../models/draw_state.dart';
import '../../../models/element_state.dart';
import '../../../models/interaction_state.dart';
import '../../../services/grid_snap_service.dart';
import '../../../services/object_snap_service.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../../types/snap_guides.dart';
import '../../../utils/camera_zoom.dart';
import '../../../utils/snapping_mode.dart';
import '../../../utils/visible_elements.dart';
import '../arrow/arrow_binding.dart';
import '../arrow/arrow_binding_policy.dart';
import '../line/line_data.dart';
import 'arrow_core_bindable_query.dart';
import 'arrow_core_bridge.dart';
import 'arrow_core_endpoint_drag.dart';
import 'arrow_geometry.dart';
import 'arrow_like_data.dart';
import 'arrow_two_point_layout.dart';
import 'elbow/elbow_fixed_segment.dart';
import 'elbow/elbow_router.dart';

/// Creation strategy for arrow elements (single- and multi-point).
@immutable
class ArrowCreationStrategy extends PointCreationStrategy {
  const ArrowCreationStrategy();

  @override
  CreationUpdateResult start({
    required ElementData data,
    required DrawPoint startPosition,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    final arrowData = requireCreationDataType<ArrowLikeData>(
      data: data,
      strategyName: 'ArrowCreationStrategy.start',
    );

    final arrowRect = _calculateArrowRect(
      points: [startPosition, startPosition],
      arrowType: arrowData.arrowType,
    );
    final normalizedPoints = ArrowGeometry.normalizePoints(
      worldPoints: [startPosition, startPosition],
      rect: arrowRect,
    );
    final updatedData = arrowData.copyWith(points: normalizedPoints);
    final sessionData = _ArrowCreationSessionData();
    return CreationUpdateResult(
      data: updatedData,
      rect: arrowRect,
      creationMode: PointCreationMode(
        fixedPoints: List<DrawPoint>.unmodifiable([startPosition]),
        currentPoint: startPosition,
        sessionData: sessionData,
      ),
    );
  }

  @override
  CreationUpdateResult update({
    required DrawState state,
    required DrawConfig config,
    required CreatingState creatingState,
    required DrawPoint currentPosition,
    required bool maintainAspectRatio,
    required bool createFromCenter,
    required SnappingMode snappingMode,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    final elementData = requireCreatingElementDataType<ArrowLikeData>(
      creatingState: creatingState,
      strategyName: 'ArrowCreationStrategy.update',
    );
    if (elementData is LineData) {
      return _updateLine(
        state: state,
        config: config,
        creatingState: creatingState,
        currentPosition: currentPosition,
        snappingMode: snappingMode,
        maintainAspectRatio: maintainAspectRatio,
        createFromCenter: createFromCenter,
        data: elementData,
      );
    }
    final sessionData = _resolveSessionData(creatingState.creationMode);

    final endpoints = _resolveCreationEndpoints(
      state: state,
      config: config,
      creatingState: creatingState,
      data: elementData,
      currentPosition: currentPosition,
      snappingMode: snappingMode,
      sessionData: sessionData,
      maintainAspectRatio: maintainAspectRatio,
      createFromCenter: createFromCenter,
    );
    var adjustedCurrent = endpoints.currentPosition;

    final bindingResult = _snapBindingPoint(
      state: state,
      config: config,
      position: adjustedCurrent,
      snappingMode: snappingMode,
      arrowType: elementData.arrowType,
      dragStart: false,
      startArrowheadStyle: elementData.startArrowhead,
      endArrowheadStyle: elementData.endArrowhead,
      preferredBinding: elementData.endBinding,
      oppositeBinding: endpoints.startBinding,
      oppositePoint: endpoints.segmentStart,
      angleLocked: maintainAspectRatio,
      altKey: createFromCenter,
    );
    adjustedCurrent = bindingResult.position;
    var endBinding = bindingResult.binding;
    final closeTolerance =
        config.selection.interaction.handleTolerance *
        _loopCloseToleranceMultiplier;
    if (elementData.arrowType != ArrowType.elbow &&
        endpoints.fixedPoints.length >= 2) {
      final startPoint = endpoints.fixedPoints.first;
      if (adjustedCurrent.distanceSquared(startPoint) <=
          closeTolerance * closeTolerance) {
        adjustedCurrent = startPoint;
        endBinding = endpoints.startBinding;
      }
    }

    final allPoints = _appendCurrentPoint(
      fixedPoints: endpoints.fixedPoints,
      currentPoint: adjustedCurrent,
    );
    late final DrawRect arrowRect;
    late final List<DrawPoint> normalizedPoints;
    var resolvedStartBinding = endpoints.startBinding;
    var resolvedEndBinding = endBinding;
    List<ElbowFixedSegment>? resolvedFixedSegments;
    bool? resolvedStartIsSpecial;
    bool? resolvedEndIsSpecial;
    if (elementData.arrowType == ArrowType.elbow) {
      final routed = routeElbowArrow(
        start: endpoints.startPosition,
        end: adjustedCurrent,
        startBinding: endpoints.startBinding,
        endBinding: bindingResult.binding,
        elementsById: state.domain.document.elementMap,
        startArrowhead: elementData.startArrowhead,
        endArrowhead: elementData.endArrowhead,
        engineContext: buildCoreEngineContext(
          zoom: state.application.view.camera.zoom,
          isBindingEnabled: config.snap.enableArrowBinding,
        ),
      );
      final routedPoints = routed.points;
      arrowRect = _calculateArrowRect(
        points: routedPoints,
        arrowType: elementData.arrowType,
      );
      normalizedPoints = ArrowGeometry.normalizePoints(
        worldPoints: routedPoints,
        rect: arrowRect,
      );
      resolvedStartBinding = routed.startBinding;
      resolvedEndBinding = routed.endBinding;
      resolvedFixedSegments = routed.fixedSegments;
      resolvedStartIsSpecial = routed.startIsSpecial;
      resolvedEndIsSpecial = routed.endIsSpecial;
    } else if (endpoints.fixedPoints.length == 1) {
      final layout = computeArrowTwoPointLayout(
        first: endpoints.fixedPoints.first,
        second: adjustedCurrent,
      );
      arrowRect = layout.rect;
      normalizedPoints = layout.normalizedPoints;
    } else {
      arrowRect = _calculateArrowRect(
        points: allPoints,
        arrowType: elementData.arrowType,
      );
      normalizedPoints = ArrowGeometry.normalizePoints(
        worldPoints: allPoints,
        rect: arrowRect,
      );
    }
    final updatedData = elementData.copyWith(
      points: normalizedPoints,
      startBinding: resolvedStartBinding,
      endBinding: resolvedEndBinding,
      fixedSegments: resolvedFixedSegments,
      startIsSpecial: resolvedStartIsSpecial,
      endIsSpecial: resolvedEndIsSpecial,
    );

    return CreationUpdateResult(
      data: updatedData,
      rect: arrowRect,
      snapGuides: endpoints.snapGuides,
      creationMode: PointCreationMode(
        fixedPoints: elementData.arrowType == ArrowType.elbow
            ? List<DrawPoint>.unmodifiable([endpoints.startPosition])
            : endpoints.fixedPoints,
        currentPoint: adjustedCurrent,
        sessionData: sessionData,
      ),
    );
  }

  @override
  CreationUpdateResult? addPoint({
    required DrawState state,
    required DrawConfig config,
    required CreatingState creatingState,
    required DrawPoint position,
    required SnappingMode snappingMode,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    if (!creatingState.isPointCreation) {
      return null;
    }

    final elementData = requireCreatingElementDataType<ArrowLikeData>(
      creatingState: creatingState,
      strategyName: 'ArrowCreationStrategy.addPoint',
    );
    if (elementData.arrowType == ArrowType.elbow) {
      return null;
    }
    final sessionData = _resolveSessionData(creatingState.creationMode);
    final endpoints = _resolveCreationEndpoints(
      state: state,
      config: config,
      creatingState: creatingState,
      data: elementData,
      currentPosition: position,
      snappingMode: snappingMode,
      sessionData: sessionData,
      maintainAspectRatio: false,
      createFromCenter: false,
    );
    var adjustedPosition = endpoints.currentPosition;

    final bindingResult = _snapBindingPoint(
      state: state,
      config: config,
      position: adjustedPosition,
      snappingMode: snappingMode,
      arrowType: elementData.arrowType,
      dragStart: false,
      startArrowheadStyle: elementData.startArrowhead,
      endArrowheadStyle: elementData.endArrowhead,
      preferredBinding: elementData.endBinding,
      oppositeBinding: endpoints.startBinding,
      oppositePoint: endpoints.segmentStart,
      angleLocked: false,
      altKey: false,
    );
    adjustedPosition = bindingResult.position;

    var updatedFixedPoints = endpoints.fixedPoints;
    if (updatedFixedPoints.isEmpty ||
        updatedFixedPoints.last != adjustedPosition) {
      updatedFixedPoints = List<DrawPoint>.unmodifiable([
        ...updatedFixedPoints,
        adjustedPosition,
      ]);
    }
    updatedFixedPoints = _applyBoundStartToFixedPoints(
      fixedPoints: updatedFixedPoints,
      boundStart: endpoints.startPosition,
    );
    final allPoints = _appendCurrentPoint(
      fixedPoints: updatedFixedPoints,
      currentPoint: adjustedPosition,
    );
    final arrowRect = _calculateArrowRect(
      points: allPoints,
      arrowType: elementData.arrowType,
    );
    final normalizedPoints = ArrowGeometry.normalizePoints(
      worldPoints: allPoints,
      rect: arrowRect,
    );
    final updatedData = elementData.copyWith(
      points: normalizedPoints,
      startBinding: endpoints.startBinding,
      endBinding: bindingResult.binding,
    );

    return CreationUpdateResult(
      data: updatedData,
      rect: arrowRect,
      snapGuides: endpoints.snapGuides,
      creationMode: PointCreationMode(
        fixedPoints: updatedFixedPoints,
        currentPoint: adjustedPosition,
        sessionData: sessionData,
      ),
    );
  }

  @override
  CreationFinishResult finish({
    required DrawState state,
    required DrawConfig config,
    required CreatingState creatingState,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    final data = requireCreatingElementDataType<ArrowLikeData>(
      creatingState: creatingState,
      strategyName: 'ArrowCreationStrategy.finish',
    );

    final minSize = config.element.minCreateSize;
    final finishTolerance = config.selection.interaction.handleTolerance;
    final worldPoints = ArrowGeometry.resolveWorldPoints(
      rect: creatingState.currentRect,
      normalizedPoints: data.points,
    );
    final finalPoints =
        data.arrowType == ArrowType.elbow || !creatingState.isPointCreation
        ? worldPoints
        : _resolveFinalArrowPoints(
            interaction: creatingState,
            finishTolerance: finishTolerance,
          );
    final closeTolerance = finishTolerance * _loopCloseToleranceMultiplier;
    final closedPoints = data.arrowType == ArrowType.elbow
        ? finalPoints
        : _closeIfNeeded(finalPoints, closeTolerance: closeTolerance);
    if (closedPoints.length < 2) {
      return CreationFinishResult(
        data: data,
        rect: creatingState.currentRect,
        shouldCommit: false,
      );
    }

    final arrowRect = _calculateArrowRect(
      points: closedPoints,
      arrowType: data.arrowType,
    );
    final normalizedPoints = ArrowGeometry.normalizePoints(
      worldPoints: closedPoints,
      rect: arrowRect,
    );
    _ArrowCreationFinishResult finalizedResult = (
      rect: arrowRect,
      data: data.copyWith(points: normalizedPoints),
      orderedElementIds: null,
    );
    if (config.snap.enableArrowBinding) {
      finalizedResult = _finalizeArrowCreationBindings(
        state: state,
        config: config,
        elementId: creatingState.element.id,
        result: finalizedResult,
      );
    }

    final points = ArrowGeometry.resolveWorldPoints(
      rect: finalizedResult.rect,
      normalizedPoints: finalizedResult.data.points,
    );
    final length = ArrowGeometry.calculateShaftLength(
      points: points,
      arrowType: finalizedResult.data.arrowType,
    );
    if (!length.isFinite || length < minSize) {
      return CreationFinishResult(
        data: data,
        rect: creatingState.currentRect,
        shouldCommit: false,
      );
    }

    return CreationFinishResult(
      data: finalizedResult.data,
      rect: finalizedResult.rect,
      shouldCommit: true,
      orderedElementIds: finalizedResult.orderedElementIds,
    );
  }
}

typedef _ArrowCreationFinishResult = ({
  DrawRect rect,
  ArrowLikeData data,
  List<String>? orderedElementIds,
});

_ArrowCreationFinishResult _finalizeArrowCreationBindings({
  required DrawState state,
  required DrawConfig config,
  required String elementId,
  required _ArrowCreationFinishResult result,
}) {
  final worldPoints = ArrowGeometry.resolveWorldPoints(
    rect: result.rect,
    normalizedPoints: result.data.points,
  );
  if (worldPoints.length < 2) {
    return result;
  }

  final bindingDistance = resolveZoomAdjustedDistance(
    distance: config.snap.arrowBindingDistance,
    zoom: state.application.view.camera.zoom,
  );
  final previewElement = ElementState(
    id: elementId,
    rect: result.rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: result.data,
  );
  final dragIndex = worldPoints.length - 1;
  final pointer = worldPoints.last;
  final preserveDraggedInsideBinding =
      result.data.endBinding?.mode == ArrowBindingMode.inside;
  final preserveOppositeInsideBinding =
      result.data.startBinding?.mode == ArrowBindingMode.inside;
  final oppositeOrbitFocusPoint =
      result.data.startBinding?.mode == ArrowBindingMode.orbit
      ? worldPoints.first
      : null;
  final coreContext = buildCoreEngineContext(
    zoom: state.application.view.camera.zoom,
    isBindingEnabled: config.snap.enableArrowBinding,
  );
  final orderedElementIds = <String>[
    ...state.domain.document.elements.map((element) => element.id),
    elementId,
  ];
  final finalized = finalizeArrowCoreEndpointDragResult(
    state: state,
    element: previewElement,
    data: result.data,
    localPoints: worldPoints,
    draggedIndex: dragIndex,
    worldPointer: pointer,
    startBinding: result.data.startBinding,
    endBinding: result.data.endBinding,
    excludedElementId: elementId,
    shouldLookupBindings: true,
    allowNewBinding: true,
    bindingDistance: bindingDistance,
    coreEngineContext: coreContext,
    orderedElementIds: orderedElementIds,
    options: <String, dynamic>{
      'newArrow': true,
      if (preserveDraggedInsideBinding) 'altKey': true,
      if (preserveOppositeInsideBinding) 'preserveOppositeInsideBinding': true,
      if (oppositeOrbitFocusPoint != null)
        'oppositeOrbitFocusPoint': <double>[
          oppositeOrbitFocusPoint.x,
          oppositeOrbitFocusPoint.y,
        ],
    },
  );
  if (finalized == null) {
    return result;
  }
  final currentArrow = toCoreArrowState(
    element: previewElement,
    data: result.data,
  );
  final patchedElement = finalized.arrow == currentArrow
      ? previewElement
      : applyCoreArrowStateToElement(
          element: previewElement,
          data: result.data,
          nextArrow: finalized.arrow,
        );
  final patchedData = patchedElement.data;
  if (patchedData is! ArrowLikeData) {
    return result;
  }
  return (
    rect: patchedElement.rect,
    data: patchedData,
    orderedElementIds: finalized.orderedElementIds,
  );
}

CreationUpdateResult _updateLine({
  required DrawState state,
  required DrawConfig config,
  required CreatingState creatingState,
  required DrawPoint currentPosition,
  required SnappingMode snappingMode,
  required bool maintainAspectRatio,
  required bool createFromCenter,
  required LineData data,
}) {
  final sessionData = _resolveSessionData(creatingState.creationMode);
  final endpoints = _resolveCreationEndpoints(
    state: state,
    config: config,
    creatingState: creatingState,
    data: data,
    currentPosition: currentPosition,
    snappingMode: snappingMode,
    sessionData: sessionData,
    maintainAspectRatio: maintainAspectRatio,
    createFromCenter: createFromCenter,
  );
  var adjustedCurrent = endpoints.currentPosition;

  final bindingResult = _snapBindingPoint(
    state: state,
    config: config,
    position: adjustedCurrent,
    snappingMode: snappingMode,
    arrowType: data.arrowType,
    dragStart: false,
    startArrowheadStyle: data.startArrowhead,
    endArrowheadStyle: data.endArrowhead,
    preferredBinding: data.endBinding,
    oppositeBinding: endpoints.startBinding,
    oppositePoint: endpoints.segmentStart,
    angleLocked: maintainAspectRatio,
    altKey: createFromCenter,
  );
  adjustedCurrent = bindingResult.position;
  var endBinding = bindingResult.binding;

  final closeTolerance =
      config.selection.interaction.handleTolerance *
      _loopCloseToleranceMultiplier;
  if (endpoints.fixedPoints.length >= 2) {
    final firstPoint = endpoints.fixedPoints.first;
    if (adjustedCurrent.distanceSquared(firstPoint) <=
        closeTolerance * closeTolerance) {
      adjustedCurrent = firstPoint;
      endBinding = endpoints.startBinding;
    }
  }

  late final DrawRect lineRect;
  late final List<DrawPoint> normalizedPoints;
  if (endpoints.fixedPoints.length == 1) {
    final layout = computeArrowTwoPointLayout(
      first: endpoints.fixedPoints.first,
      second: adjustedCurrent,
    );
    lineRect = layout.rect;
    normalizedPoints = layout.normalizedPoints;
  } else {
    final worldPoints = _appendCurrentPoint(
      fixedPoints: endpoints.fixedPoints,
      currentPoint: adjustedCurrent,
    );
    lineRect = _calculateArrowRect(
      points: worldPoints,
      arrowType: data.arrowType,
    );
    normalizedPoints = ArrowGeometry.normalizePoints(
      worldPoints: worldPoints,
      rect: lineRect,
    );
  }
  final updatedData = data.copyWith(
    points: normalizedPoints,
    startBinding: endpoints.startBinding,
    endBinding: endBinding,
  );

  return CreationUpdateResult(
    data: updatedData,
    rect: lineRect,
    snapGuides: endpoints.snapGuides,
    creationMode: PointCreationMode(
      fixedPoints: endpoints.fixedPoints,
      currentPoint: adjustedCurrent,
      sessionData: sessionData,
    ),
  );
}

const _loopCloseToleranceMultiplier = 1.5;

_CreationEndpointResolution _resolveCreationEndpoints({
  required DrawState state,
  required DrawConfig config,
  required CreatingState creatingState,
  required ArrowLikeData data,
  required DrawPoint currentPosition,
  required SnappingMode snappingMode,
  required _ArrowCreationSessionData sessionData,
  required bool maintainAspectRatio,
  required bool createFromCenter,
}) {
  var startPosition = _snapPointToGridIfNeeded(
    point: creatingState.startPosition,
    config: config,
    snappingMode: snappingMode,
  );
  var adjustedCurrent = _snapPointToGridIfNeeded(
    point: currentPosition,
    config: config,
    snappingMode: snappingMode,
  );

  final startBindingResult = _resolveStartBindingPoint(
    state: state,
    config: config,
    startPosition: startPosition,
    snappingMode: snappingMode,
    arrowType: data.arrowType,
    startArrowheadStyle: data.startArrowhead,
    endArrowheadStyle: data.endArrowhead,
    preferredBinding: data.startBinding,
    oppositeBinding: data.endBinding,
    oppositePoint: adjustedCurrent,
    sessionData: sessionData,
    angleLocked: maintainAspectRatio,
    altKey: createFromCenter,
  );
  startPosition = startBindingResult.position;

  final fixedPoints = _applyBoundStartToFixedPoints(
    fixedPoints: creatingState.fixedPoints,
    boundStart: startPosition,
  );
  final segmentStart = fixedPoints.isNotEmpty
      ? fixedPoints.last
      : startPosition;
  final snapResult = _snapCreatePoint(
    state: state,
    config: config,
    position: adjustedCurrent,
    snappingMode: snappingMode,
    sessionData: sessionData,
  );
  adjustedCurrent = snapResult.position;

  return _CreationEndpointResolution(
    startPosition: startPosition,
    fixedPoints: fixedPoints,
    segmentStart: segmentStart,
    currentPosition: adjustedCurrent,
    startBinding: startBindingResult.binding,
    snapGuides: snapResult.guides,
  );
}

DrawPoint _snapPointToGridIfNeeded({
  required DrawPoint point,
  required DrawConfig config,
  required SnappingMode snappingMode,
}) => snappingMode == SnappingMode.grid
    ? gridSnapService.snapPoint(point: point, gridSize: config.grid.size)
    : point;

/// Calculates accurate bounding rect for arrow, accounting for curved paths.
DrawRect _calculateArrowRect({
  required List<DrawPoint> points,
  required ArrowType arrowType,
}) => ArrowGeometry.calculatePathBounds(
  worldPoints: points,
  arrowType: arrowType,
);

List<DrawPoint> _appendCurrentPoint({
  required List<DrawPoint> fixedPoints,
  required DrawPoint currentPoint,
}) {
  if (fixedPoints.isEmpty) {
    return [currentPoint];
  }
  if (fixedPoints.last == currentPoint) {
    return fixedPoints;
  }
  return [...fixedPoints, currentPoint];
}

List<DrawPoint> _resolveFinalArrowPoints({
  required CreatingState interaction,
  required double finishTolerance,
}) {
  final points = <DrawPoint>[...interaction.fixedPoints];
  final currentPoint = interaction.currentPoint;
  if (currentPoint == null) {
    return points;
  }
  if (points.isEmpty) {
    points.add(currentPoint);
    return points;
  }

  final lastPoint = points.last;
  if (lastPoint == currentPoint) {
    return points;
  }

  // Avoid creating an extra tiny segment when finishing multi-point arrows.
  if (points.length >= 2 &&
      lastPoint.distanceSquared(currentPoint) <=
          finishTolerance * finishTolerance) {
    return points;
  }
  points.add(currentPoint);
  return points;
}

List<DrawPoint> _closeIfNeeded(
  List<DrawPoint> points, {
  required double closeTolerance,
}) {
  if (points.length < 3) {
    return points;
  }
  final first = points.first;
  final last = points.last;
  if (first == last) {
    return points;
  }
  if (first.distanceSquared(last) <= closeTolerance * closeTolerance) {
    final closed = List<DrawPoint>.from(points);
    closed[closed.length - 1] = first;
    return closed;
  }
  return points;
}

_PointSnapResult _snapCreatePoint({
  required DrawState state,
  required DrawConfig config,
  required DrawPoint position,
  required SnappingMode snappingMode,
  required _ArrowCreationSessionData sessionData,
}) {
  if (snappingMode != SnappingMode.object) {
    return _PointSnapResult(position: position);
  }
  final snapConfig = config.snap;
  if (!snapConfig.enablePointSnaps && !snapConfig.enableGapSnaps) {
    return _PointSnapResult(position: position);
  }
  final referenceElements = sessionData.resolveReferenceElements(
    state.domain.document,
  );
  if (referenceElements.isEmpty) {
    return _PointSnapResult(position: position);
  }
  final referenceAabbs = sessionData.resolveReferenceElementAabbs(
    document: state.domain.document,
    referenceElements: referenceElements,
  );
  final snapDistance = resolveZoomAdjustedDistance(
    distance: snapConfig.distance,
    zoom: state.application.view.camera.zoom,
  );
  if (snapDistance <= 0) {
    return _PointSnapResult(position: position);
  }
  final result = objectSnapService.snapRect(
    targetRect: DrawRect(
      minX: position.x,
      minY: position.y,
      maxX: position.x,
      maxY: position.y,
    ),
    referenceElements: referenceElements,
    snapDistance: snapDistance,
    targetAnchorsX: const [SnapAxisAnchor.center],
    targetAnchorsY: const [SnapAxisAnchor.center],
    referenceAabbs: referenceAabbs,
    enablePointSnaps: snapConfig.enablePointSnaps,
    enableGapSnaps: snapConfig.enableGapSnaps,
  );
  final snappedPosition = result.hasSnap
      ? DrawPoint(x: position.x + result.dx, y: position.y + result.dy)
      : position;
  final guides = snapConfig.showGuides ? result.guides : const <SnapGuide>[];
  return _PointSnapResult(position: snappedPosition, guides: guides);
}

_BindingSnapResult _snapBindingPoint({
  required DrawState state,
  required DrawConfig config,
  required DrawPoint position,
  required SnappingMode snappingMode,
  required ArrowType arrowType,
  required bool dragStart,
  required ArrowheadStyle startArrowheadStyle,
  required ArrowheadStyle endArrowheadStyle,
  required ArrowBinding? preferredBinding,
  required ArrowBinding? oppositeBinding,
  required DrawPoint oppositePoint,
  required bool angleLocked,
  required bool altKey,
}) {
  final snapConfig = config.snap;
  final shouldLookupBindings = _shouldAttemptBinding(
    snapConfig: snapConfig,
    snappingMode: snappingMode,
  );
  final bindingDistance = shouldLookupBindings
      ? resolveZoomAdjustedDistance(
          distance: snapConfig.arrowBindingDistance,
          zoom: state.application.view.camera.zoom,
        )
      : 0.0;
  if (!shouldLookupBindings || bindingDistance <= 0) {
    return _BindingSnapResult(position: position);
  }

  final candidates = resolveCoreBindableCandidates(
    document: state.domain.document,
    worldPoint: position,
    distance: bindingDistance,
    preferredBinding: preferredBinding,
    oppositeBinding: oppositeBinding,
  );
  if (candidates.isEmpty || candidates.elements.isEmpty) {
    return _BindingSnapResult(position: position);
  }

  final hasArrowhead = dragStart
      ? startArrowheadStyle != ArrowheadStyle.none
      : endArrowheadStyle != ArrowheadStyle.none;
  final preserveOppositeInsideBinding =
      oppositeBinding?.mode == ArrowBindingMode.inside;
  final oppositeOrbitFocusPoint =
      oppositeBinding?.mode == ArrowBindingMode.orbit ? oppositePoint : null;
  final bindingCandidate = arrowType == ArrowType.elbow
      ? ArrowBindingUtils.resolveElbowBindingCandidate(
          worldPoint: position,
          targets: candidates.elements,
          snapDistance: bindingDistance,
          hasArrowhead: hasArrowhead,
          preferredBinding: preferredBinding,
          allowNewBinding: shouldLookupBindings,
          dragStart: dragStart,
          newArrow: true,
          initialBinding: dragStart,
          preserveOppositeInsideBinding: preserveOppositeInsideBinding,
          oppositeOrbitFocusPoint: oppositeOrbitFocusPoint,
          angleLocked: angleLocked,
          altKey: altKey,
        )
      : ArrowBindingUtils.resolveBindingCandidate(
          worldPoint: position,
          targets: candidates.elements,
          snapDistance: bindingDistance,
          preferredBinding: preferredBinding,
          allowNewBinding: shouldLookupBindings,
          referencePoint: oppositePoint,
          dragStart: dragStart,
          newArrow: true,
          initialBinding: dragStart,
          preserveOppositeInsideBinding: preserveOppositeInsideBinding,
          oppositeOrbitFocusPoint: oppositeOrbitFocusPoint,
          angleLocked: angleLocked,
          altKey: altKey,
        );
  if (bindingCandidate == null) {
    return _BindingSnapResult(position: position);
  }

  return _BindingSnapResult(
    position: bindingCandidate.snapPoint,
    binding: bindingCandidate.binding,
  );
}

_BindingSnapResult _resolveStartBindingPoint({
  required DrawState state,
  required DrawConfig config,
  required DrawPoint startPosition,
  required SnappingMode snappingMode,
  required ArrowType arrowType,
  required ArrowheadStyle startArrowheadStyle,
  required ArrowheadStyle endArrowheadStyle,
  required ArrowBinding? preferredBinding,
  required ArrowBinding? oppositeBinding,
  required DrawPoint oppositePoint,
  required _ArrowCreationSessionData sessionData,
  required bool angleLocked,
  required bool altKey,
}) {
  final snapConfig = config.snap;
  final bindingEnabled = _shouldAttemptBinding(
    snapConfig: snapConfig,
    snappingMode: snappingMode,
  );
  final bindingDistance = bindingEnabled
      ? resolveZoomAdjustedDistance(
          distance: snapConfig.arrowBindingDistance,
          zoom: state.application.view.camera.zoom,
        )
      : 0.0;
  final elementsVersion = state.domain.document.elementsVersion;
  if (sessionData.canReuseStartBinding(
    startPosition: startPosition,
    preferredBinding: preferredBinding,
    snappingMode: snappingMode,
    elementsVersion: elementsVersion,
    bindingEnabled: bindingEnabled,
    bindingDistance: bindingDistance,
    angleLocked: angleLocked,
    altKey: altKey,
  )) {
    final cached = sessionData.resolveCachedStartBinding(
      state: state,
      startPosition: startPosition,
      arrowType: arrowType,
      startArrowheadStyle: startArrowheadStyle,
      oppositePoint: oppositePoint,
    );
    if (cached != null) {
      return cached;
    }
  }

  final resolved = _snapBindingPoint(
    state: state,
    config: config,
    position: startPosition,
    snappingMode: snappingMode,
    arrowType: arrowType,
    dragStart: true,
    startArrowheadStyle: startArrowheadStyle,
    endArrowheadStyle: endArrowheadStyle,
    preferredBinding: preferredBinding,
    oppositeBinding: oppositeBinding,
    oppositePoint: oppositePoint,
    angleLocked: angleLocked,
    altKey: altKey,
  );
  sessionData.cacheStartBinding(
    startPosition: startPosition,
    preferredBinding: preferredBinding,
    snappingMode: snappingMode,
    elementsVersion: elementsVersion,
    bindingEnabled: bindingEnabled,
    bindingDistance: bindingDistance,
    angleLocked: angleLocked,
    altKey: altKey,
    result: resolved,
  );
  return resolved;
}

bool _shouldAttemptBinding({
  required SnapConfig snapConfig,
  required SnappingMode snappingMode,
}) => shouldAttemptArrowBinding(
  snapConfig: snapConfig,
  snappingMode: snappingMode,
);

_ArrowCreationSessionData _resolveSessionData(CreationMode mode) {
  if (mode case PointCreationMode(:final sessionData)) {
    if (sessionData is _ArrowCreationSessionData) {
      return sessionData;
    }
  }
  return _ArrowCreationSessionData();
}

class _ArrowCreationSessionData {
  DrawPoint? _cachedStartPosition;
  ArrowBinding? _cachedStartPreferredBinding;
  ArrowBinding? _cachedStartBinding;
  SnappingMode? _cachedStartSnappingMode;
  bool? _cachedStartBindingEnabled;
  double? _cachedStartBindingDistance;
  bool? _cachedStartAngleLocked;
  bool? _cachedStartAltKey;
  var _cachedStartElementsVersion = -1;

  var _referenceElementsVersion = -1;
  List<ElementState> _referenceElements = const [];
  var _referenceAabbsVersion = -1;
  List<DrawRect> _referenceElementAabbs = const [];
  List<ElementState> _referenceAabbsSource = const [];

  bool canReuseStartBinding({
    required DrawPoint startPosition,
    required ArrowBinding? preferredBinding,
    required SnappingMode snappingMode,
    required int elementsVersion,
    required bool bindingEnabled,
    required double bindingDistance,
    required bool angleLocked,
    required bool altKey,
  }) =>
      _cachedStartPosition == startPosition &&
      _cachedStartPreferredBinding == preferredBinding &&
      _cachedStartSnappingMode == snappingMode &&
      _cachedStartBindingEnabled == bindingEnabled &&
      _cachedStartBindingDistance == bindingDistance &&
      _cachedStartAngleLocked == angleLocked &&
      _cachedStartAltKey == altKey &&
      _cachedStartElementsVersion == elementsVersion;

  _BindingSnapResult? resolveCachedStartBinding({
    required DrawState state,
    required DrawPoint startPosition,
    required ArrowType arrowType,
    required ArrowheadStyle startArrowheadStyle,
    required DrawPoint oppositePoint,
  }) {
    final cachedBinding = _cachedStartBinding;
    if (cachedBinding == null) {
      return _BindingSnapResult(position: startPosition);
    }

    final target = state.domain.document.getElementById(
      cachedBinding.elementId,
    );
    if (target == null ||
        target.opacity <= 0 ||
        !ArrowBindingUtils.isBindableTarget(target)) {
      return null;
    }

    final boundPoint = arrowType == ArrowType.elbow
        ? ArrowBindingUtils.resolveElbowBoundPoint(
            binding: cachedBinding,
            target: target,
            hasArrowhead: startArrowheadStyle != ArrowheadStyle.none,
          )
        : ArrowBindingUtils.resolveBoundPoint(
            binding: cachedBinding,
            target: target,
            referencePoint: oppositePoint,
          );
    if (boundPoint == null) {
      return null;
    }
    return _BindingSnapResult(position: boundPoint, binding: cachedBinding);
  }

  void cacheStartBinding({
    required DrawPoint startPosition,
    required ArrowBinding? preferredBinding,
    required SnappingMode snappingMode,
    required int elementsVersion,
    required bool bindingEnabled,
    required double bindingDistance,
    required bool angleLocked,
    required bool altKey,
    required _BindingSnapResult result,
  }) {
    _cachedStartPosition = startPosition;
    _cachedStartPreferredBinding = preferredBinding;
    _cachedStartBinding = result.binding;
    _cachedStartSnappingMode = snappingMode;
    _cachedStartBindingEnabled = bindingEnabled;
    _cachedStartBindingDistance = bindingDistance;
    _cachedStartAngleLocked = angleLocked;
    _cachedStartAltKey = altKey;
    _cachedStartElementsVersion = elementsVersion;
  }

  List<ElementState> resolveReferenceElements(DocumentState document) {
    if (_referenceElementsVersion == document.elementsVersion) {
      return _referenceElements;
    }
    _referenceElementsVersion = document.elementsVersion;
    return _referenceElements = resolveVisibleElements(
      document.elements,
    ).toList(growable: false);
  }

  List<DrawRect> resolveReferenceElementAabbs({
    required DocumentState document,
    required List<ElementState> referenceElements,
  }) {
    if (_referenceAabbsVersion == document.elementsVersion &&
        identical(_referenceAabbsSource, referenceElements)) {
      return _referenceElementAabbs;
    }
    _referenceAabbsVersion = document.elementsVersion;
    _referenceAabbsSource = referenceElements;
    return _referenceElementAabbs = ObjectSnapService.buildReferenceAabbs(
      referenceElements,
    );
  }
}

@immutable
class _CreationEndpointResolution {
  const _CreationEndpointResolution({
    required this.startPosition,
    required this.fixedPoints,
    required this.segmentStart,
    required this.currentPosition,
    required this.startBinding,
    required this.snapGuides,
  });

  final DrawPoint startPosition;
  final List<DrawPoint> fixedPoints;
  final DrawPoint segmentStart;
  final DrawPoint currentPosition;
  final ArrowBinding? startBinding;
  final List<SnapGuide> snapGuides;
}

@immutable
class _PointSnapResult {
  const _PointSnapResult({
    required this.position,
    this.guides = const <SnapGuide>[],
  });

  final DrawPoint position;
  final List<SnapGuide> guides;
}

@immutable
class _BindingSnapResult {
  const _BindingSnapResult({required this.position, this.binding});

  final DrawPoint position;
  final ArrowBinding? binding;
}

List<DrawPoint> _applyBoundStartToFixedPoints({
  required List<DrawPoint> fixedPoints,
  required DrawPoint boundStart,
}) {
  if (fixedPoints.isEmpty) {
    return fixedPoints;
  }
  if (fixedPoints.first == boundStart) {
    return fixedPoints;
  }
  return List<DrawPoint>.unmodifiable([boundStart, ...fixedPoints.skip(1)]);
}
