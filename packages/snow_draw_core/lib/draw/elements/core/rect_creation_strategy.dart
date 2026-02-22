import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../elements/core/element_data.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../services/grid_snap_service.dart';
import '../../services/object_snap_service.dart';
import '../../services/text/text_metrics_service.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/snap_guides.dart';
import '../../utils/snapping_mode.dart';
import '../../utils/state_calculator.dart';
import 'creation_strategy.dart';

const _startAnchors = <SnapAxisAnchor>[SnapAxisAnchor.start];
const _endAnchors = <SnapAxisAnchor>[SnapAxisAnchor.end];

/// Default creation strategy for rect-based elements (rectangle, text, etc.).
@immutable
class RectCreationStrategy extends CreationStrategy {
  const RectCreationStrategy();

  @override
  CreationUpdateResult start({
    required ElementData data,
    required DrawPoint startPosition,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) => CreationUpdateResult(
    data: data,
    rect: DrawRect.fromPoint(startPosition),
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
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    final snapToGrid = snappingMode == SnappingMode.grid;
    final gridSize = config.grid.size;
    final startPosition = snapToGrid
        ? gridSnapService.snapPoint(
            point: creatingState.startPosition,
            gridSize: gridSize,
          )
        : creatingState.startPosition;
    final current = snapToGrid
        ? gridSnapService.snapPoint(point: currentPosition, gridSize: gridSize)
        : currentPosition;
    var rect = StateCalculator.calculateCreateRect(
      startPosition: startPosition,
      currentPosition: current,
      maintainAspectRatio: maintainAspectRatio,
      createFromCenter: createFromCenter,
    );

    final snapConfig = config.snap;
    final shouldObjectSnap =
        snappingMode == SnappingMode.object &&
        !createFromCenter &&
        (snapConfig.enablePointSnaps || snapConfig.enableGapSnaps);
    if (!shouldObjectSnap) {
      return CreationUpdateResult(
        data: creatingState.elementData,
        rect: rect,
        creationMode: creatingState.creationMode,
      );
    }

    final zoom = state.application.view.camera.zoom;
    final effectiveZoom = zoom == 0 ? 1.0 : zoom;
    final snapDistance = snapConfig.distance / effectiveZoom;
    final cachedMode = _resolveCachedSnapReferences(
      state: state,
      creationMode: creatingState.creationMode,
    );
    final moveMinX = currentPosition.x < creatingState.startPosition.x;
    final moveMinY = currentPosition.y < creatingState.startPosition.y;
    final result = objectSnapService.snapRect(
      targetRect: rect,
      referenceElements: cachedMode.referenceElements,
      referenceAabbs: cachedMode.referenceAabbs,
      snapDistance: snapDistance,
      targetAnchorsX: moveMinX ? _startAnchors : _endAnchors,
      targetAnchorsY: moveMinY ? _startAnchors : _endAnchors,
      enablePointSnaps: snapConfig.enablePointSnaps,
      enableGapSnaps: snapConfig.enableGapSnaps,
    );
    if (result.hasSnap) {
      rect = DrawRect(
        minX: rect.minX + (moveMinX ? result.dx : 0),
        minY: rect.minY + (moveMinY ? result.dy : 0),
        maxX: rect.maxX + (moveMinX ? 0 : result.dx),
        maxY: rect.maxY + (moveMinY ? 0 : result.dy),
      );
    }

    return CreationUpdateResult(
      data: creatingState.elementData,
      rect: rect,
      creationMode: cachedMode,
      snapGuides: snapConfig.showGuides ? result.guides : const <SnapGuide>[],
    );
  }

  @override
  CreationFinishResult finish({
    required DrawConfig config,
    required CreatingState creatingState,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    final rect = creatingState.currentRect;
    final minSize = config.element.minCreateSize;
    final shouldCommit =
        rect.width >= minSize &&
        rect.height >= minSize &&
        creatingState.element.copyWith(rect: rect).isValidWith(config.element);
    return CreationFinishResult(
      data: creatingState.elementData,
      rect: rect,
      shouldCommit: shouldCommit,
    );
  }
}

@immutable
class _CachedRectCreationMode extends CreationMode {
  const _CachedRectCreationMode({
    required this.referenceElements,
    required this.referenceAabbs,
    required this.elementsVersion,
  });

  final List<ElementState> referenceElements;
  final List<DrawRect> referenceAabbs;
  final int elementsVersion;
}

_CachedRectCreationMode _resolveCachedSnapReferences({
  required DrawState state,
  required CreationMode creationMode,
}) {
  final elementsVersion = state.domain.document.elementsVersion;
  if (creationMode is _CachedRectCreationMode &&
      creationMode.elementsVersion == elementsVersion) {
    return creationMode;
  }

  final referenceElements = List<ElementState>.unmodifiable(
    _resolveReferenceElements(state),
  );
  final referenceAabbs = ObjectSnapService.buildReferenceAabbs(
    referenceElements,
  );
  return _CachedRectCreationMode(
    referenceElements: referenceElements,
    referenceAabbs: referenceAabbs,
    elementsVersion: elementsVersion,
  );
}

List<ElementState> _resolveReferenceElements(DrawState state) => [
  for (final element in state.domain.document.elements)
    if (element.opacity > 0) element,
];
