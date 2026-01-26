import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../elements/core/creation_strategy.dart';
import '../../../elements/core/element_data.dart';
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
import 'arrow_data.dart';
import 'arrow_geometry.dart';

/// Creation strategy for arrow elements (single- and multi-point).
@immutable
class ArrowCreationStrategy extends PointCreationStrategy {
  const ArrowCreationStrategy();

  @override
  CreationUpdateResult start({
    required ElementData data,
    required DrawPoint startPosition,
  }) {
    if (data is! ArrowData) {
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
    return CreationUpdateResult(
      data: updatedData,
      rect: arrowRect,
      creationMode: PointCreationMode(
        fixedPoints: List<DrawPoint>.unmodifiable([startPosition]),
        currentPoint: startPosition,
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
    if (elementData is! ArrowData) {
      return CreationUpdateResult(
        data: elementData,
        rect: creatingState.currentRect,
        creationMode: creatingState.creationMode,
      );
    }

    final gridConfig = config.grid;
    final snapToGrid = snappingMode == SnappingMode.grid;
    final startPosition = snapToGrid
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

    final fixedPoints = creatingState.fixedPoints;
    final segmentStart = fixedPoints.isNotEmpty
        ? fixedPoints.last
        : startPosition;
    adjustedCurrent = _resolveArrowSegmentPosition(
      segmentStart: segmentStart,
      currentPosition: adjustedCurrent,
      arrowType: elementData.arrowType,
    );

    var snapGuides = const <SnapGuide>[];
    final snapResult = _snapCreatePoint(
      state: state,
      config: config,
      position: adjustedCurrent,
      snappingMode: snappingMode,
    );
    adjustedCurrent = snapResult.position;
    snapGuides = snapResult.guides;

    final isPolyline = elementData.arrowType == ArrowType.polyline;
    if (isPolyline && fixedPoints.length >= 2) {
      final handleTolerance = _resolveCreateHandleTolerance(state, config);
      final loopThreshold = handleTolerance * 1.5;
      final loopTarget = fixedPoints.first;
      final isLoopSnap =
          adjustedCurrent.distanceSquared(loopTarget) <=
          loopThreshold * loopThreshold;
      if (isLoopSnap) {
        adjustedCurrent = loopTarget;
        snapGuides = const <SnapGuide>[];
      }
    }

    final allPoints = _appendCurrentPoint(
      fixedPoints: fixedPoints,
      currentPoint: adjustedCurrent,
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
    final updatedData = elementData.copyWith(points: normalizedPoints);

    return CreationUpdateResult(
      data: updatedData,
      rect: arrowRect,
      snapGuides: snapGuides,
      creationMode: PointCreationMode(
        fixedPoints: fixedPoints,
        currentPoint: adjustedCurrent,
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
    if (elementData is! ArrowData) {
      return null;
    }

    final gridConfig = config.grid;
    final snapToGrid = snappingMode == SnappingMode.grid;
    var adjustedPosition = snapToGrid
        ? gridSnapService.snapPoint(
            point: position,
            gridSize: gridConfig.size,
          )
        : position;

    var fixedPoints = creatingState.fixedPoints;
    var segmentStart = fixedPoints.isNotEmpty
        ? fixedPoints.last
        : creatingState.startPosition;
    adjustedPosition = _resolveArrowSegmentPosition(
      segmentStart: segmentStart,
      currentPosition: adjustedPosition,
      arrowType: elementData.arrowType,
    );
    final snapResult = _snapCreatePoint(
      state: state,
      config: config,
      position: adjustedPosition,
      snappingMode: snappingMode,
    );
    adjustedPosition = snapResult.position;
    var snapGuides = snapResult.guides;

    final isPolyline = elementData.arrowType == ArrowType.polyline;
    var isLoopSnap = false;
    if (isPolyline && fixedPoints.length >= 2) {
      final handleTolerance = _resolveCreateHandleTolerance(state, config);
      final loopThreshold = handleTolerance * 1.5;
      final loopTarget = fixedPoints.first;
      isLoopSnap =
          adjustedPosition.distanceSquared(loopTarget) <=
          loopThreshold * loopThreshold;
      if (isLoopSnap) {
        if (creatingState.currentPoint == loopTarget) {
          return null;
        }
        adjustedPosition = loopTarget;
        snapGuides = const <SnapGuide>[];
      } else {
        fixedPoints = _rollbackPolylineFixedPoint(
          fixedPoints: fixedPoints,
          currentPoint: adjustedPosition,
          tolerance: handleTolerance,
        );
        segmentStart = fixedPoints.isNotEmpty
            ? fixedPoints.last
            : creatingState.startPosition;
      }
    }

    var updatedFixedPoints = fixedPoints;
    if (!isLoopSnap &&
        (updatedFixedPoints.isEmpty ||
            updatedFixedPoints.last != adjustedPosition)) {
      updatedFixedPoints = List<DrawPoint>.unmodifiable([
        ...updatedFixedPoints,
        adjustedPosition,
      ]);
    }
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
    final updatedData = elementData.copyWith(points: normalizedPoints);

    return CreationUpdateResult(
      data: updatedData,
      rect: arrowRect,
      snapGuides: snapGuides,
      creationMode: PointCreationMode(
        fixedPoints: updatedFixedPoints,
        currentPoint: adjustedPosition,
      ),
    );
  }

  @override
  CreationFinishResult finish({
    required DrawConfig config,
    required CreatingState creatingState,
  }) {
    final data = creatingState.elementData;
    if (data is! ArrowData) {
      return CreationFinishResult(
        data: data,
        rect: creatingState.currentRect,
        shouldCommit: false,
      );
    }

    final minSize = config.element.minCreateSize;
    final finalPoints = creatingState.isPointCreation
        ? _resolveFinalArrowPoints(creatingState)
        : _resolveArrowWorldPoints(
            rect: creatingState.currentRect,
            normalizedPoints: data.points,
          );
    if (finalPoints.length < 2) {
      return CreationFinishResult(
        data: data,
        rect: creatingState.currentRect,
        shouldCommit: false,
      );
    }

    final arrowRect = _calculateArrowRect(
      points: finalPoints,
      arrowType: data.arrowType,
      strokeWidth: data.strokeWidth,
    );
    final normalizedPoints = ArrowGeometry.normalizePoints(
      worldPoints: finalPoints,
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
  required ArrowType arrowType,
}) =>
    // For all arrow types including polyline, allow
    // free positioning of control points
    // The three-segment elbow effect for
    // polylines is applied during rendering
    // in ArrowGeometry.expandPolylinePoints(), not
    // during point creation
    currentPosition;

double _resolveCreateHandleTolerance(DrawState state, DrawConfig config) {
  final zoom = state.application.view.camera.zoom;
  final effectiveZoom = zoom == 0 ? 1.0 : zoom;
  return config.selection.interaction.handleTolerance / effectiveZoom;
}

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

// Roll back the last fixed point when the end point folds a straight segment.
List<DrawPoint> _rollbackPolylineFixedPoint({
  required List<DrawPoint> fixedPoints,
  required DrawPoint currentPoint,
  required double tolerance,
}) {
  if (fixedPoints.length < 2) {
    return fixedPoints;
  }
  final prev = fixedPoints[fixedPoints.length - 2];
  final last = fixedPoints[fixedPoints.length - 1];
  final toleranceSq = tolerance * tolerance;
  if (last.distanceSquared(currentPoint) <= toleranceSq) {
    return fixedPoints;
  }
  if (prev.distanceSquared(last) <= toleranceSq) {
    return List<DrawPoint>.unmodifiable(
      fixedPoints.sublist(0, fixedPoints.length - 1),
    );
  }
  if (_areCollinear(prev, last, currentPoint, tolerance) &&
      (_isBetween(prev, last, currentPoint, tolerance) ||
          _isBetween(prev, currentPoint, last, tolerance))) {
    return List<DrawPoint>.unmodifiable(
      fixedPoints.sublist(0, fixedPoints.length - 1),
    );
  }
  return fixedPoints;
}

bool _areCollinear(DrawPoint a, DrawPoint b, DrawPoint c, double tolerance) {
  final acx = c.x - a.x;
  final acy = c.y - a.y;
  final lengthSq = acx * acx + acy * acy;
  if (lengthSq <= tolerance * tolerance) {
    return true;
  }
  final abx = b.x - a.x;
  final aby = b.y - a.y;
  final cross = abx * acy - aby * acx;
  return cross * cross <= tolerance * tolerance * lengthSq;
}

bool _isBetween(DrawPoint a, DrawPoint b, DrawPoint c, double tolerance) {
  final minX = math.min(a.x, c.x) - tolerance;
  final maxX = math.max(a.x, c.x) + tolerance;
  final minY = math.min(a.y, c.y) - tolerance;
  final maxY = math.max(a.y, c.y) + tolerance;
  return b.x >= minX && b.x <= maxX && b.y >= minY && b.y <= maxY;
}

List<DrawPoint> _resolveFinalArrowPoints(CreatingState interaction) {
  final points = <DrawPoint>[...interaction.fixedPoints];
  final currentPoint = interaction.currentPoint;
  if (currentPoint != null && (points.isEmpty || points.last != currentPoint)) {
    points.add(currentPoint);
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
}) {
  if (snappingMode != SnappingMode.object) {
    return _PointSnapResult(position: position);
  }
  final snapConfig = config.snap;
  if (!snapConfig.enablePointSnaps && !snapConfig.enableGapSnaps) {
    return _PointSnapResult(position: position);
  }
  final referenceElements = _resolveReferenceElements(state);
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

List<ElementState> _resolveReferenceElements(DrawState state) => state
    .domain
    .document
    .elements
    .where((element) => element.opacity > 0)
    .toList();

@immutable
class _PointSnapResult {
  const _PointSnapResult({
    required this.position,
    this.guides = const <SnapGuide>[],
  });

  final DrawPoint position;
  final List<SnapGuide> guides;
}
