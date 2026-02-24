import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../models/draw_state.dart';
import '../../models/interaction_state.dart';
import '../../services/grid_snap_service.dart';
import '../../services/text/text_metrics_service.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/snap_guides.dart';
import '../../utils/snapping_mode.dart';
import '../core/element_data.dart';

/// Result for creation start/update phases.
@immutable
class CreationUpdateResult {
  const CreationUpdateResult({
    required this.data,
    required this.rect,
    required this.creationMode,
    this.snapGuides = const [],
  });
  final ElementData data;
  final DrawRect rect;
  final CreationMode creationMode;
  final List<SnapGuide> snapGuides;
}

/// Result for creation finish.
@immutable
class CreationFinishResult {
  const CreationFinishResult({
    required this.data,
    required this.rect,
    required this.shouldCommit,
  });
  final ElementData data;
  final DrawRect rect;
  final bool shouldCommit;
}

/// Strategy for element creation.
@immutable
abstract class CreationStrategy {
  const CreationStrategy();

  CreationUpdateResult start({
    required ElementData data,
    required DrawPoint startPosition,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  });

  CreationUpdateResult update({
    required DrawState state,
    required DrawConfig config,
    required CreatingState creatingState,
    required DrawPoint currentPosition,
    required bool maintainAspectRatio,
    required bool createFromCenter,
    required SnappingMode snappingMode,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  });

  /// Applies a batch of pointer positions to the current creation session.
  ///
  /// The default implementation falls back to repeatedly calling [update].
  /// Strategies with high-frequency workflows (for example free draw) can
  /// override this to process a whole sample batch with less overhead.
  CreationUpdateResult updateBatch({
    required DrawState state,
    required DrawConfig config,
    required CreatingState creatingState,
    required List<DrawPoint> positions,
    required bool maintainAspectRatio,
    required bool createFromCenter,
    required SnappingMode snappingMode,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    if (positions.isEmpty) {
      return CreationUpdateResult(
        data: creatingState.elementData,
        rect: creatingState.currentRect,
        creationMode: creatingState.creationMode,
        snapGuides: creatingState.snapGuides,
      );
    }

    var working = creatingState;
    for (final position in positions) {
      final updateResult = update(
        state: state,
        config: config,
        creatingState: working,
        currentPosition: position,
        maintainAspectRatio: maintainAspectRatio,
        createFromCenter: createFromCenter,
        snappingMode: snappingMode,
        textMetricsService: textMetricsService,
      );

      final baseElement = working.element;
      final updatedElement = updateResult.data == working.element.data
          ? baseElement
          : baseElement.copyWith(data: updateResult.data);

      working = working.copyWith(
        element: updatedElement,
        currentRect: updateResult.rect,
        snapGuides: updateResult.snapGuides,
        creationMode: updateResult.creationMode,
      );
    }

    return CreationUpdateResult(
      data: working.element.data,
      rect: working.currentRect,
      creationMode: working.creationMode,
      snapGuides: working.snapGuides,
    );
  }

  CreationUpdateResult? addPoint({
    required DrawState state,
    required DrawConfig config,
    required CreatingState creatingState,
    required DrawPoint position,
    required SnappingMode snappingMode,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) => null;

  CreationFinishResult finish({
    required DrawConfig config,
    required CreatingState creatingState,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  });
}

/// Creation strategy that supports point-based workflows.
@immutable
abstract class PointCreationStrategy extends CreationStrategy {
  const PointCreationStrategy();
}

/// Returns whether the creation result should be committed to the document.
///
/// The element must satisfy both minimum size and element-level validity
/// constraints from [config].
bool shouldCommitCreationResult({
  required DrawConfig config,
  required CreatingState creatingState,
  DrawRect? rect,
}) {
  final resolvedRect = rect ?? creatingState.currentRect;
  final minSize = config.element.minCreateSize;
  return resolvedRect.width >= minSize &&
      resolvedRect.height >= minSize &&
      creatingState.element
          .copyWith(rect: resolvedRect)
          .isValidWith(config.element);
}

/// Builds a standard finish result using the current creation rect.
CreationFinishResult finishCreationWithCurrentRect({
  required DrawConfig config,
  required CreatingState creatingState,
}) {
  final rect = creatingState.currentRect;
  return CreationFinishResult(
    data: creatingState.elementData,
    rect: rect,
    shouldCommit: shouldCommitCreationResult(
      config: config,
      creatingState: creatingState,
      rect: rect,
    ),
  );
}

/// Snaps [point] to the creation grid when grid snapping is active.
DrawPoint snapCreationPoint({
  required DrawPoint point,
  required DrawConfig config,
  required SnappingMode snappingMode,
}) {
  if (snappingMode != SnappingMode.grid) {
    return point;
  }
  return gridSnapService.snapPoint(point: point, gridSize: config.grid.size);
}
