import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../elements/core/creation_strategy.dart';
import '../../../elements/core/element_data.dart';
import '../../../models/draw_state.dart';
import '../../../models/interaction_state.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../../utils/snapping_mode.dart';
import '../arrow/arrow_geometry.dart';
import 'free_draw_data.dart';

/// Creation strategy for freehand drawing.
///
/// During interaction, the strategy keeps world-space points and an incremental
/// preview payload in [FreeDrawCreationMode]. Solid strokes use point-only
/// previews, while dashed/dotted strokes also carry incremental preview points.
/// The rendering backend can rebuild a concrete path from these points. This
/// avoids the previous O(n) normalize -> copy -> re-render loop on every
/// pointer event.
///
/// Normalization is performed once at finish time and produces the final
/// persisted free-draw points used by render/hit-test paths.
@immutable
class FreeDrawCreationStrategy extends CreationStrategy {
  const FreeDrawCreationStrategy();

  /// Minimum point spacing in world units before sampling the next point.
  static const _baseMinDistance = 1.5;

  /// Exponential smoothing factor (0 = none, 1 = no movement).
  static const _smoothingAlpha = 0.2;

  /// Maximum direction change (sine(theta)) before we stop tail replacement.
  static const _tailReplaceMaxTurnSin = 0.08;

  @override
  CreationUpdateResult start({
    required ElementData data,
    required DrawPoint startPosition,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    final freeDrawData = requireCreationDataType<FreeDrawData>(
      data: data,
      strategyName: 'FreeDrawCreationStrategy.start',
    );

    final points = <DrawPoint>[startPosition, startPosition];
    final previewPoints = _resolvePreviewPointsIfNeeded(
      strokeStyle: freeDrawData.strokeStyle,
      worldPoints: points,
    );

    return CreationUpdateResult(
      // Keep element data stable during creation; normalize once in finish().
      data: freeDrawData,
      rect: _boundsFromPoints(points),
      creationMode: FreeDrawCreationMode(
        worldPoints: points,
        previewPoints: previewPoints,
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
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    final elementData = requireCreatingElementDataType<FreeDrawData>(
      creatingState: creatingState,
      strategyName: 'FreeDrawCreationStrategy.update',
    );

    final adjustedPosition = snapCreationPoint(
      point: currentPosition,
      config: config,
      snappingMode: snappingMode,
    );

    final mode = _resolveFreeDrawMode(creatingState.creationMode);

    final worldPoints = _resolveCreationWorldPoints(
      mode: mode,
      rect: creatingState.currentRect,
      normalizedPoints: elementData.points,
    );

    final previewPoints = _resolvePreviewPointsIfNeeded(
      existingPoints: mode.previewPoints,
      worldPoints: worldPoints,
      strokeStyle: elementData.strokeStyle,
    );

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
        lineAnchor = worldPoints[worldPoints.length - 2];
        lineCurrent = worldPoints.last;
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
      if (completedLinePoint != null && previewPoints != null) {
        _appendPreviewPoint(previewPoints, completedLinePoint);
        previewChanged = true;
      }

      final pointMutation = _appendSmoothedPoint(
        worldPoints: worldPoints,
        currentPosition: adjustedPosition,
        strokeWidth: elementData.strokeWidth,
        allowTailReplace: previewPoints == null,
      );
      if (pointMutation.hasChange) {
        if (previewPoints != null && pointMutation.appendedPoint != null) {
          _appendPreviewPoint(previewPoints, pointMutation.appendedPoint!);
        }
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
        previewPoints: previewPoints,
        lineAnchor: lineAnchor,
        lineCurrent: lineCurrent,
        revision: mode.revision + 1,
      ),
    );
  }

  @override
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

    if (positions.length == 1 || maintainAspectRatio) {
      return update(
        state: state,
        config: config,
        creatingState: creatingState,
        currentPosition: positions.last,
        maintainAspectRatio: maintainAspectRatio,
        createFromCenter: createFromCenter,
        snappingMode: snappingMode,
        textMetricsService: textMetricsService,
      );
    }

    final elementData = requireCreatingElementDataType<FreeDrawData>(
      creatingState: creatingState,
      strategyName: 'FreeDrawCreationStrategy.updateBatch',
    );

    final mode = _resolveFreeDrawMode(creatingState.creationMode);
    final worldPoints = _resolveCreationWorldPoints(
      mode: mode,
      rect: creatingState.currentRect,
      normalizedPoints: elementData.points,
    );
    final previewPoints = _resolvePreviewPointsIfNeeded(
      existingPoints: mode.previewPoints,
      worldPoints: worldPoints,
      strokeStyle: elementData.strokeStyle,
    );

    var rect = creatingState.currentRect;
    var previewChanged = false;

    if (mode.isLineActive) {
      final completedLinePoint =
          mode.lineCurrent ??
          (worldPoints.isNotEmpty ? worldPoints.last : null);
      if (completedLinePoint != null && previewPoints != null) {
        _appendPreviewPoint(previewPoints, completedLinePoint);
        rect = _expandBoundsWithPoint(rect, completedLinePoint);
        previewChanged = true;
      }
    }

    for (final rawPosition in positions) {
      final adjustedPosition = snapCreationPoint(
        point: rawPosition,
        config: config,
        snappingMode: snappingMode,
      );
      final pointMutation = _appendSmoothedPoint(
        worldPoints: worldPoints,
        currentPosition: adjustedPosition,
        strokeWidth: elementData.strokeWidth,
        allowTailReplace: previewPoints == null,
      );
      if (!pointMutation.hasChange) {
        continue;
      }
      if (previewPoints != null && pointMutation.appendedPoint != null) {
        _appendPreviewPoint(previewPoints, pointMutation.appendedPoint!);
      }
      final changedPoint = pointMutation.changedPoint;
      if (changedPoint != null) {
        rect = _expandBoundsWithPoint(rect, changedPoint);
      }
      previewChanged = true;
    }

    final lineStateChanged = mode.isLineActive;
    if (!previewChanged && !lineStateChanged) {
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
        isLineActive: false,
        worldPoints: worldPoints,
        previewPoints: previewPoints,
        lineAnchor: null,
        lineCurrent: null,
        revision: mode.revision + 1,
      ),
    );
  }

  @override
  CreationFinishResult finish({
    required DrawConfig config,
    required CreatingState creatingState,
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    final data = requireCreatingElementDataType<FreeDrawData>(
      creatingState: creatingState,
      strategyName: 'FreeDrawCreationStrategy.finish',
    );

    final mode = _resolveFreeDrawMode(creatingState.creationMode);
    final worldPoints = _resolveCreationWorldPoints(
      mode: mode,
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
    final baked = _buildBakedNormalizedPoints(worldPoints: points, rect: rect);
    final finalizedPoints = baked ?? normalized;

    return CreationFinishResult(
      data: data.copyWith(points: finalizedPoints),
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
    this.previewPoints,
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

  /// Incremental world-space preview points for non-solid stroke previews.
  final List<DrawPoint>? previewPoints;

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
    Object? previewPoints = _unset,
    Object? lineAnchor = _unset,
    Object? lineCurrent = _unset,
    int? revision,
  }) => FreeDrawCreationMode(
    isLineActive: isLineActive ?? this.isLineActive,
    worldPoints: worldPoints ?? this.worldPoints,
    previewPoints: identical(previewPoints, _unset)
        ? this.previewPoints
        : previewPoints as List<DrawPoint>?,
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

List<DrawPoint> _resolveCreationWorldPoints({
  required FreeDrawCreationMode mode,
  required DrawRect rect,
  required List<DrawPoint> normalizedPoints,
}) =>
    mode.worldPoints ??
    ArrowGeometry.resolveWorldPoints(
      rect: rect,
      normalizedPoints: normalizedPoints,
    );

List<DrawPoint>? _resolvePreviewPointsIfNeeded({
  required List<DrawPoint> worldPoints,
  required StrokeStyle strokeStyle,
  List<DrawPoint>? existingPoints,
}) {
  if (strokeStyle == StrokeStyle.solid) {
    return null;
  }
  return existingPoints ?? List<DrawPoint>.from(worldPoints);
}

void _appendPreviewPoint(List<DrawPoint> previewPoints, DrawPoint point) =>
    previewPoints.add(point);

DrawRect _boundsFromPoints(List<DrawPoint> points) =>
    DrawRect.fromPointCloud(points);

/// Expands [current] to include the last two points of [points].
DrawRect _expandBounds(DrawRect current, List<DrawPoint> points) {
  if (points.isEmpty) {
    return current;
  }

  final start = points.length > 2 ? points.length - 2 : 0;
  return current.expandToIncludeAll(points.skip(start));
}

DrawRect _expandBoundsWithPoint(DrawRect current, DrawPoint point) =>
    current.expandToInclude(point);

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

List<DrawPoint>? _buildBakedNormalizedPoints({
  required List<DrawPoint> worldPoints,
  required DrawRect rect,
}) {
  if (worldPoints.length < 3) {
    return null;
  }

  final closed = _sameLocation(worldPoints.first, worldPoints.last);
  final source = closed && worldPoints.length > 3
      ? worldPoints.sublist(0, worldPoints.length - 1)
      : worldPoints;
  if (source.length < 3) {
    return null;
  }

  final smoothed = _smoothStrokePointsForBake(source, closed: closed);
  if (smoothed.length < 3) {
    return null;
  }

  final bakedWorldPoints =
      closed && !_sameLocation(smoothed.first, smoothed.last)
      ? <DrawPoint>[...smoothed, smoothed.first]
      : smoothed;
  if (bakedWorldPoints.length < 3) {
    return null;
  }

  return ArrowGeometry.normalizePoints(
    worldPoints: bakedWorldPoints,
    rect: rect,
  );
}

List<DrawPoint> _smoothStrokePointsForBake(
  List<DrawPoint> points, {
  required bool closed,
}) {
  if (points.length < 3) {
    return points;
  }

  const iterations = 3;
  final count = points.length;
  final lastIndex = count - 1;

  var src = List<DrawPoint>.of(points);
  var dst = List<DrawPoint>.filled(count, DrawPoint.zero);

  for (var iteration = 0; iteration < iterations; iteration++) {
    if (closed) {
      for (var index = 0; index <= lastIndex; index++) {
        final prev = src[(index - 1 + count) % count];
        final current = src[index];
        final next = src[(index + 1) % count];
        dst[index] = DrawPoint(
          x: (prev.x + current.x * 2 + next.x) * 0.25,
          y: (prev.y + current.y * 2 + next.y) * 0.25,
          pressure: current.pressure,
          timestamp: current.timestamp,
        );
      }
    } else {
      dst[0] = src[0];
      dst[lastIndex] = src[lastIndex];
      for (var index = 1; index < lastIndex; index++) {
        final prev = src[index - 1];
        final current = src[index];
        final next = src[index + 1];
        dst[index] = DrawPoint(
          x: (prev.x + current.x * 2 + next.x) * 0.25,
          y: (prev.y + current.y * 2 + next.y) * 0.25,
          pressure: current.pressure,
          timestamp: current.timestamp,
        );
      }
    }
    final temp = src;
    src = dst;
    dst = temp;
  }

  return src;
}

bool _sameLocation(DrawPoint a, DrawPoint b) => a.x == b.x && a.y == b.y;

/// Appends a new point with smoothing and minimum-distance filtering.
///
/// Mutates [worldPoints] in place to avoid O(n) list copies.
_FreeDrawPointMutation _appendSmoothedPoint({
  required List<DrawPoint> worldPoints,
  required DrawPoint currentPosition,
  required double strokeWidth,
  required bool allowTailReplace,
}) {
  if (worldPoints.length < 2) {
    worldPoints.add(currentPosition);
    return _FreeDrawPointMutation.appended(currentPosition);
  }

  final last = worldPoints.last;
  final minDistance = math.max(
    FreeDrawCreationStrategy._baseMinDistance,
    strokeWidth * 0.75,
  );
  final minDistanceSq = minDistance * minDistance;
  final distSq = last.distanceSquared(currentPosition);
  if (distSq < minDistanceSq) {
    return const _FreeDrawPointMutation.none();
  }

  const alpha = FreeDrawCreationStrategy._smoothingAlpha;
  final smoothed = DrawPoint(
    x: last.x * alpha + currentPosition.x * (1 - alpha),
    y: last.y * alpha + currentPosition.y * (1 - alpha),
    pressure: currentPosition.pressure,
    timestamp: currentPosition.timestamp,
  );

  if (allowTailReplace &&
      _shouldReplaceTailPoint(
        worldPoints: worldPoints,
        candidate: smoothed,
        strokeWidth: strokeWidth,
      )) {
    worldPoints[worldPoints.length - 1] = smoothed;
    return _FreeDrawPointMutation.replaced(smoothed);
  }

  worldPoints.add(smoothed);
  return _FreeDrawPointMutation.appended(smoothed);
}

bool _shouldReplaceTailPoint({
  required List<DrawPoint> worldPoints,
  required DrawPoint candidate,
  required double strokeWidth,
}) {
  if (worldPoints.length < 3) {
    return false;
  }

  final previous = worldPoints[worldPoints.length - 1];
  final previousPrevious = worldPoints[worldPoints.length - 2];
  final segX = previous.x - previousPrevious.x;
  final segY = previous.y - previousPrevious.y;
  final nextX = candidate.x - previous.x;
  final nextY = candidate.y - previous.y;

  final segLengthSq = segX * segX + segY * segY;
  final nextLengthSq = nextX * nextX + nextY * nextY;
  if (segLengthSq <= 1e-6 || nextLengthSq <= 1e-6) {
    return false;
  }

  final dot = segX * nextX + segY * nextY;
  if (dot <= 0) {
    return false;
  }

  final segLength = math.sqrt(segLengthSq);
  final nextLength = math.sqrt(nextLengthSq);
  final sinTurn =
      (segX * nextY - segY * nextX).abs() / (segLength * nextLength);
  if (sinTurn > FreeDrawCreationStrategy._tailReplaceMaxTurnSin) {
    return false;
  }

  final lineDistance = (segX * nextY - segY * nextX).abs() / segLength;
  final lineDistanceTolerance = math.max(0.5, strokeWidth * 0.35);
  return lineDistance <= lineDistanceTolerance;
}

class _FreeDrawPointMutation {
  const _FreeDrawPointMutation._({
    required this.hasChange,
    this.changedPoint,
    this.appendedPoint,
  });

  const _FreeDrawPointMutation.none() : this._(hasChange: false);

  const _FreeDrawPointMutation.appended(DrawPoint point)
    : this._(hasChange: true, changedPoint: point, appendedPoint: point);

  const _FreeDrawPointMutation.replaced(DrawPoint point)
    : this._(hasChange: true, changedPoint: point);

  final bool hasChange;
  final DrawPoint? changedPoint;
  final DrawPoint? appendedPoint;
}

void _startLineSegment({
  required List<DrawPoint> worldPoints,
  required DrawPoint currentPosition,
}) {
  if (worldPoints.isEmpty) {
    worldPoints.add(currentPosition);
  }
  worldPoints.add(currentPosition);
}

void _updateLineSegment({
  required List<DrawPoint> worldPoints,
  required DrawPoint currentPosition,
}) {
  if (worldPoints.length < 2) {
    _startLineSegment(
      worldPoints: worldPoints,
      currentPosition: currentPosition,
    );
    return;
  }
  worldPoints[worldPoints.length - 1] = currentPosition;
}
