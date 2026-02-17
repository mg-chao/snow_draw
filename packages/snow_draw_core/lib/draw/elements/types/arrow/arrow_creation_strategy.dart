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
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../../types/snap_guides.dart';
import '../../../utils/snapping_mode.dart';
import '../arrow/arrow_binding.dart';
import '../line/line_data.dart';
import 'arrow_binding_snapper.dart';
import 'arrow_binding_target_cache.dart';
import 'arrow_geometry.dart';
import 'arrow_like_data.dart';
import 'arrow_two_point_layout.dart';
import 'elbow/elbow_router.dart';

/// Creation strategy for arrow elements (single- and multi-point).
@immutable
class ArrowCreationStrategy extends PointCreationStrategy {
  const ArrowCreationStrategy();

  @override
  CreationUpdateResult start({
    required ElementData data,
    required DrawPoint startPosition,
  }) {
    if (data is! ArrowLikeData) {
      return CreationUpdateResult(
        data: data,
        rect: DrawRect(
          minX: startPosition.x,
          minY: startPosition.y,
          maxX: startPosition.x,
          maxY: startPosition.y,
        ),
        creationMode: const RectCreationMode(),
      );
    }

    final arrowRect = _calculateArrowRect(
      points: [startPosition, startPosition],
      arrowType: data.arrowType,
      strokeWidth: data.strokeWidth,
    );
    final normalizedPoints = ArrowGeometry.normalizePoints(
      worldPoints: [startPosition, startPosition],
      rect: arrowRect,
    );
    final updatedData = data.copyWith(points: normalizedPoints);
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
  }) {
    if (maintainAspectRatio || createFromCenter) {
      // Point creation ignores these modifiers.
    }
    final elementData = creatingState.elementData;
    if (elementData is! ArrowLikeData) {
      return CreationUpdateResult(
        data: elementData,
        rect: creatingState.currentRect,
        creationMode: creatingState.creationMode,
      );
    }
    if (elementData is LineData) {
      return _updateLine(
        state: state,
        config: config,
        creatingState: creatingState,
        currentPosition: currentPosition,
        snappingMode: snappingMode,
        data: elementData,
      );
    }
    final sessionData = _resolveSessionData(creatingState.creationMode);

    final gridConfig = config.grid;
    final snapToGrid = snappingMode == SnappingMode.grid;
    var startPosition = snapToGrid
        ? gridSnapService.snapPoint(
            point: creatingState.startPosition,
            gridSize: gridConfig.size,
          )
        : creatingState.startPosition;
    var adjustedCurrent = snapToGrid
        ? gridSnapService.snapPoint(
            point: currentPosition,
            gridSize: gridConfig.size,
          )
        : currentPosition;

    final startBindingResult = _resolveStartBindingPoint(
      state: state,
      config: config,
      startPosition: startPosition,
      snappingMode: snappingMode,
      arrowType: elementData.arrowType,
      arrowheadStyle: elementData.startArrowhead,
      preferredBinding: elementData.startBinding,
      referencePoint: adjustedCurrent,
      sessionData: sessionData,
    );
    startPosition = startBindingResult.position;

    final fixedPoints = _applyBoundStartToFixedPoints(
      fixedPoints: creatingState.fixedPoints,
      boundStart: startPosition,
    );
    final segmentStart = fixedPoints.isNotEmpty
        ? fixedPoints.last
        : startPosition;
    adjustedCurrent = _resolveArrowSegmentPosition(
      segmentStart: segmentStart,
      currentPosition: adjustedCurrent,
    );

    var snapGuides = const <SnapGuide>[];
    final snapResult = _snapCreatePoint(
      state: state,
      config: config,
      position: adjustedCurrent,
      snappingMode: snappingMode,
      sessionData: sessionData,
    );
    adjustedCurrent = snapResult.position;
    snapGuides = snapResult.guides;

    final bindingResult = _snapBindingPoint(
      state: state,
      config: config,
      position: adjustedCurrent,
      snappingMode: snappingMode,
      arrowType: elementData.arrowType,
      arrowheadStyle: elementData.endArrowhead,
      preferredBinding: elementData.endBinding,
      referencePoint: segmentStart,
      targetCache: sessionData.endTargetCache,
    );
    adjustedCurrent = bindingResult.position;
    var endBinding = bindingResult.binding;
    final closeTolerance =
        config.selection.interaction.handleTolerance *
        _loopCloseToleranceMultiplier;
    if (elementData.arrowType != ArrowType.elbow && fixedPoints.length >= 2) {
      final startPoint = fixedPoints.first;
      if (adjustedCurrent.distanceSquared(startPoint) <=
          closeTolerance * closeTolerance) {
        adjustedCurrent = startPoint;
        endBinding = startBindingResult.binding;
      }
    }

    final allPoints = _appendCurrentPoint(
      fixedPoints: fixedPoints,
      currentPoint: adjustedCurrent,
    );
    late final DrawRect arrowRect;
    late final List<DrawPoint> normalizedPoints;
    if (elementData.arrowType == ArrowType.elbow) {
      final routedPoints = routeElbowArrow(
        start: startPosition,
        end: adjustedCurrent,
        startBinding: startBindingResult.binding,
        endBinding: bindingResult.binding,
        elementsById: state.domain.document.elementMap,
        startArrowhead: elementData.startArrowhead,
        endArrowhead: elementData.endArrowhead,
      ).points;
      arrowRect = _calculateArrowRect(
        points: routedPoints,
        arrowType: elementData.arrowType,
        strokeWidth: elementData.strokeWidth,
      );
      normalizedPoints = ArrowGeometry.normalizePoints(
        worldPoints: routedPoints,
        rect: arrowRect,
      );
    } else if (fixedPoints.length == 1) {
      final layout = computeArrowTwoPointLayout(
        first: fixedPoints.first,
        second: adjustedCurrent,
      );
      arrowRect = layout.rect;
      normalizedPoints = layout.normalizedPoints;
    } else {
      arrowRect = _calculateArrowRect(
        points: allPoints,
        arrowType: elementData.arrowType,
        strokeWidth: elementData.strokeWidth,
      );
      normalizedPoints = ArrowGeometry.normalizePoints(
        worldPoints: allPoints,
        rect: arrowRect,
      );
    }
    final updatedData = elementData.copyWith(
      points: normalizedPoints,
      startBinding: startBindingResult.binding,
      endBinding: endBinding,
    );

    return CreationUpdateResult(
      data: updatedData,
      rect: arrowRect,
      snapGuides: snapGuides,
      creationMode: PointCreationMode(
        fixedPoints: elementData.arrowType == ArrowType.elbow
            ? List<DrawPoint>.unmodifiable([startPosition])
            : fixedPoints,
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
  }) {
    if (!creatingState.isPointCreation) {
      return null;
    }

    final elementData = creatingState.elementData;
    if (elementData is! ArrowLikeData) {
      return null;
    }
    if (elementData.arrowType == ArrowType.elbow) {
      return null;
    }
    final sessionData = _resolveSessionData(creatingState.creationMode);

    final gridConfig = config.grid;
    final snapToGrid = snappingMode == SnappingMode.grid;
    var adjustedPosition = snapToGrid
        ? gridSnapService.snapPoint(point: position, gridSize: gridConfig.size)
        : position;

    var startPosition = snapToGrid
        ? gridSnapService.snapPoint(
            point: creatingState.startPosition,
            gridSize: gridConfig.size,
          )
        : creatingState.startPosition;
    final startBindingResult = _resolveStartBindingPoint(
      state: state,
      config: config,
      startPosition: startPosition,
      snappingMode: snappingMode,
      arrowType: elementData.arrowType,
      arrowheadStyle: elementData.startArrowhead,
      preferredBinding: elementData.startBinding,
      referencePoint: adjustedPosition,
      sessionData: sessionData,
    );
    startPosition = startBindingResult.position;

    final fixedPoints = _applyBoundStartToFixedPoints(
      fixedPoints: creatingState.fixedPoints,
      boundStart: startPosition,
    );
    final segmentStart = fixedPoints.isNotEmpty
        ? fixedPoints.last
        : startPosition;
    adjustedPosition = _resolveArrowSegmentPosition(
      segmentStart: segmentStart,
      currentPosition: adjustedPosition,
    );
    final snapResult = _snapCreatePoint(
      state: state,
      config: config,
      position: adjustedPosition,
      snappingMode: snappingMode,
      sessionData: sessionData,
    );
    adjustedPosition = snapResult.position;
    final snapGuides = snapResult.guides;

    final bindingResult = _snapBindingPoint(
      state: state,
      config: config,
      position: adjustedPosition,
      snappingMode: snappingMode,
      arrowType: elementData.arrowType,
      arrowheadStyle: elementData.endArrowhead,
      preferredBinding: elementData.endBinding,
      referencePoint: segmentStart,
      targetCache: sessionData.endTargetCache,
    );
    adjustedPosition = bindingResult.position;

    var updatedFixedPoints = fixedPoints;
    if (updatedFixedPoints.isEmpty ||
        updatedFixedPoints.last != adjustedPosition) {
      updatedFixedPoints = List<DrawPoint>.unmodifiable([
        ...updatedFixedPoints,
        adjustedPosition,
      ]);
    }
    updatedFixedPoints = _applyBoundStartToFixedPoints(
      fixedPoints: updatedFixedPoints,
      boundStart: startPosition,
    );
    final allPoints = _appendCurrentPoint(
      fixedPoints: updatedFixedPoints,
      currentPoint: adjustedPosition,
    );
    final arrowRect = _calculateArrowRect(
      points: allPoints,
      arrowType: elementData.arrowType,
      strokeWidth: elementData.strokeWidth,
    );
    final normalizedPoints = ArrowGeometry.normalizePoints(
      worldPoints: allPoints,
      rect: arrowRect,
    );
    final updatedData = elementData.copyWith(
      points: normalizedPoints,
      startBinding: startBindingResult.binding,
      endBinding: bindingResult.binding,
    );

    return CreationUpdateResult(
      data: updatedData,
      rect: arrowRect,
      snapGuides: snapGuides,
      creationMode: PointCreationMode(
        fixedPoints: updatedFixedPoints,
        currentPoint: adjustedPosition,
        sessionData: sessionData,
      ),
    );
  }

  @override
  CreationFinishResult finish({
    required DrawConfig config,
    required CreatingState creatingState,
  }) {
    final data = creatingState.elementData;
    if (data is! ArrowLikeData) {
      return CreationFinishResult(
        data: data,
        rect: creatingState.currentRect,
        shouldCommit: false,
      );
    }

    final minSize = config.element.minCreateSize;
    final finishTolerance = config.selection.interaction.handleTolerance;
    final rawPoints = creatingState.isPointCreation
        ? _resolveFinalArrowPoints(
            interaction: creatingState,
            finishTolerance: finishTolerance,
          )
        : _resolveArrowWorldPoints(
            rect: creatingState.currentRect,
            normalizedPoints: data.points,
          );
    final finalPoints = data.arrowType == ArrowType.elbow
        ? _resolveArrowWorldPoints(
            rect: creatingState.currentRect,
            normalizedPoints: data.points,
          )
        : rawPoints;
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
      strokeWidth: data.strokeWidth,
    );
    final normalizedPoints = ArrowGeometry.normalizePoints(
      worldPoints: closedPoints,
      rect: arrowRect,
    );
    final updatedData = data.copyWith(points: normalizedPoints);
    final points = ArrowGeometry.resolveWorldPoints(
      rect: arrowRect,
      normalizedPoints: updatedData.points,
    );
    final length = ArrowGeometry.calculateShaftLength(
      points: points,
      arrowType: updatedData.arrowType,
    );
    if (!length.isFinite || length < minSize) {
      return CreationFinishResult(
        data: data,
        rect: creatingState.currentRect,
        shouldCommit: false,
      );
    }

    return CreationFinishResult(
      data: updatedData,
      rect: arrowRect,
      shouldCommit: true,
    );
  }
}

CreationUpdateResult _updateLine({
  required DrawState state,
  required DrawConfig config,
  required CreatingState creatingState,
  required DrawPoint currentPosition,
  required SnappingMode snappingMode,
  required LineData data,
}) {
  final sessionData = _resolveSessionData(creatingState.creationMode);
  final lineEndpoints = _resolveLineEndpoints(
    state: state,
    config: config,
    creatingState: creatingState,
    data: data,
    currentPosition: currentPosition,
    snappingMode: snappingMode,
    sessionData: sessionData,
  );

  final snapResult = _snapCreatePoint(
    state: state,
    config: config,
    position: lineEndpoints.currentPosition,
    snappingMode: snappingMode,
    sessionData: sessionData,
  );
  var adjustedCurrent = snapResult.position;

  final bindingResult = _snapBindingPoint(
    state: state,
    config: config,
    position: adjustedCurrent,
    snappingMode: snappingMode,
    arrowType: data.arrowType,
    arrowheadStyle: data.endArrowhead,
    preferredBinding: data.endBinding,
    referencePoint: lineEndpoints.segmentStart,
    targetCache: sessionData.endTargetCache,
    targetCacheThresholdFactor: _lineBindingCacheTargetThresholdFactor,
  );
  adjustedCurrent = bindingResult.position;
  var endBinding = bindingResult.binding;

  final closeTolerance =
      config.selection.interaction.handleTolerance *
      _loopCloseToleranceMultiplier;
  if (lineEndpoints.fixedPoints.length >= 2) {
    final firstPoint = lineEndpoints.fixedPoints.first;
    if (adjustedCurrent.distanceSquared(firstPoint) <=
        closeTolerance * closeTolerance) {
      adjustedCurrent = firstPoint;
      endBinding = lineEndpoints.startBinding;
    }
  }

  final worldPoints = _appendCurrentPoint(
    fixedPoints: lineEndpoints.fixedPoints,
    currentPoint: adjustedCurrent,
  );
  late final DrawRect lineRect;
  late final List<DrawPoint> normalizedPoints;
  if (worldPoints.length == 2) {
    final layout = computeArrowTwoPointLayout(
      first: worldPoints.first,
      second: worldPoints.last,
    );
    lineRect = layout.rect;
    normalizedPoints = layout.normalizedPoints;
  } else {
    lineRect = _calculateArrowRect(
      points: worldPoints,
      arrowType: data.arrowType,
      strokeWidth: data.strokeWidth,
    );
    normalizedPoints = ArrowGeometry.normalizePoints(
      worldPoints: worldPoints,
      rect: lineRect,
    );
  }
  final updatedData = data.copyWith(
    points: normalizedPoints,
    startBinding: lineEndpoints.startBinding,
    endBinding: endBinding,
  );

  return CreationUpdateResult(
    data: updatedData,
    rect: lineRect,
    snapGuides: snapResult.guides,
    creationMode: PointCreationMode(
      fixedPoints: lineEndpoints.fixedPoints,
      currentPoint: adjustedCurrent,
      sessionData: sessionData,
    ),
  );
}

const _loopCloseToleranceMultiplier = 1.5;
const _defaultBindingCacheTargetThresholdFactor = 0.4;
const _defaultBindingCacheEmptyThresholdFactor = 0.75;
const _lineBindingCacheTargetThresholdFactor = 0.9;

_LineEndpointResolution _resolveLineEndpoints({
  required DrawState state,
  required DrawConfig config,
  required CreatingState creatingState,
  required LineData data,
  required DrawPoint currentPosition,
  required SnappingMode snappingMode,
  required _ArrowCreationSessionData sessionData,
}) {
  final gridConfig = config.grid;
  final snapToGrid = snappingMode == SnappingMode.grid;
  var startPosition = snapToGrid
      ? gridSnapService.snapPoint(
          point: creatingState.startPosition,
          gridSize: gridConfig.size,
        )
      : creatingState.startPosition;
  var adjustedCurrent = snapToGrid
      ? gridSnapService.snapPoint(
          point: currentPosition,
          gridSize: gridConfig.size,
        )
      : currentPosition;

  final startBindingResult = _resolveStartBindingPoint(
    state: state,
    config: config,
    startPosition: startPosition,
    snappingMode: snappingMode,
    arrowType: data.arrowType,
    arrowheadStyle: data.startArrowhead,
    preferredBinding: data.startBinding,
    referencePoint: adjustedCurrent,
    sessionData: sessionData,
    targetCacheThresholdFactor: _lineBindingCacheTargetThresholdFactor,
  );
  startPosition = startBindingResult.position;

  final fixedPoints = _applyBoundStartToFixedPoints(
    fixedPoints: creatingState.fixedPoints,
    boundStart: startPosition,
  );
  final segmentStart = fixedPoints.isNotEmpty
      ? fixedPoints.last
      : startPosition;
  adjustedCurrent = _resolveArrowSegmentPosition(
    segmentStart: segmentStart,
    currentPosition: adjustedCurrent,
  );

  return _LineEndpointResolution(
    fixedPoints: fixedPoints,
    segmentStart: segmentStart,
    currentPosition: adjustedCurrent,
    startBinding: startBindingResult.binding,
  );
}

/// Calculates accurate bounding rect for arrow, accounting for curved paths.
DrawRect _calculateArrowRect({
  required List<DrawPoint> points,
  required ArrowType arrowType,
  required double strokeWidth,
}) => ArrowGeometry.calculatePathBounds(
  worldPoints: points,
  arrowType: arrowType,
);

DrawPoint _resolveArrowSegmentPosition({
  required DrawPoint segmentStart,
  required DrawPoint currentPosition,
}) =>
    // For all arrow types, allow free positioning.
    currentPosition;

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

List<DrawPoint> _resolveArrowWorldPoints({
  required DrawRect rect,
  required List<DrawPoint> normalizedPoints,
}) {
  final resolved = ArrowGeometry.resolveWorldPoints(
    rect: rect,
    normalizedPoints: normalizedPoints,
  );
  return resolved
      .map((point) => DrawPoint(x: point.dx, y: point.dy))
      .toList(growable: false);
}

_PointSnapResult _snapCreatePoint({
  required DrawState state,
  required DrawConfig config,
  required DrawPoint position,
  required SnappingMode snappingMode,
  _ArrowCreationSessionData? sessionData,
}) {
  if (snappingMode != SnappingMode.object) {
    return _PointSnapResult(position: position);
  }
  final snapConfig = config.snap;
  if (!snapConfig.enablePointSnaps && !snapConfig.enableGapSnaps) {
    return _PointSnapResult(position: position);
  }
  final referenceElements = _resolveReferenceElements(
    state,
    sessionData: sessionData,
  );
  if (referenceElements.isEmpty) {
    return _PointSnapResult(position: position);
  }
  final zoom = state.application.view.camera.zoom;
  final effectiveZoom = zoom == 0 ? 1.0 : zoom;
  final snapDistance = snapConfig.distance / effectiveZoom;
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
  required ArrowheadStyle arrowheadStyle,
  ArrowBinding? preferredBinding,
  DrawPoint? referencePoint,
  ArrowBindingTargetCache? targetCache,
  double targetCacheThresholdFactor = _defaultBindingCacheTargetThresholdFactor,
  double emptyCacheThresholdFactor = _defaultBindingCacheEmptyThresholdFactor,
}) {
  final snapConfig = config.snap;
  final bindingEnabled = ArrowBindingSnapper.shouldAttemptBinding(
    snapConfig: snapConfig,
    snappingMode: snappingMode,
  );
  if (!bindingEnabled) {
    targetCache?.reset();
    return _BindingSnapResult(position: position);
  }
  final bindingDistance = ArrowBindingSnapper.resolveBindingDistance(
    state: state,
    snapConfig: snapConfig,
  );
  if (bindingDistance <= 0) {
    targetCache?.reset();
    return _BindingSnapResult(position: position);
  }

  final preferredDirect =
      ArrowBindingSnapper.resolvePreferredBindingCandidateDirect(
        state: state,
        worldPoint: position,
        arrowType: arrowType,
        arrowheadStyle: arrowheadStyle,
        snapDistance: bindingDistance,
        allowNewBinding: true,
        preferredBinding: preferredBinding,
        referencePoint: referencePoint,
      );
  if (preferredDirect != null) {
    return _BindingSnapResult(
      position: preferredDirect.snapPoint,
      binding: preferredDirect.binding,
    );
  }

  if (!state.domain.document.hasArrowBindableElements) {
    targetCache?.reset();
    return _BindingSnapResult(position: position);
  }

  final bindingSearchDistance = ArrowBindingUtils.resolveBindingSearchDistance(
    bindingDistance,
  );
  final targets = ArrowBindingSnapper.resolveBindingTargetsCached(
    state: state,
    position: position,
    distance: bindingSearchDistance,
    cache: targetCache,
    targetCacheThresholdFactor: targetCacheThresholdFactor,
    emptyCacheThresholdFactor: emptyCacheThresholdFactor,
  );
  if (targets.isEmpty) {
    return _BindingSnapResult(position: position);
  }

  final preferredCandidate =
      ArrowBindingSnapper.resolvePreferredBindingCandidate(
        worldPoint: position,
        targets: targets,
        arrowType: arrowType,
        arrowheadStyle: arrowheadStyle,
        snapDistance: bindingDistance,
        allowNewBinding: true,
        preferredBinding: preferredBinding,
        referencePoint: referencePoint,
      );
  if (preferredCandidate != null) {
    return _BindingSnapResult(
      position: preferredCandidate.snapPoint,
      binding: preferredCandidate.binding,
    );
  }

  final candidate = arrowType == ArrowType.elbow
      ? ArrowBindingUtils.resolveElbowBindingCandidate(
          worldPoint: position,
          targets: targets,
          snapDistance: bindingDistance,
          preferredBinding: preferredBinding,
          hasArrowhead: arrowheadStyle != ArrowheadStyle.none,
        )
      : ArrowBindingUtils.resolveBindingCandidate(
          worldPoint: position,
          targets: targets,
          snapDistance: bindingDistance,
          preferredBinding: preferredBinding,
          referencePoint: referencePoint,
        );
  if (candidate == null) {
    return _BindingSnapResult(position: position);
  }
  return _BindingSnapResult(
    position: candidate.snapPoint,
    binding: candidate.binding,
  );
}

_BindingSnapResult _resolveStartBindingPoint({
  required DrawState state,
  required DrawConfig config,
  required DrawPoint startPosition,
  required SnappingMode snappingMode,
  required ArrowType arrowType,
  required ArrowheadStyle arrowheadStyle,
  required ArrowBinding? preferredBinding,
  required DrawPoint referencePoint,
  required _ArrowCreationSessionData sessionData,
  double targetCacheThresholdFactor = _defaultBindingCacheTargetThresholdFactor,
  double emptyCacheThresholdFactor = _defaultBindingCacheEmptyThresholdFactor,
}) {
  final snapConfig = config.snap;
  final bindingEnabled = ArrowBindingSnapper.shouldAttemptBinding(
    snapConfig: snapConfig,
    snappingMode: snappingMode,
  );
  final bindingDistance = bindingEnabled
      ? ArrowBindingSnapper.resolveBindingDistance(
          state: state,
          snapConfig: snapConfig,
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
  )) {
    final cached = sessionData.resolveCachedStartBinding(
      state: state,
      startPosition: startPosition,
      arrowType: arrowType,
      arrowheadStyle: arrowheadStyle,
      referencePoint: referencePoint,
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
    arrowheadStyle: arrowheadStyle,
    preferredBinding: preferredBinding,
    referencePoint: referencePoint,
    targetCache: sessionData.startTargetCache,
    targetCacheThresholdFactor: targetCacheThresholdFactor,
    emptyCacheThresholdFactor: emptyCacheThresholdFactor,
  );
  sessionData.cacheStartBinding(
    startPosition: startPosition,
    preferredBinding: preferredBinding,
    snappingMode: snappingMode,
    elementsVersion: elementsVersion,
    bindingEnabled: bindingEnabled,
    bindingDistance: bindingDistance,
    result: resolved,
  );
  return resolved;
}

List<ElementState> _resolveReferenceElements(
  DrawState state, {
  _ArrowCreationSessionData? sessionData,
}) {
  final document = state.domain.document;
  if (sessionData != null) {
    return sessionData.resolveReferenceElements(document);
  }
  return document.elements.where((element) => element.opacity > 0).toList();
}

_ArrowCreationSessionData _resolveSessionData(CreationMode mode) {
  if (mode case PointCreationMode(:final sessionData)) {
    if (sessionData is _ArrowCreationSessionData) {
      return sessionData;
    }
  }
  return _ArrowCreationSessionData();
}

class _ArrowCreationSessionData {
  final startTargetCache = ArrowBindingTargetCache();
  final endTargetCache = ArrowBindingTargetCache();

  DrawPoint? _cachedStartPosition;
  ArrowBinding? _cachedStartPreferredBinding;
  ArrowBinding? _cachedStartBinding;
  SnappingMode? _cachedStartSnappingMode;
  bool? _cachedStartBindingEnabled;
  double? _cachedStartBindingDistance;
  var _cachedStartElementsVersion = -1;

  var _referenceElementsVersion = -1;
  List<ElementState> _referenceElements = const [];

  bool canReuseStartBinding({
    required DrawPoint startPosition,
    required ArrowBinding? preferredBinding,
    required SnappingMode snappingMode,
    required int elementsVersion,
    required bool bindingEnabled,
    required double bindingDistance,
  }) =>
      _cachedStartPosition == startPosition &&
      _cachedStartPreferredBinding == preferredBinding &&
      _cachedStartSnappingMode == snappingMode &&
      _cachedStartBindingEnabled == bindingEnabled &&
      _cachedStartBindingDistance == bindingDistance &&
      _cachedStartElementsVersion == elementsVersion;

  _BindingSnapResult? resolveCachedStartBinding({
    required DrawState state,
    required DrawPoint startPosition,
    required ArrowType arrowType,
    required ArrowheadStyle arrowheadStyle,
    required DrawPoint referencePoint,
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
            hasArrowhead: arrowheadStyle != ArrowheadStyle.none,
          )
        : ArrowBindingUtils.resolveBoundPoint(
            binding: cachedBinding,
            target: target,
            referencePoint: referencePoint,
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
    required _BindingSnapResult result,
  }) {
    _cachedStartPosition = startPosition;
    _cachedStartPreferredBinding = preferredBinding;
    _cachedStartBinding = result.binding;
    _cachedStartSnappingMode = snappingMode;
    _cachedStartBindingEnabled = bindingEnabled;
    _cachedStartBindingDistance = bindingDistance;
    _cachedStartElementsVersion = elementsVersion;
  }

  List<ElementState> resolveReferenceElements(DocumentState document) {
    if (_referenceElementsVersion == document.elementsVersion) {
      return _referenceElements;
    }
    _referenceElementsVersion = document.elementsVersion;
    return _referenceElements = document.elements
        .where((element) => element.opacity > 0)
        .toList(growable: false);
  }
}

@immutable
class _LineEndpointResolution {
  const _LineEndpointResolution({
    required this.fixedPoints,
    required this.segmentStart,
    required this.currentPosition,
    required this.startBinding,
  });

  final List<DrawPoint> fixedPoints;
  final DrawPoint segmentStart;
  final DrawPoint currentPosition;
  final ArrowBinding? startBinding;
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
