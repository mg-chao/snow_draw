import 'dart:ui';

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
/// During interaction, the strategy keeps world-space points and an incremental
/// preview path in [FreeDrawCreationMode]. This avoids the previous O(n)
/// normalize -> copy -> re-render loop on every pointer event.
///
/// Normalization is now performed once at finish time.
@immutable
class FreeDrawCreationStrategy extends CreationStrategy {
  const FreeDrawCreationStrategy();

  /// Minimum squared distance between consecutive points (world units).
  static const _minDistanceSq = 2;

  /// Exponential smoothing factor (0 = none, 1 = no movement).
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

    final points = <DrawPoint>[startPosition, startPosition];
    final previewPath = Path()..moveTo(startPosition.x, startPosition.y);

    return CreationUpdateResult(
      // Keep element data stable during creation; normalize once in finish().
      data: data,
      rect: _boundsFromPoints(points),
      creationMode: FreeDrawCreationMode(
        worldPoints: points,
        previewPath: previewPath,
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
    if (state.application.isCreating) {
      // Free draw ignores state-derived modifiers during creation updates.
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

    final adjustedPosition = snappingMode == SnappingMode.grid
        ? gridSnapService.snapPoint(
            point: currentPosition,
            gridSize: config.grid.size,
          )
        : currentPosition;

    final mode = _resolveFreeDrawMode(creatingState.creationMode);

    final worldPoints =
        mode.worldPoints ??
        _resolveWorldPoints(
          rect: creatingState.currentRect,
          normalizedPoints: elementData.points,
        );

    final previewPath = mode.previewPath ?? _buildPreviewPath(worldPoints);

    final wasLineActive = mode.isLineActive;
    var lineAnchor = mode.lineAnchor;
    var lineCurrent = mode.lineCurrent;
    var previewChanged = false;

    if (maintainAspectRatio) {
      if (!wasLineActive) {
        _startLineSegment(
          worldPoints: worldPoints,
          currentPosition: adjustedPosition,
        );
        if (worldPoints.length >= 2) {
          lineAnchor = worldPoints[worldPoints.length - 2];
        } else if (worldPoints.isNotEmpty) {
          lineAnchor = worldPoints.first;
        }
        lineCurrent = worldPoints.isEmpty ? null : worldPoints.last;
        previewChanged = true;
      } else {
        final before = worldPoints.isEmpty ? null : worldPoints.last;
        _updateLineSegment(
          worldPoints: worldPoints,
          currentPosition: adjustedPosition,
        );
        final after = worldPoints.isEmpty ? null : worldPoints.last;
        lineCurrent = after;
        previewChanged = before != after;
      }
    } else {
      final completedLinePoint = wasLineActive
          ? (lineCurrent ?? (worldPoints.isNotEmpty ? worldPoints.last : null))
          : null;
      if (completedLinePoint != null) {
        _appendPreviewPoint(previewPath, completedLinePoint);
        previewChanged = true;
      }

      final appendResult = _appendSmoothedPoint(
        worldPoints: worldPoints,
        currentPosition: adjustedPosition,
      );
      if (appendResult.hasAppendedPoint) {
        _appendPreviewPoint(
          previewPath,
          appendResult.appendedPoint!,
          moveTo: worldPoints.length == 1,
        );
        previewChanged = true;
      }
      lineAnchor = null;
      lineCurrent = null;
    }

    final rect = _expandBounds(creatingState.currentRect, worldPoints);
    final lineStateChanged = maintainAspectRatio != wasLineActive;
    final rectChanged = rect != creatingState.currentRect;

    if (!previewChanged && !lineStateChanged && !rectChanged) {
      return CreationUpdateResult(
        data: elementData,
        rect: creatingState.currentRect,
        creationMode: mode,
      );
    }

    return CreationUpdateResult(
      data: elementData,
      rect: rect,
      creationMode: mode.copyWith(
        isLineActive: maintainAspectRatio,
        worldPoints: worldPoints,
        previewPath: previewPath,
        lineAnchor: lineAnchor,
        lineCurrent: lineCurrent,
        revision: mode.revision + 1,
      ),
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

    final mode = _resolveFreeDrawMode(creatingState.creationMode);
    final worldPoints =
        mode.worldPoints ??
        _resolveWorldPoints(
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

    return CreationFinishResult(
      data: data.copyWith(points: normalized),
      rect: rect,
      shouldCommit: true,
    );
  }
}

// ============================================================
// Public creation mode for free-draw preview.
// ============================================================

@immutable
class FreeDrawCreationMode extends CreationMode {
  const FreeDrawCreationMode({
    this.isLineActive = false,
    this.worldPoints,
    this.previewPath,
    this.lineAnchor,
    this.lineCurrent,
    this.revision = 0,
  });

  /// Whether Shift-based straight-segment mode is active.
  final bool isLineActive;

  /// Accumulated world-space points carried between updates.
  ///
  /// This list is intentionally mutable during a single creation session to
  /// avoid allocating and copying on every pointer event.
  final List<DrawPoint>? worldPoints;

  /// Incremental world-space preview path used for low-latency rendering.
  final Path? previewPath;

  /// Anchor point for the active straight segment while Shift is held.
  final DrawPoint? lineAnchor;

  /// Current endpoint for the active straight segment while Shift is held.
  final DrawPoint? lineCurrent;

  /// Monotonic revision used for repaint invalidation.
  final int revision;

  static const _unset = Object();

  FreeDrawCreationMode copyWith({
    bool? isLineActive,
    List<DrawPoint>? worldPoints,
    Path? previewPath,
    Object? lineAnchor = _unset,
    Object? lineCurrent = _unset,
    int? revision,
  }) => FreeDrawCreationMode(
    isLineActive: isLineActive ?? this.isLineActive,
    worldPoints: worldPoints ?? this.worldPoints,
    previewPath: previewPath ?? this.previewPath,
    lineAnchor: identical(lineAnchor, _unset)
        ? this.lineAnchor
        : lineAnchor as DrawPoint?,
    lineCurrent: identical(lineCurrent, _unset)
        ? this.lineCurrent
        : lineCurrent as DrawPoint?,
    revision: revision ?? this.revision,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreeDrawCreationMode &&
          other.isLineActive == isLineActive &&
          other.revision == revision;

  @override
  int get hashCode => Object.hash(runtimeType, isLineActive, revision);

  @override
  String toString() =>
      'FreeDrawCreationMode('
      'isLineActive: $isLineActive, '
      'revision: $revision'
      ')';
}

// ============================================================
// Private helpers
// ============================================================

FreeDrawCreationMode _resolveFreeDrawMode(CreationMode mode) =>
    mode is FreeDrawCreationMode ? mode : const FreeDrawCreationMode();

List<DrawPoint> _resolveWorldPoints({
  required DrawRect rect,
  required List<DrawPoint> normalizedPoints,
}) {
  final resolved = ArrowGeometry.resolveWorldPoints(
    rect: rect,
    normalizedPoints: normalizedPoints,
  );
  return List<DrawPoint>.generate(
    resolved.length,
    (i) => DrawPoint(
      x: resolved[i].dx,
      y: resolved[i].dy,
      pressure: i < normalizedPoints.length ? normalizedPoints[i].pressure : 0,
    ),
  );
}

Path _buildPreviewPath(List<DrawPoint> worldPoints) {
  final path = Path();
  if (worldPoints.isEmpty) {
    return path;
  }

  path.moveTo(worldPoints.first.x, worldPoints.first.y);
  for (var i = 1; i < worldPoints.length; i++) {
    final point = worldPoints[i];
    path.lineTo(point.x, point.y);
  }
  return path;
}

void _appendPreviewPoint(Path path, DrawPoint point, {bool moveTo = false}) {
  if (moveTo) {
    path.moveTo(point.x, point.y);
    return;
  }
  path.lineTo(point.x, point.y);
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

/// Expands [current] to include the last two points of [points].
DrawRect _expandBounds(DrawRect current, List<DrawPoint> points) {
  if (points.isEmpty) {
    return current;
  }

  var minX = current.minX;
  var maxX = current.maxX;
  var minY = current.minY;
  var maxY = current.maxY;

  final start = points.length > 2 ? points.length - 2 : 0;
  for (var i = start; i < points.length; i++) {
    final point = points[i];
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

@immutable
class _AppendPointResult {
  const _AppendPointResult({this.appendedPoint});
  final DrawPoint? appendedPoint;

  bool get hasAppendedPoint => appendedPoint != null;
}

/// Appends a new point with smoothing and minimum-distance filtering.
///
/// Mutates [worldPoints] in place to avoid O(n) list copies.
_AppendPointResult _appendSmoothedPoint({
  required List<DrawPoint> worldPoints,
  required DrawPoint currentPosition,
}) {
  if (worldPoints.isEmpty) {
    worldPoints.add(currentPosition);
    return _AppendPointResult(appendedPoint: currentPosition);
  }

  if (worldPoints.length == 1) {
    worldPoints.add(currentPosition);
    return _AppendPointResult(appendedPoint: currentPosition);
  }

  final last = worldPoints.last;
  final distSq = last.distanceSquared(currentPosition);
  if (distSq < FreeDrawCreationStrategy._minDistanceSq) {
    return const _AppendPointResult();
  }

  const alpha = FreeDrawCreationStrategy._smoothingAlpha;
  final smoothed = DrawPoint(
    x: last.x * alpha + currentPosition.x * (1 - alpha),
    y: last.y * alpha + currentPosition.y * (1 - alpha),
    pressure: currentPosition.pressure,
    timestamp: currentPosition.timestamp,
  );

  worldPoints.add(smoothed);
  return _AppendPointResult(appendedPoint: smoothed);
}

void _startLineSegment({
  required List<DrawPoint> worldPoints,
  required DrawPoint currentPosition,
}) {
  if (worldPoints.isEmpty) {
    worldPoints.add(currentPosition);
  }

  final anchor = worldPoints.last;
  worldPoints.add(anchor);
  worldPoints[worldPoints.length - 1] = currentPosition;
}

void _updateLineSegment({
  required List<DrawPoint> worldPoints,
  required DrawPoint currentPosition,
}) {
  if (worldPoints.isEmpty) {
    worldPoints.add(currentPosition);
    return;
  }

  if (worldPoints.length == 1) {
    worldPoints.add(currentPosition);
    return;
  }
  worldPoints[worldPoints.length - 1] = currentPosition;
}
