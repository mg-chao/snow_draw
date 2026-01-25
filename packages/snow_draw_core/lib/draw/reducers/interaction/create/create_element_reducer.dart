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
      final arrowRect = _rectFromPoints(startPosition, startPosition);
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
    final nextApplication =
        data is ArrowData
            ? state.application.copyWith(
              interaction: ArrowCreatingState(
                element: newElement,
                startPosition: startPosition,
                currentRect: initialRect,
                fixedPoints: List<DrawPoint>.unmodifiable([startPosition]),
                currentPoint: startPosition,
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
      final fixedPoints =
          interaction is ArrowCreatingState
              ? interaction.fixedPoints
              : [startPosition];
      final segmentStart = fixedPoints.isNotEmpty
          ? fixedPoints.last
          : startPosition;
      final adjustedCurrent = _resolveArrowSegmentPosition(
        segmentStart: segmentStart,
        currentPosition: currentPosition,
        arrowType: elementData.arrowType,
      );
      final allPoints = <DrawPoint>[...fixedPoints, adjustedCurrent];
      final arrowRect = _rectFromPointsList(allPoints);
      final normalizedPoints = ArrowGeometry.normalizePoints(
        worldPoints: allPoints,
        rect: arrowRect,
      );
      final updatedData = elementData.copyWith(points: normalizedPoints);
      final updatedElement = interaction.element.copyWith(data: updatedData);
      final nextInteraction =
          interaction is ArrowCreatingState
              ? interaction.copyWith(
                element: updatedElement,
                currentRect: arrowRect,
                snapGuides: const [],
                currentPoint: adjustedCurrent,
              )
              : interaction.copyWith(
                element: updatedElement,
                currentRect: arrowRect,
                snapGuides: const [],
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

  _CreateDirection _resolveCreateDirection(
    DrawPoint start,
    DrawPoint current,
  ) {
    final horizontal =
        current.x >= start.x ? _CreateAxis.end : _CreateAxis.start;
    final vertical =
        current.y >= start.y ? _CreateAxis.end : _CreateAxis.start;
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

  List<ElementState> _resolveReferenceElements(DrawState state) =>
      state.domain.document.elements
          .where((element) => element.opacity > 0)
          .toList();

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
      final finalPoints =
          interaction is ArrowCreatingState
              ? _resolveFinalArrowPoints(interaction)
              : _resolveArrowWorldPoints(
                rect: updatedElement.rect,
                normalizedPoints: data.points,
              );
      if (finalPoints.length < 2) {
        return _cancelCreateElement(state);
      }
      final arrowRect = _rectFromPointsList(finalPoints);
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

    final newElements = [
      ...state.domain.document.elements,
      updatedElement,
    ];

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
    if (interaction is! ArrowCreatingState) {
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

    final fixedPoints = interaction.fixedPoints;
    final segmentStart = fixedPoints.isNotEmpty
        ? fixedPoints.last
        : interaction.startPosition;
    position = _resolveArrowSegmentPosition(
      segmentStart: segmentStart,
      currentPosition: position,
      arrowType: elementData.arrowType,
    );

    final updatedFixedPoints = position == segmentStart
        ? fixedPoints
        : List<DrawPoint>.unmodifiable([...fixedPoints, position]);
    final allPoints = <DrawPoint>[
      ...updatedFixedPoints,
      position,
    ];
    final arrowRect = _rectFromPointsList(allPoints);
    final normalizedPoints = ArrowGeometry.normalizePoints(
      worldPoints: allPoints,
      rect: arrowRect,
    );
    final updatedData = elementData.copyWith(points: normalizedPoints);
    final updatedElement = interaction.element.copyWith(data: updatedData);
    final nextInteraction = interaction.copyWith(
      element: updatedElement,
      currentRect: arrowRect,
      fixedPoints: updatedFixedPoints,
      currentPoint: position,
      snapGuides: const [],
    );
    return state.copyWith(
      application: state.application.copyWith(interaction: nextInteraction),
    );
  }
}

enum _CreateAxis { start, end }

DrawRect _rectFromPoints(DrawPoint a, DrawPoint b) {
  final minX = math.min(a.x, b.x);
  final maxX = math.max(a.x, b.x);
  final minY = math.min(a.y, b.y);
  final maxY = math.max(a.y, b.y);
  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

DrawPoint _resolveArrowSegmentPosition({
  required DrawPoint segmentStart,
  required DrawPoint currentPosition,
  required ArrowType arrowType,
}) {
  if (arrowType != ArrowType.polyline) {
    return currentPosition;
  }

  final dx = currentPosition.x - segmentStart.x;
  final dy = currentPosition.y - segmentStart.y;
  if (dx.abs() >= dy.abs()) {
    return DrawPoint(x: currentPosition.x, y: segmentStart.y);
  }
  return DrawPoint(x: segmentStart.x, y: currentPosition.y);
}

DrawRect _rectFromPointsList(List<DrawPoint> points) {
  if (points.isEmpty) {
    return const DrawRect(minX: 0, minY: 0, maxX: 0, maxY: 0);
  }
  var minX = points.first.x;
  var maxX = points.first.x;
  var minY = points.first.y;
  var maxY = points.first.y;
  for (final point in points.skip(1)) {
    if (point.x < minX) {
      minX = point.x;
    }
    if (point.x > maxX) {
      maxX = point.x;
    }
    if (point.y < minY) {
      minY = point.y;
    }
    if (point.y > maxY) {
      maxY = point.y;
    }
  }
  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

List<DrawPoint> _resolveFinalArrowPoints(ArrowCreatingState interaction) {
  final points = <DrawPoint>[...interaction.fixedPoints];
  final currentPoint = interaction.currentPoint;
  if (currentPoint != null &&
      (points.isEmpty || points.last != currentPoint)) {
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

@immutable
class _CreateDirection {
  const _CreateDirection({
    required this.horizontal,
    required this.vertical,
  });
  final _CreateAxis horizontal;
  final _CreateAxis vertical;
}
