import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../elements/core/element_data.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../services/grid_snap_service.dart';
import '../../services/object_snap_service.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/snap_guides.dart';
import '../../utils/snapping_mode.dart';
import '../../utils/state_calculator.dart';
import 'creation_strategy.dart';

/// Default creation strategy for rect-based elements (rectangle, text, etc.).
@immutable
class RectCreationStrategy extends CreationStrategy {
  const RectCreationStrategy();

  @override
  CreationUpdateResult start({
    required ElementData data,
    required DrawPoint startPosition,
  }) => CreationUpdateResult(
    data: data,
    rect: DrawRect(
      minX: startPosition.x,
      minY: startPosition.y,
      maxX: startPosition.x,
      maxY: startPosition.y,
    ),
    creationMode: const RectCreationMode(),
  );

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
    final gridConfig = config.grid;
    final snapToGrid = snappingMode == SnappingMode.grid;
    final startPosition = snapToGrid
        ? gridSnapService.snapPoint(
            point: creatingState.startPosition,
            gridSize: gridConfig.size,
          )
        : creatingState.startPosition;
    final snappedCurrent = snapToGrid
        ? gridSnapService.snapPoint(
            point: currentPosition,
            gridSize: gridConfig.size,
          )
        : currentPosition;
    var newRect = StateCalculator.calculateCreateRect(
      startPosition: startPosition,
      currentPosition: snappedCurrent,
      maintainAspectRatio: maintainAspectRatio,
      createFromCenter: createFromCenter,
    );

    var snapGuides = const <SnapGuide>[];
    final snapConfig = config.snap;
    final shouldSnap =
        snappingMode == SnappingMode.object &&
        !createFromCenter &&
        (snapConfig.enablePointSnaps || snapConfig.enableGapSnaps);

    if (shouldSnap) {
      final zoom = state.application.view.camera.zoom;
      final effectiveZoom = zoom == 0 ? 1.0 : zoom;
      final snapDistance = snapConfig.distance / effectiveZoom;
      final direction = _resolveCreateDirection(
        creatingState.startPosition,
        currentPosition,
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

    return CreationUpdateResult(
      data: creatingState.elementData,
      rect: newRect,
      creationMode: creatingState.creationMode,
      snapGuides: snapGuides,
    );
  }

  @override
  CreationFinishResult finish({
    required DrawConfig config,
    required CreatingState creatingState,
  }) {
    final rect = creatingState.currentRect;
    final minSize = config.element.minCreateSize;
    final updatedElement = creatingState.element.copyWith(rect: rect);
    final isValid =
        rect.width >= minSize &&
        rect.height >= minSize &&
        updatedElement.isValidWith(config.element);
    return CreationFinishResult(
      data: creatingState.elementData,
      rect: rect,
      shouldCommit: isValid,
    );
  }
}

enum _CreateAxis { start, end }

@immutable
class _CreateDirection {
  const _CreateDirection({required this.horizontal, required this.vertical});
  final _CreateAxis horizontal;
  final _CreateAxis vertical;
}

_CreateDirection _resolveCreateDirection(DrawPoint start, DrawPoint current) {
  final horizontal = current.x >= start.x ? _CreateAxis.end : _CreateAxis.start;
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
