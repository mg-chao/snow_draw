import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../elements/core/creation_strategy.dart';
import '../../../elements/core/element_data.dart';
import '../../../models/draw_state.dart';
import '../../../models/interaction_state.dart';
import '../../../services/grid_snap_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../utils/snapping_mode.dart';
import '../arrow/arrow_geometry.dart';
import 'free_draw_data.dart';

/// Creation strategy for freehand drawing.
///
/// Applies real-time exponential smoothing and minimum-distance
/// filtering during drawing. Straight-line segments are only
/// created when the user holds Shift.
@immutable
class FreeDrawCreationStrategy extends CreationStrategy {
  const FreeDrawCreationStrategy();

  /// Minimum squared distance between consecutive points (world
  /// units). Points closer than this are discarded to reduce noise.
  static const _minDistanceSq = 2;

  /// Exponential smoothing factor (0 = no smoothing, 1 = no change).
  ///
  /// A lower value lets more of the natural hand movement through,
  /// preventing slow strokes from appearing artificially straight.
  static const _smoothingAlpha = 0.2;

  @override
  CreationUpdateResult start({
    required ElementData data,
    required DrawPoint startPosition,
  }) {
    if (data is! FreeDrawData) {
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

    final points = [startPosition, startPosition];
    final rect = _boundsFromPoints(points);
    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: points,
      rect: rect,
    );

    return CreationUpdateResult(
      data: data.copyWith(points: normalized),
      rect: rect,
      creationMode: const _FreeDrawCreationMode(),
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
    if (state.application.isCreating) {
      // Free draw ignores state-derived modifiers during creation
      // updates.
    }
    if (createFromCenter) {
      // Free draw ignores createFromCenter.
    }

    final elementData = creatingState.elementData;
    if (elementData is! FreeDrawData) {
      return CreationUpdateResult(
        data: elementData,
        rect: creatingState.currentRect,
        creationMode: creatingState.creationMode,
      );
    }

    final currentRect = creatingState.currentRect;
    final adjustedPosition = snappingMode == SnappingMode.grid
        ? gridSnapService.snapPoint(
            point: currentPosition,
            gridSize: config.grid.size,
          )
        : currentPosition;
    final worldPoints = _resolveWorldPoints(
      rect: currentRect,
      normalizedPoints: elementData.points,
    );

    final mode = _resolveFreeDrawMode(creatingState.creationMode);
    List<DrawPoint> nextPoints;
    if (maintainAspectRatio) {
      if (mode.isLineActive) {
        nextPoints = _updateLineSegment(
          worldPoints: worldPoints,
          currentPosition: adjustedPosition,
        );
      } else {
        nextPoints = _startLineSegment(
          worldPoints: worldPoints,
          currentPosition: adjustedPosition,
        );
      }
    } else {
      nextPoints = _appendSmoothedPoint(
        worldPoints: worldPoints,
        currentPosition: adjustedPosition,
      );
    }

    final rect = _boundsFromPoints(nextPoints);
    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: nextPoints,
      rect: rect,
    );
    final updatedData = elementData.copyWith(points: normalized);

    return CreationUpdateResult(
      data: updatedData,
      rect: rect,
      creationMode: mode.copyWith(isLineActive: maintainAspectRatio),
    );
  }

  @override
  CreationFinishResult finish({
    required DrawConfig config,
    required CreatingState creatingState,
  }) {
    final data = creatingState.elementData;
    if (data is! FreeDrawData) {
      return CreationFinishResult(
        data: data,
        rect: creatingState.currentRect,
        shouldCommit: false,
      );
    }

    final worldPoints = _resolveWorldPoints(
      rect: creatingState.currentRect,
      normalizedPoints: data.points,
    );
    var points = _removeAdjacentDuplicates(worldPoints);
    if (points.length < 2) {
      return CreationFinishResult(
        data: data,
        rect: creatingState.currentRect,
        shouldCommit: false,
      );
    }

    points = _closeIfNeeded(
      points,
      closeTolerance:
          config.selection.interaction.handleTolerance *
          ConfigDefaults.freeDrawCloseToleranceMultiplier,
    );
    final length = _pathLength(points);
    if (!length.isFinite || length < config.element.minCreateSize) {
      return CreationFinishResult(
        data: data,
        rect: creatingState.currentRect,
        shouldCommit: false,
      );
    }

    final rect = _boundsFromPoints(points);
    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: points,
      rect: rect,
    );
    final updatedData = data.copyWith(points: normalized);

    return CreationFinishResult(
      data: updatedData,
      rect: rect,
      shouldCommit: true,
    );
  }
}

// ============================================================
// Private helpers
// ============================================================

List<DrawPoint> _resolveWorldPoints({
  required DrawRect rect,
  required List<DrawPoint> normalizedPoints,
}) {
  final resolved = ArrowGeometry.resolveWorldPoints(
    rect: rect,
    normalizedPoints: normalizedPoints,
  );
  // Carry pressure through from the normalized points.
  return List<DrawPoint>.generate(
    resolved.length,
    (i) => DrawPoint(
      x: resolved[i].dx,
      y: resolved[i].dy,
      pressure: i < normalizedPoints.length
          ? normalizedPoints[i].pressure
          : 0.0,
    ),
    growable: false,
  );
}

DrawRect _boundsFromPoints(List<DrawPoint> points) {
  if (points.isEmpty) {
    return const DrawRect();
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

List<DrawPoint> _removeAdjacentDuplicates(List<DrawPoint> points) {
  if (points.length <= 1) {
    return points;
  }
  final filtered = <DrawPoint>[points.first];
  for (final point in points.skip(1)) {
    if (point.x != filtered.last.x || point.y != filtered.last.y) {
      filtered.add(point);
    }
  }
  return filtered;
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
  if (first.x == last.x && first.y == last.y) {
    return points;
  }
  if (first.distanceSquared(last) <= closeTolerance * closeTolerance) {
    final closed = List<DrawPoint>.from(points);
    closed[closed.length - 1] = first.copyWith(pressure: last.pressure);
    return closed;
  }
  return points;
}

double _pathLength(List<DrawPoint> points) {
  if (points.length < 2) {
    return 0;
  }
  var length = 0.0;
  for (var i = 1; i < points.length; i++) {
    length += points[i - 1].distance(points[i]);
  }
  return length;
}

_FreeDrawCreationMode _resolveFreeDrawMode(CreationMode mode) =>
    mode is _FreeDrawCreationMode ? mode : const _FreeDrawCreationMode();

/// Appends a new point with real-time exponential smoothing and
/// minimum-distance filtering.
List<DrawPoint> _appendSmoothedPoint({
  required List<DrawPoint> worldPoints,
  required DrawPoint currentPosition,
}) {
  if (worldPoints.isEmpty) {
    return <DrawPoint>[currentPosition];
  }

  final nextPoints = List<DrawPoint>.from(worldPoints);
  if (nextPoints.length == 1) {
    nextPoints.add(currentPosition);
    return nextPoints;
  }

  final last = nextPoints.last;
  final distSq = last.distanceSquared(currentPosition);

  // Minimum distance filter: skip points that are too close.
  if (distSq < FreeDrawCreationStrategy._minDistanceSq) {
    // Still update the trailing point for responsiveness.
    nextPoints[nextPoints.length - 1] = currentPosition;
    return nextPoints;
  }

  // Exponential smoothing on position.
  const alpha = FreeDrawCreationStrategy._smoothingAlpha;
  final smoothed = DrawPoint(
    x: last.x * alpha + currentPosition.x * (1 - alpha),
    y: last.y * alpha + currentPosition.y * (1 - alpha),
    pressure: currentPosition.pressure,
    timestamp: currentPosition.timestamp,
  );

  nextPoints.add(smoothed);
  return nextPoints;
}

List<DrawPoint> _startLineSegment({
  required List<DrawPoint> worldPoints,
  required DrawPoint currentPosition,
}) {
  final nextPoints = List<DrawPoint>.from(worldPoints);
  if (nextPoints.isEmpty) {
    nextPoints.add(currentPosition);
  }
  final anchor = nextPoints.last;
  nextPoints.add(anchor);
  nextPoints[nextPoints.length - 1] = currentPosition;
  return nextPoints;
}

List<DrawPoint> _updateLineSegment({
  required List<DrawPoint> worldPoints,
  required DrawPoint currentPosition,
}) {
  if (worldPoints.isEmpty) {
    return <DrawPoint>[currentPosition];
  }
  final nextPoints = List<DrawPoint>.from(worldPoints);
  if (nextPoints.length == 1) {
    nextPoints.add(currentPosition);
  } else {
    nextPoints[nextPoints.length - 1] = currentPosition;
  }
  return nextPoints;
}

@immutable
class _FreeDrawCreationMode extends CreationMode {
  const _FreeDrawCreationMode({this.isLineActive = false});

  final bool isLineActive;

  _FreeDrawCreationMode copyWith({bool? isLineActive}) =>
      _FreeDrawCreationMode(isLineActive: isLineActive ?? this.isLineActive);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FreeDrawCreationMode && other.isLineActive == isLineActive;

  @override
  int get hashCode => Object.hash(runtimeType, isLineActive);

  @override
  String toString() => '_FreeDrawCreationMode(isLineActive: $isLineActive)';
}
