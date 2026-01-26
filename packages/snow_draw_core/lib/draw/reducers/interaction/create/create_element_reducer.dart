import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../config/draw_config.dart';
import '../../../core/draw_context.dart';
import '../../../elements/core/element_data.dart';
import '../../../elements/core/element_style_configurable_data.dart';
import '../../../elements/core/element_type_id.dart';
import '../../../elements/types/arrow/arrow_data.dart';
import '../../../elements/types/arrow/arrow_geometry.dart';
import '../../../elements/types/rectangle/rectangle_data.dart';
import '../../../elements/types/text/text_data.dart';
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
import '../../../utils/state_calculator.dart';

/// Reducer for element creation.
///
/// Handles: CreateElement, UpdateCreatingElement, FinishCreateElement,
/// CancelCreateElement.
@immutable
class CreateElementReducer {
  const CreateElementReducer();

  /// Try to handle element creation actions.
  ///
  /// Returns null if the action is not a creation operation.
  DrawState? reduce(DrawState state, DrawAction action, DrawContext context) =>
      switch (action) {
        final CreateElement a => _startCreateElement(state, a, context),
        final UpdateCreatingElement a => _updateCreatingElement(
          state,
          a,
          context,
        ),
        final AddArrowPoint a => _addArrowPoint(state, a, context),
        FinishCreateElement _ => _finishCreateElement(state, context),
        CancelCreateElement _ => _cancelCreateElement(state),
        _ => null,
      };

  DrawState _startCreateElement(
    DrawState state,
    CreateElement action,
    DrawContext context,
  ) {
    final config = context.config;
    final definition = context.elementRegistry.getDefinition(action.typeId);
    if (definition == null) {
      throw StateError('Element type "${action.typeId}" is not registered');
    }

    final styleDefaults = _resolveStyleDefaults(config, action.typeId);
    var data = action.initialData ?? definition.createDefaultData();
    if (action.initialData == null && data is ElementStyleConfigurableData) {
      data = (data as ElementStyleConfigurableData).withElementStyle(
        styleDefaults,
      );
    }

    final elementId = context.idGenerator();
    final gridConfig = config.grid;
    final snappingMode = resolveEffectiveSnappingModeForConfig(
      config: config,
      ctrlPressed: action.snapOverride,
    );
    final snapToGrid = snappingMode == SnappingMode.grid;
    final startPosition = snapToGrid
        ? gridSnapService.snapPoint(
            point: action.position,
            gridSize: gridConfig.size,
          )
        : action.position;
    final initialRect = DrawRect(
      minX: startPosition.x,
      minY: startPosition.y,
      maxX: startPosition.x,
      maxY: startPosition.y,
    );
    if (data is ArrowData) {
      final arrowRect = _calculateArrowRect(
        points: [startPosition, startPosition],
        arrowType: data.arrowType,
        strokeWidth: data.strokeWidth,
      );
      final normalizedPoints = ArrowGeometry.normalizePoints(
        worldPoints: [startPosition, startPosition],
        rect: arrowRect,
      );
      data = data.copyWith(points: normalizedPoints);
    }

    final newElement = ElementState(
      id: elementId,
      rect: initialRect,
      rotation: 0,
      opacity: styleDefaults.opacity,
      zIndex: state.domain.document.elements.length,
      data: data,
    );

    final nextDomain = state.domain.copyWith(
      selection: state.domain.selection.cleared(),
    );
    final nextApplication = data is ArrowData
        ? state.application.copyWith(
            interaction: CreatingState(
              element: newElement,
              startPosition: startPosition,
              currentRect: initialRect,
              creationMode: PointCreationMode(
                fixedPoints: List<DrawPoint>.unmodifiable([startPosition]),
                currentPoint: startPosition,
              ),
            ),
          )
        : state.application.copyWith(
            interaction: CreatingState(
              element: newElement,
              startPosition: startPosition,
              currentRect: initialRect,
            ),
          );
    return state.copyWith(domain: nextDomain, application: nextApplication);
  }

  ElementStyleConfig _resolveStyleDefaults(
    DrawConfig config,
    ElementTypeId<ElementData> typeId,
  ) {
    if (typeId == RectangleData.typeIdToken) {
      return config.rectangleStyle;
    }
    if (typeId == ArrowData.typeIdToken) {
      return config.arrowStyle;
    }
    if (typeId == TextData.typeIdToken) {
      return config.textStyle;
    }
    return config.elementStyle;
  }

  DrawState _updateCreatingElement(
    DrawState state,
    UpdateCreatingElement action,
    DrawContext context,
  ) {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState) {
      return state;
    }

    final gridConfig = context.config.grid;
    final snappingMode = resolveEffectiveSnappingModeForConfig(
      config: context.config,
      ctrlPressed: action.snapOverride,
    );
    final snapToGrid = snappingMode == SnappingMode.grid;
    final startPosition = snapToGrid
        ? gridSnapService.snapPoint(
            point: interaction.startPosition,
            gridSize: gridConfig.size,
          )
        : interaction.startPosition;
    final currentPosition = snapToGrid
        ? gridSnapService.snapPoint(
            point: action.currentPosition,
            gridSize: gridConfig.size,
          )
        : action.currentPosition;
    var newRect = StateCalculator.calculateCreateRect(
      startPosition: startPosition,
      currentPosition: currentPosition,
      maintainAspectRatio: action.maintainAspectRatio,
      createFromCenter: action.createFromCenter,
    );

    final elementData = interaction.element.data;
    if (elementData is ArrowData) {
      // Use unified CreatingState with PointCreationMode
      final fixedPoints = interaction.fixedPoints;
      final segmentStart = fixedPoints.isNotEmpty
          ? fixedPoints.last
          : startPosition;
      var adjustedCurrent = _resolveArrowSegmentPosition(
        segmentStart: segmentStart,
        currentPosition: currentPosition,
        arrowType: elementData.arrowType,
      );
      var snapGuides = const <SnapGuide>[];
      final snapResult = _snapCreatePoint(
        state: state,
        config: context.config,
        position: adjustedCurrent,
        snappingMode: snappingMode,
      );
      adjustedCurrent = snapResult.position;
      snapGuides = snapResult.guides;
      final isPolyline = elementData.arrowType == ArrowType.polyline;
      if (isPolyline && fixedPoints.length >= 2) {
        final handleTolerance = _resolveCreateHandleTolerance(
          state,
          context.config,
        );
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
      final updatedElement = interaction.element.copyWith(data: updatedData);
      final nextInteraction = interaction.copyWith(
        element: updatedElement,
        currentRect: arrowRect,
        snapGuides: snapGuides,
        creationMode: PointCreationMode(
          fixedPoints: fixedPoints,
          currentPoint: adjustedCurrent,
        ),
      );
      return state.copyWith(
        application: state.application.copyWith(interaction: nextInteraction),
      );
    }

    var snapGuides = const <SnapGuide>[];
    final snapConfig = context.config.snap;
    final shouldSnap =
        snappingMode == SnappingMode.object &&
        !action.createFromCenter &&
        (snapConfig.enablePointSnaps || snapConfig.enableGapSnaps);

    if (shouldSnap) {
      final zoom = state.application.view.camera.zoom;
      final effectiveZoom = zoom == 0 ? 1.0 : zoom;
      final snapDistance = snapConfig.distance / effectiveZoom;
      final direction = _resolveCreateDirection(
        interaction.startPosition,
        action.currentPosition,
      );
      final anchorsX = _createAnchorsX(direction);
      final anchorsY = _createAnchorsY(direction);
      final referenceElements = _resolveReferenceElements(state);
      final result = objectSnapService.snapRect(
        targetRect: newRect,
        referenceElements: referenceElements,
        snapDistance: snapDistance,
        targetAnchorsX: anchorsX,
        targetAnchorsY: anchorsY,
        enablePointSnaps: snapConfig.enablePointSnaps,
        enableGapSnaps: snapConfig.enableGapSnaps,
      );
      if (result.hasSnap) {
        final moveMinX = anchorsX.contains(SnapAxisAnchor.start);
        final moveMaxX = anchorsX.contains(SnapAxisAnchor.end);
        final moveMinY = anchorsY.contains(SnapAxisAnchor.start);
        final moveMaxY = anchorsY.contains(SnapAxisAnchor.end);
        newRect = DrawRect(
          minX: newRect.minX + (moveMinX ? result.dx : 0),
          minY: newRect.minY + (moveMinY ? result.dy : 0),
          maxX: newRect.maxX + (moveMaxX ? result.dx : 0),
          maxY: newRect.maxY + (moveMaxY ? result.dy : 0),
        );
      }
      if (snapConfig.showGuides) {
        snapGuides = result.guides;
      }
    }
    return state.copyWith(
      application: state.application.copyWith(
        interaction: interaction.copyWith(
          currentRect: newRect,
          snapGuides: snapGuides,
        ),
      ),
    );
  }

  _CreateDirection _resolveCreateDirection(DrawPoint start, DrawPoint current) {
    final horizontal = current.x >= start.x
        ? _CreateAxis.end
        : _CreateAxis.start;
    final vertical = current.y >= start.y ? _CreateAxis.end : _CreateAxis.start;
    return _CreateDirection(horizontal: horizontal, vertical: vertical);
  }

  List<SnapAxisAnchor> _createAnchorsX(_CreateDirection direction) => [
    if (direction.horizontal == _CreateAxis.start)
      SnapAxisAnchor.start
    else
      SnapAxisAnchor.end,
  ];

  List<SnapAxisAnchor> _createAnchorsY(_CreateDirection direction) => [
    if (direction.vertical == _CreateAxis.start)
      SnapAxisAnchor.start
    else
      SnapAxisAnchor.end,
  ];

  List<ElementState> _resolveReferenceElements(DrawState state) => state
      .domain
      .document
      .elements
      .where((element) => element.opacity > 0)
      .toList();

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

  DrawState _finishCreateElement(DrawState state, DrawContext context) {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState) {
      return state.copyWith(application: state.application.toIdle());
    }

    var updatedElement = interaction.element.copyWith(
      rect: interaction.currentRect,
      zIndex: state.domain.document.elements.length,
    );
    final minSize = context.config.element.minCreateSize;

    final data = updatedElement.data;
    if (data is ArrowData) {
      final finalPoints = interaction.isPointCreation
          ? _resolveFinalArrowPoints(interaction)
          : _resolveArrowWorldPoints(
              rect: updatedElement.rect,
              normalizedPoints: data.points,
            );
      if (finalPoints.length < 2) {
        return _cancelCreateElement(state);
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
      updatedElement = updatedElement.copyWith(
        rect: arrowRect,
        data: data.copyWith(points: normalizedPoints),
      );
      final points = ArrowGeometry.resolveWorldPoints(
        rect: updatedElement.rect,
        normalizedPoints: (updatedElement.data as ArrowData).points,
      );
      final length = ArrowGeometry.calculateShaftLength(
        points: points,
        arrowType: (updatedElement.data as ArrowData).arrowType,
      );
      if (!length.isFinite || length < minSize) {
        return _cancelCreateElement(state);
      }
    } else if (updatedElement.rect.width < minSize ||
        updatedElement.rect.height < minSize ||
        !updatedElement.isValidWith(context.config.element)) {
      return _cancelCreateElement(state);
    }

    final newElements = [...state.domain.document.elements, updatedElement];

    final nextState = state.copyWith(
      domain: state.domain.copyWith(
        document: state.domain.document.copyWith(elements: newElements),
      ),
      application: state.application.toIdle(),
    );
    nextState.domain.document.warmCaches();
    return nextState;
  }

  DrawState _cancelCreateElement(DrawState state) {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState) {
      return state.copyWith(application: state.application.toIdle());
    }

    final nextDomain = state.domain.copyWith(
      selection: state.domain.selection.cleared(),
    );
    final nextApplication = state.application.copyWith(
      interaction: const IdleState(),
    );
    return state.copyWith(domain: nextDomain, application: nextApplication);
  }

  DrawState _addArrowPoint(
    DrawState state,
    AddArrowPoint action,
    DrawContext context,
  ) {
    final interaction = state.application.interaction;
    if (interaction is! CreatingState || !interaction.isPointCreation) {
      return state;
    }
    final elementData = interaction.element.data;
    if (elementData is! ArrowData) {
      return state;
    }

    final gridConfig = context.config.grid;
    final snappingMode = resolveEffectiveSnappingModeForConfig(
      config: context.config,
      ctrlPressed: action.snapOverride,
    );
    final snapToGrid = snappingMode == SnappingMode.grid;
    var position = snapToGrid
        ? gridSnapService.snapPoint(
            point: action.position,
            gridSize: gridConfig.size,
          )
        : action.position;

    var fixedPoints = interaction.fixedPoints;
    var segmentStart = fixedPoints.isNotEmpty
        ? fixedPoints.last
        : interaction.startPosition;
    position = _resolveArrowSegmentPosition(
      segmentStart: segmentStart,
      currentPosition: position,
      arrowType: elementData.arrowType,
    );
    final snapResult = _snapCreatePoint(
      state: state,
      config: context.config,
      position: position,
      snappingMode: snappingMode,
    );
    position = snapResult.position;
    var snapGuides = snapResult.guides;

    final isPolyline = elementData.arrowType == ArrowType.polyline;
    var isLoopSnap = false;
    if (isPolyline && fixedPoints.length >= 2) {
      final handleTolerance = _resolveCreateHandleTolerance(
        state,
        context.config,
      );
      final loopThreshold = handleTolerance * 1.5;
      final loopTarget = fixedPoints.first;
      isLoopSnap =
          position.distanceSquared(loopTarget) <= loopThreshold * loopThreshold;
      if (isLoopSnap) {
        if (interaction.currentPoint == loopTarget) {
          return state;
        }
        position = loopTarget;
        snapGuides = const <SnapGuide>[];
      } else {
        fixedPoints = _rollbackPolylineFixedPoint(
          fixedPoints: fixedPoints,
          currentPoint: position,
          tolerance: handleTolerance,
        );
        segmentStart = fixedPoints.isNotEmpty
            ? fixedPoints.last
            : interaction.startPosition;
      }
    }

    var updatedFixedPoints = fixedPoints;
    if (!isLoopSnap &&
        (updatedFixedPoints.isEmpty || updatedFixedPoints.last != position)) {
      updatedFixedPoints = List<DrawPoint>.unmodifiable([
        ...updatedFixedPoints,
        position,
      ]);
    }
    final allPoints = _appendCurrentPoint(
      fixedPoints: updatedFixedPoints,
      currentPoint: position,
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
    final updatedElement = interaction.element.copyWith(data: updatedData);
    final nextInteraction = interaction.copyWith(
      element: updatedElement,
      currentRect: arrowRect,
      snapGuides: snapGuides,
      creationMode: PointCreationMode(
        fixedPoints: updatedFixedPoints,
        currentPoint: position,
      ),
    );
    return state.copyWith(
      application: state.application.copyWith(interaction: nextInteraction),
    );
  }
}

enum _CreateAxis { start, end }

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

@immutable
class _PointSnapResult {
  const _PointSnapResult({
    required this.position,
    this.guides = const <SnapGuide>[],
  });

  final DrawPoint position;
  final List<SnapGuide> guides;
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

@immutable
class _CreateDirection {
  const _CreateDirection({required this.horizontal, required this.vertical});
  final _CreateAxis horizontal;
  final _CreateAxis vertical;
}
