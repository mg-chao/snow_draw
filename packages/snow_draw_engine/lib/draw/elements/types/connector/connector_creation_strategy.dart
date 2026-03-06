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
import '../../../utils/combined_element_lookup.dart';
import '../../../utils/snapping_mode.dart';
import '../../../utils/visible_elements.dart';
import '../arrow/arrow_binding.dart';
import '../arrow/arrow_binding_policy.dart';
import '../arrow/arrow_core.dart' as core;
import '../arrow/arrow_core_bridge.dart';
import '../arrow/arrow_core_endpoint_drag.dart';
import '../arrow/arrow_core_geometry_adapter.dart';
import '../arrow/arrow_core_ops.dart';
import '../arrow/arrow_data.dart';
import '../arrow/arrow_scene.dart';
import '../arrow/elbow/elbow_editing.dart';
import '../arrow/elbow/elbow_fixed_segment.dart';
import '../arrow/elbow/elbow_router.dart';
import '../line/line_data.dart';
import 'connector_data.dart';
import 'connector_geometry.dart';

/// Creation strategy for connector elements (single- and multi-point).
@immutable
class ConnectorCreationStrategy extends PointCreationStrategy {
  const ConnectorCreationStrategy();

  @override
  CreationUpdateResult start({
    required ElementData data,
    required DrawPoint startPosition,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    final arrowData = requireCreationDataType<ConnectorData>(
      data: data,
      strategyName: 'ConnectorCreationStrategy.start',
    );

    final arrowRect = _calculateArrowRect(
      points: [startPosition, startPosition],
      arrowType: arrowData.arrowType,
    );
    final normalizedPoints = normalizeArrowPoints(
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
    bool snapOverrideActive = false,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    final elementData = requireCreatingElementDataType<ConnectorData>(
      creatingState: creatingState,
      strategyName: 'ConnectorCreationStrategy.update',
    );
    if (elementData is LineData) {
      return _updateLine(
        state: state,
        config: config,
        creatingState: creatingState,
        currentPosition: currentPosition,
        snappingMode: snappingMode,
        snapOverrideActive: snapOverrideActive,
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
      snapOverrideActive: snapOverrideActive,
      sessionData: sessionData,
      maintainAspectRatio: maintainAspectRatio,
      createFromCenter: createFromCenter,
    );
    var adjustedCurrent = endpoints.currentPosition;

    final bindingResult = _snapBindingPoint(
      state: state,
      config: config,
      data: elementData,
      position: adjustedCurrent,
      snappingMode: snappingMode,
      dragStart: false,
      preferredBinding: elementData.endBinding,
      oppositeBinding: endpoints.startBinding,
      oppositePoint: endpoints.segmentStart,
      initialBinding: false,
      preserveOppositeInsideBinding: sessionData.preserveStartInsideBinding,
      oppositeOrbitFocusPoint: sessionData.startOrbitFocusPoint,
      angleLocked: maintainAspectRatio,
      altKey: createFromCenter,
      snapOverrideActive: snapOverrideActive,
    );
    sessionData.allowBindingOnFinalize = bindingResult.allowBindingOnFinalize;
    adjustedCurrent = bindingResult.position;
    var endBinding = bindingResult.binding;
    final startBinding = bindingResult.startBinding ?? endpoints.startBinding;
    final closeTolerance =
        config.selection.interaction.handleTolerance *
        _loopCloseToleranceMultiplier;
    if (elementData.arrowType != ArrowType.elbow &&
        endpoints.fixedPoints.length >= 2) {
      final startPoint = endpoints.fixedPoints.first;
      if (adjustedCurrent.distanceSquared(startPoint) <=
          closeTolerance * closeTolerance) {
        adjustedCurrent = startPoint;
        endBinding = startBinding;
      }
    }

    final allPoints = _appendCurrentPoint(
      fixedPoints: endpoints.fixedPoints,
      currentPoint: adjustedCurrent,
    );
    late final DrawRect arrowRect;
    late final List<DrawPoint> normalizedPoints;
    var resolvedStartBinding = startBinding;
    var resolvedEndBinding = endBinding;
    List<ElbowFixedSegment>? resolvedFixedSegments;
    bool? resolvedStartIsSpecial;
    bool? resolvedEndIsSpecial;
    if (elementData.arrowType == ArrowType.elbow) {
      final routed = routeElbowArrow(
        start: endpoints.startPosition,
        end: adjustedCurrent,
        startBinding: resolvedStartBinding,
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
      normalizedPoints = normalizeArrowPoints(
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
      normalizedPoints = normalizeArrowPoints(
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
    bool snapOverrideActive = false,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    if (!creatingState.isPointCreation) {
      return null;
    }

    final elementData = requireCreatingElementDataType<ConnectorData>(
      creatingState: creatingState,
      strategyName: 'ConnectorCreationStrategy.addPoint',
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
      snapOverrideActive: snapOverrideActive,
      sessionData: sessionData,
      maintainAspectRatio: false,
      createFromCenter: false,
    );
    var adjustedPosition = endpoints.currentPosition;

    final bindingResult = _snapBindingPoint(
      state: state,
      config: config,
      data: elementData,
      position: adjustedPosition,
      snappingMode: snappingMode,
      dragStart: false,
      preferredBinding: elementData.endBinding,
      oppositeBinding: endpoints.startBinding,
      oppositePoint: endpoints.segmentStart,
      initialBinding: false,
      preserveOppositeInsideBinding: sessionData.preserveStartInsideBinding,
      oppositeOrbitFocusPoint: sessionData.startOrbitFocusPoint,
      angleLocked: false,
      altKey: false,
      snapOverrideActive: snapOverrideActive,
    );
    sessionData.allowBindingOnFinalize = bindingResult.allowBindingOnFinalize;
    adjustedPosition = bindingResult.position;
    final resolvedStartBinding =
        bindingResult.startBinding ?? endpoints.startBinding;

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
    final normalizedPoints = normalizeArrowPoints(
      worldPoints: allPoints,
      rect: arrowRect,
    );
    final updatedData = elementData.copyWith(
      points: normalizedPoints,
      startBinding: resolvedStartBinding,
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
    final data = requireCreatingElementDataType<ConnectorData>(
      creatingState: creatingState,
      strategyName: 'ConnectorCreationStrategy.finish',
    );

    final minSize = config.element.minCreateSize;
    final finishTolerance = config.selection.interaction.handleTolerance;
    final worldPoints = resolveArrowWorldPoints(
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
    final normalizedPoints = normalizeArrowPoints(
      worldPoints: closedPoints,
      rect: arrowRect,
    );
    _ArrowCreationFinishResult finalizedResult = (
      rect: arrowRect,
      data: data.copyWith(points: normalizedPoints),
      orderedElementIds: null,
    );
    final sessionData = _resolveSessionData(creatingState.creationMode);
    if (config.snap.enableArrowBinding) {
      finalizedResult = _finalizeArrowCreationBindings(
        state: state,
        config: config,
        elementId: creatingState.element.id,
        result: finalizedResult,
        sessionData: sessionData,
      );
    }

    final points = resolveArrowWorldPoints(
      rect: finalizedResult.rect,
      normalizedPoints: finalizedResult.data.points,
    );
    final length = ConnectorGeometry.calculateShaftLength(
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
  ConnectorData data,
  List<String>? orderedElementIds,
});

_ArrowCreationFinishResult _finalizeArrowCreationBindings({
  required DrawState state,
  required DrawConfig config,
  required String elementId,
  required _ArrowCreationFinishResult result,
  required _ArrowCreationSessionData sessionData,
}) {
  final worldPoints = resolveArrowWorldPoints(
    rect: result.rect,
    normalizedPoints: result.data.points,
  );
  if (worldPoints.length < 2) {
    return result;
  }

  final bindingDistance = resolveCoreMaxBindingDistance(
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
      sessionData.startOrbitFocusPoint ??
      (result.data.startBinding?.mode == ArrowBindingMode.orbit
          ? worldPoints.first
          : null);
  final coreContext = buildCoreEngineContext(
    zoom: state.application.view.camera.zoom,
    isBindingEnabled: config.snap.enableArrowBinding,
  );
  final allowNewBinding = sessionData.allowBindingOnFinalize;
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
    allowNewBinding: allowNewBinding,
    bindingDistance: bindingDistance,
    coreEngineContext: coreContext,
    fixedSegments: result.data.fixedSegments,
    orderedElementIds: orderedElementIds,
    options: ArrowCoreEndpointBindingOptions(
      newArrow: true,
      altKey: preserveDraggedInsideBinding,
      preserveOppositeInsideBinding: preserveOppositeInsideBinding,
      oppositeOrbitFocusPoint: oppositeOrbitFocusPoint,
    ),
  );
  if (finalized == null) {
    return result;
  }
  final currentArrow = toCoreArrowState(
    element: previewElement,
    data: result.data,
    maxCoordinate: coreContext.maxCoordinate,
  );
  final patchedElement = finalized.arrow == currentArrow
      ? previewElement
      : applyCoreArrowStateToElement(
          element: previewElement,
          data: result.data,
          nextArrow: finalized.arrow,
        );
  final patchedData = patchedElement.data;
  if (patchedData is! ConnectorData) {
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
  required bool snapOverrideActive,
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
    snapOverrideActive: snapOverrideActive,
    sessionData: sessionData,
    maintainAspectRatio: maintainAspectRatio,
    createFromCenter: createFromCenter,
  );
  var adjustedCurrent = endpoints.currentPosition;

  final bindingResult = _snapBindingPoint(
    state: state,
    config: config,
    data: data,
    position: adjustedCurrent,
    snappingMode: snappingMode,
    dragStart: false,
    preferredBinding: data.endBinding,
    oppositeBinding: endpoints.startBinding,
    oppositePoint: endpoints.segmentStart,
    initialBinding: false,
    preserveOppositeInsideBinding: sessionData.preserveStartInsideBinding,
    oppositeOrbitFocusPoint: sessionData.startOrbitFocusPoint,
    angleLocked: maintainAspectRatio,
    altKey: createFromCenter,
    snapOverrideActive: snapOverrideActive,
  );
  sessionData.allowBindingOnFinalize = bindingResult.allowBindingOnFinalize;
  adjustedCurrent = bindingResult.position;
  var endBinding = bindingResult.binding;
  final resolvedStartBinding =
      bindingResult.startBinding ?? endpoints.startBinding;

  final closeTolerance =
      config.selection.interaction.handleTolerance *
      _loopCloseToleranceMultiplier;
  if (endpoints.fixedPoints.length >= 2) {
    final firstPoint = endpoints.fixedPoints.first;
    if (adjustedCurrent.distanceSquared(firstPoint) <=
        closeTolerance * closeTolerance) {
      adjustedCurrent = firstPoint;
      endBinding = resolvedStartBinding;
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
    normalizedPoints = normalizeArrowPoints(
      worldPoints: worldPoints,
      rect: lineRect,
    );
  }
  final updatedData = data.copyWith(
    points: normalizedPoints,
    startBinding: resolvedStartBinding,
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
  required ConnectorData data,
  required DrawPoint currentPosition,
  required SnappingMode snappingMode,
  required bool snapOverrideActive,
  required _ArrowCreationSessionData sessionData,
  required bool maintainAspectRatio,
  required bool createFromCenter,
}) {
  sessionData.allowBindingOnFinalize = _shouldAttemptBinding(
    snapConfig: config.snap,
    snappingMode: snappingMode,
    snapOverrideActive: snapOverrideActive,
  );
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
    data: data,
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
    snapOverrideActive: snapOverrideActive,
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
}) =>
    calculateArrowPathBoundsViaCore(worldPoints: points, arrowType: arrowType);

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
  required ConnectorData data,
  required DrawPoint position,
  required SnappingMode snappingMode,
  required bool dragStart,
  required ArrowBinding? preferredBinding,
  required ArrowBinding? oppositeBinding,
  required DrawPoint oppositePoint,
  required bool initialBinding,
  required bool angleLocked,
  required bool altKey,
  required bool snapOverrideActive,
  bool newArrow = true,
  bool? preserveOppositeInsideBinding,
  DrawPoint? oppositeOrbitFocusPoint,
}) {
  final snapConfig = config.snap;
  final shouldLookupBindings = _shouldAttemptBinding(
    snapConfig: snapConfig,
    snappingMode: snappingMode,
    snapOverrideActive: snapOverrideActive,
  );
  final bindingDistance = shouldLookupBindings
      ? resolveCoreMaxBindingDistance(zoom: state.application.view.camera.zoom)
      : 0.0;
  if (!shouldLookupBindings || bindingDistance <= 0) {
    return _BindingSnapResult(
      position: position,
      allowBindingOnFinalize: false,
    );
  }

  final coreEngineContext = buildCoreEngineContext(
    zoom: state.application.view.camera.zoom,
  );
  final shouldPreserveOppositeInsideBinding =
      preserveOppositeInsideBinding ??
      oppositeBinding?.mode == ArrowBindingMode.inside;
  final resolvedOppositeOrbitFocusPoint =
      oppositeOrbitFocusPoint ??
      (oppositeBinding?.mode == ArrowBindingMode.orbit ? oppositePoint : null);
  final bindingResult = _resolveBindingWithCoreEndpointPreview(
    state: state,
    data: data,
    worldPointer: position,
    oppositePoint: oppositePoint,
    dragStart: dragStart,
    preferredBinding: preferredBinding,
    oppositeBinding: oppositeBinding,
    shouldLookupBindings: shouldLookupBindings,
    allowNewBinding: shouldLookupBindings,
    bindingDistance: bindingDistance,
    coreEngineContext: coreEngineContext,
    options: ArrowCoreEndpointBindingOptions(
      newArrow: newArrow,
      initialBinding: initialBinding,
      preserveOppositeInsideBinding: shouldPreserveOppositeInsideBinding,
      oppositeOrbitFocusPoint: resolvedOppositeOrbitFocusPoint,
      angleLocked: angleLocked,
      altKey: altKey,
    ),
  );
  if (bindingResult == null || bindingResult.binding == null) {
    return _BindingSnapResult(position: position);
  }

  return _BindingSnapResult(
    position: bindingResult.snapPoint,
    binding: bindingResult.binding,
    startBinding: bindingResult.startBinding,
    endBinding: bindingResult.endBinding,
  );
}

_CorePreviewBindingResult? _resolveBindingWithCoreEndpointPreview({
  required DrawState state,
  required ConnectorData data,
  required DrawPoint worldPointer,
  required DrawPoint oppositePoint,
  required bool dragStart,
  required ArrowBinding? preferredBinding,
  required ArrowBinding? oppositeBinding,
  required bool shouldLookupBindings,
  required bool allowNewBinding,
  required double bindingDistance,
  required core.EngineContext coreEngineContext,
  ArrowCoreEndpointBindingOptions options =
      const ArrowCoreEndpointBindingOptions(),
}) {
  final startPoint = dragStart ? worldPointer : oppositePoint;
  final endPoint = dragStart ? oppositePoint : worldPointer;
  final previewStartBinding = dragStart ? preferredBinding : oppositeBinding;
  final previewEndBinding = dragStart ? oppositeBinding : preferredBinding;

  if (data.arrowType == ArrowType.elbow) {
    final routed = routeElbowArrow(
      start: startPoint,
      end: endPoint,
      startBinding: previewStartBinding,
      endBinding: previewEndBinding,
      elementsById: state.domain.document.elementMap,
      startArrowhead: data.startArrowhead,
      endArrowhead: data.endArrowhead,
      engineContext: coreEngineContext,
    );
    final previewRect = _calculateArrowRect(
      points: routed.points,
      arrowType: data.arrowType,
    );
    final previewData =
        data.copyWith(
              points: normalizeArrowPoints(
                worldPoints: routed.points,
                rect: previewRect,
              ),
              startBinding: routed.startBinding,
              endBinding: routed.endBinding,
              fixedSegments: routed.fixedSegments,
              startIsSpecial: routed.startIsSpecial,
              endIsSpecial: routed.endIsSpecial,
            )
            as ArrowData;
    final previewElement = ElementState(
      id: '__binding-preview__',
      rect: previewRect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: previewData,
    );
    final previewPoints = List<DrawPoint>.of(routed.points, growable: false);
    final draggedIndex = dragStart ? 0 : previewPoints.length - 1;
    if (dragStart) {
      previewPoints[0] = startPoint;
    } else {
      previewPoints[draggedIndex] = endPoint;
    }

    final activeBinding = dragStart
        ? previewData.startBinding
        : previewData.endBinding;
    final previewOppositeBinding = dragStart
        ? previewData.endBinding
        : previewData.startBinding;
    final candidates = resolveArrowBindableCandidatesForEndpointStrategy(
      document: state.domain.document,
      allowNewBinding: allowNewBinding,
      activeBinding: activeBinding,
      oppositeBinding: previewOppositeBinding,
      excludedElementId: previewElement.id,
    );
    final dragContext = shouldLookupBindings && allowNewBinding
        ? coreEngineContext
        : buildCoreEngineContext(
            zoom: coreEngineContext.zoom,
            isBindingEnabled: false,
            bindMode: coreEngineContext.bindMode,
            maxCoordinate: coreEngineContext.maxCoordinate,
          );
    final previewArrow = toCoreArrowState(
      element: previewElement,
      data: previewData,
      localPointsOverride: previewPoints,
      fixedSegmentsOverride: routed.fixedSegments,
      startBindingOverride: previewData.startBinding,
      endBindingOverride: previewData.endBinding,
      maxCoordinate: coreEngineContext.maxCoordinate,
    );
    final strategies = resolveCoreEndpointBindingStrategy(
      arrow: previewArrow,
      draggedPoints: <int, core.Point>{
        draggedIndex: <double>[
          worldPointer.x - previewArrow.x,
          worldPointer.y - previewArrow.y,
        ],
      },
      pointer: toCorePoint(worldPointer),
      bindables: candidates.bindables,
      context: dragContext,
      options: options,
    );
    final draggedStrategy = dragStart ? strategies.start : strategies.end;
    final strategyArrow = _applyCoreEndpointStrategyToArrow(
      arrow: previewArrow,
      edge: dragStart ? core.arrowEndpointStart : core.arrowEndpointEnd,
      strategy: draggedStrategy,
    );

    var resolvedStartBinding = fromCoreBinding(strategyArrow.startBinding);
    var resolvedEndBinding = fromCoreBinding(strategyArrow.endBinding);
    if (dragStart) {
      resolvedEndBinding = oppositeBinding;
    } else {
      resolvedStartBinding = oppositeBinding;
    }

    final elbowResult = computeElbowEdit(
      element: previewElement,
      data: previewData.copyWith(
        startBinding: resolvedStartBinding,
        endBinding: resolvedEndBinding,
      ),
      lookup: CombinedElementLookup(base: state.domain.document.elementMap),
      localPointsOverride: <DrawPoint>[startPoint, endPoint],
      engineContext: coreEngineContext,
    );
    resolvedStartBinding = elbowResult.startBinding;
    resolvedEndBinding = elbowResult.endBinding;

    final binding = dragStart ? resolvedStartBinding : resolvedEndBinding;
    if (binding == null) {
      return null;
    }

    final preferredElementId = preferredBinding?.elementId;
    if (!allowNewBinding &&
        preferredElementId != null &&
        binding.elementId != preferredElementId) {
      return null;
    }

    final snappedPoint = dragStart
        ? elbowResult.localPoints.first
        : elbowResult.localPoints.last;
    return _CorePreviewBindingResult(
      binding: binding,
      snapPoint: snappedPoint,
      startBinding: resolvedStartBinding,
      endBinding: resolvedEndBinding,
    );
  }

  final previewLayout = computeArrowTwoPointLayout(
    first: startPoint,
    second: endPoint,
  );
  final previewData = data.copyWith(
    points: previewLayout.normalizedPoints,
    startBinding: previewStartBinding,
    endBinding: previewEndBinding,
  );
  final previewElement = ElementState(
    id: '__binding-preview__',
    rect: previewLayout.rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: previewData,
  );
  final draggedIndex = dragStart ? 0 : 1;
  final dragResult = computeArrowCoreEndpointDragResult(
    state: state,
    element: previewElement,
    data: previewData,
    localPoints: <DrawPoint>[startPoint, endPoint],
    draggedIndex: draggedIndex,
    worldPointer: worldPointer,
    startBinding: previewData.startBinding,
    endBinding: previewData.endBinding,
    excludedElementId: previewElement.id,
    shouldLookupBindings: shouldLookupBindings,
    allowNewBinding: allowNewBinding,
    bindingDistance: bindingDistance,
    coreEngineContext: coreEngineContext,
    options: options,
  );
  if (dragResult == null) {
    return null;
  }

  var resolvedStartBinding = dragResult.startBinding;
  var resolvedEndBinding = dragResult.endBinding;
  if (dragStart && oppositeBinding != null) {
    resolvedEndBinding = oppositeBinding;
  } else if (!dragStart && oppositeBinding != null) {
    resolvedStartBinding = oppositeBinding;
  }

  final binding = dragStart ? resolvedStartBinding : resolvedEndBinding;
  if (binding == null) {
    return null;
  }

  final preferredElementId = preferredBinding?.elementId;
  if (!allowNewBinding &&
      preferredElementId != null &&
      binding.elementId != preferredElementId) {
    return null;
  }

  final snappedPoint = dragStart
      ? dragResult.worldPoints.first
      : dragResult.worldPoints.last;
  return _CorePreviewBindingResult(
    binding: binding,
    snapPoint: snappedPoint,
    startBinding: resolvedStartBinding,
    endBinding: resolvedEndBinding,
  );
}

core.ArrowState _applyCoreEndpointStrategyToArrow({
  required core.ArrowState arrow,
  required core.ArrowEndpointEdge edge,
  required core.EndpointBindingStrategy? strategy,
}) {
  if (strategy == null) {
    return arrow;
  }
  if (strategy.mode == null) {
    final mutation = unbindCoreArrowEndpoint(arrow: arrow, edge: edge);
    return core.applyArrowPatch(arrow, mutation.arrowPatch);
  }

  final bindable = strategy.element;
  final focusPoint = strategy.focusPoint;
  if (bindable == null || focusPoint == null) {
    return arrow;
  }

  final mutation = bindCoreArrowEndpoint(
    arrow: arrow,
    edge: edge,
    bindable: bindable,
    mode: strategy.mode,
    focusPoint: focusPoint,
  );
  return core.applyArrowPatch(arrow, mutation.arrowPatch);
}

_BindingSnapResult _resolveStartBindingPoint({
  required DrawState state,
  required DrawConfig config,
  required ConnectorData data,
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
  required bool snapOverrideActive,
}) {
  final snapConfig = config.snap;
  final bindingEnabled = _shouldAttemptBinding(
    snapConfig: snapConfig,
    snappingMode: snappingMode,
    snapOverrideActive: snapOverrideActive,
  );
  final bindingDistance = bindingEnabled
      ? resolveCoreMaxBindingDistance(zoom: state.application.view.camera.zoom)
      : 0.0;
  final shouldReusePreferredBinding =
      preferredBinding != null &&
      (preferredBinding.mode == ArrowBindingMode.orbit ||
          (preferredBinding.mode == ArrowBindingMode.inside &&
              sessionData.preserveStartInsideBinding));
  if (shouldReusePreferredBinding) {
    final stableBinding = preferredBinding;
    final target = state.domain.document.getElementById(
      stableBinding.elementId,
    );
    if (target != null &&
        target.opacity > 0 &&
        ArrowBindingUtils.isBindableTarget(target)) {
      final boundPoint = arrowType == ArrowType.elbow
          ? ArrowBindingUtils.resolveElbowBoundPoint(
              binding: stableBinding,
              target: target,
              hasArrowhead: startArrowheadStyle != ArrowheadStyle.none,
              bindables: state.domain.document.arrowBindableStates,
            )
          : ArrowBindingUtils.resolveBoundPoint(
              binding: stableBinding,
              target: target,
              referencePoint: oppositePoint,
              bindables: state.domain.document.arrowBindableStates,
            );
      if (boundPoint != null) {
        return _BindingSnapResult(position: boundPoint, binding: stableBinding);
      }
    }
  }
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
    data: data,
    position: startPosition,
    snappingMode: snappingMode,
    dragStart: true,
    preferredBinding: preferredBinding,
    oppositeBinding: oppositeBinding,
    // Excalidraw parity: start-point initial binding is computed from the
    // pointer-down origin before the dragged endpoint moves away.
    oppositePoint: preferredBinding == null ? startPosition : oppositePoint,
    initialBinding: preferredBinding == null,
    angleLocked: angleLocked,
    altKey: altKey,
    snapOverrideActive: snapOverrideActive,
  );
  if (preferredBinding == null) {
    final resolvedMode = resolved.binding?.mode;
    sessionData
      ..preserveStartInsideBinding = resolvedMode == ArrowBindingMode.inside
      ..startOrbitFocusPoint = resolvedMode == ArrowBindingMode.orbit
          ? resolved.position
          : null;
  }
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
  required bool snapOverrideActive,
}) => shouldAttemptArrowBinding(
  snapConfig: snapConfig,
  snappingMode: snappingMode,
  snapOverrideActive: snapOverrideActive,
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
  var preserveStartInsideBinding = false;
  DrawPoint? startOrbitFocusPoint;
  var allowBindingOnFinalize = true;
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
            bindables: state.domain.document.arrowBindableStates,
          )
        : ArrowBindingUtils.resolveBoundPoint(
            binding: cachedBinding,
            target: target,
            referencePoint: oppositePoint,
            bindables: state.domain.document.arrowBindableStates,
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
  const _BindingSnapResult({
    required this.position,
    this.binding,
    this.startBinding,
    this.endBinding,
    this.allowBindingOnFinalize = true,
  });

  final DrawPoint position;
  final ArrowBinding? binding;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final bool allowBindingOnFinalize;
}

@immutable
class _CorePreviewBindingResult {
  const _CorePreviewBindingResult({
    required this.snapPoint,
    this.binding,
    this.startBinding,
    this.endBinding,
  });

  final DrawPoint snapPoint;
  final ArrowBinding? binding;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
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
