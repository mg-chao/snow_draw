import 'dart:math' as math;

import '../../draw/core/coordinates/element_space.dart';
import '../../draw/elements/types/arrow/arrow_geometry.dart';
import '../../draw/elements/types/free_draw/free_draw_data.dart';
import '../../draw/elements/types/line/line_data.dart';
import '../../draw/models/element_state.dart';
import '../../draw/types/draw_point.dart';
import '../../draw/types/draw_rect.dart';

const _defaultMaxLineOccluderQueryRects = 12;
const _defaultLineOccluderPaddingFloor = 3.0;
const _defaultLineOccluderPaddingStrokeFactor = 0.75;
const _defaultLineOccluderTargetSegmentLength = 96.0;
const _lineAxisAlignedToleranceFactor = 2.0;

/// Resolves occluder query rects for localized optimized-scene rendering.
///
/// Non-line seeds and complex lines fall back to [seedAabb]. Two-point line
/// elements ([LineData] and line-like [FreeDrawData]) return segment-tight
/// rects expanded by stroke-aware padding. Long diagonal segments are split
/// into smaller chunks so localized optimized-scene rendering does not query
/// large, mostly-empty AABBs.
///
/// Invalid line tuning values (negative, `NaN`, `Infinity`) are normalized to
/// safe defaults to keep query planning stable.
List<DrawRect> resolveOptimizedOccluderQueryRects({
  required ElementState seedElement,
  required DrawRect seedAabb,
  int maxLineQueryRects = _defaultMaxLineOccluderQueryRects,
  double linePaddingFloor = _defaultLineOccluderPaddingFloor,
  double linePaddingStrokeFactor = _defaultLineOccluderPaddingStrokeFactor,
  double lineTargetSegmentLength = _defaultLineOccluderTargetSegmentLength,
}) {
  final data = seedElement.data;
  final normalizedPoints = switch (data) {
    LineData(:final points) when points.length == 2 => points,
    FreeDrawData(:final points) when points.length == 2 => points,
    _ => null,
  };
  if (normalizedPoints == null) {
    return [seedAabb];
  }

  final worldPoints = _resolveTwoPointWorldPoints(
    seedElement: seedElement,
    normalizedPoints: normalizedPoints,
  );
  if (worldPoints.length < 2) {
    return [seedAabb];
  }

  final rawStrokeWidth = switch (data) {
    LineData(:final strokeWidth) => strokeWidth,
    FreeDrawData(:final strokeWidth) => strokeWidth,
    _ => 0.0,
  };
  final strokeWidth = rawStrokeWidth.isFinite ? rawStrokeWidth.abs() : 0.0;
  final safePaddingFloor = _normalizeNonNegativeFinite(
    linePaddingFloor,
    fallback: _defaultLineOccluderPaddingFloor,
  );
  final safePaddingStrokeFactor = _normalizeNonNegativeFinite(
    linePaddingStrokeFactor,
    fallback: _defaultLineOccluderPaddingStrokeFactor,
  );
  final safeTargetSegmentLength = _normalizePositiveFinite(
    lineTargetSegmentLength,
    fallback: _defaultLineOccluderTargetSegmentLength,
  );
  final padding = math.max(
    safePaddingFloor,
    strokeWidth * safePaddingStrokeFactor,
  );
  final planner = _LineOccluderQueryPlanner(
    maxQueryRects: maxLineQueryRects,
    padding: padding,
    targetSegmentLength: safeTargetSegmentLength,
  );
  final queryRects = planner.build(worldPoints);
  return queryRects.isEmpty ? [seedAabb] : queryRects;
}

List<DrawPoint> _resolveTwoPointWorldPoints({
  required ElementState seedElement,
  required List<DrawPoint> normalizedPoints,
}) {
  final rawPoints = ArrowGeometry.resolveWorldPoints(
    rect: seedElement.rect,
    normalizedPoints: normalizedPoints,
  );
  if (rawPoints.isEmpty) {
    return const <DrawPoint>[];
  }
  if (seedElement.rotation == 0) {
    return rawPoints
        .map((point) => DrawPoint(x: point.dx, y: point.dy))
        .toList(growable: false);
  }

  final space = ElementSpace(
    rotation: seedElement.rotation,
    origin: seedElement.rect.center,
  );
  return rawPoints
      .map((point) => space.toWorld(DrawPoint(x: point.dx, y: point.dy)))
      .toList(growable: false);
}

class _LineOccluderQueryPlanner {
  const _LineOccluderQueryPlanner({
    required this.maxQueryRects,
    required this.padding,
    required this.targetSegmentLength,
  });

  final int maxQueryRects;
  final double padding;
  final double targetSegmentLength;

  List<DrawRect> build(List<DrawPoint> worldPoints) {
    if (maxQueryRects <= 0 || worldPoints.length < 2) {
      return const <DrawRect>[];
    }

    final rects = <DrawRect>[];
    for (var index = 1; index < worldPoints.length; index++) {
      final remainingBudget = maxQueryRects - rects.length;
      if (remainingBudget <= 0) {
        return const <DrawRect>[];
      }
      final segmentRects = _buildSegmentRects(
        start: worldPoints[index - 1],
        end: worldPoints[index],
        maxRects: remainingBudget,
      );
      if (segmentRects.isEmpty) {
        return const <DrawRect>[];
      }
      rects.addAll(segmentRects);
    }
    return rects;
  }

  List<DrawRect> _buildSegmentRects({
    required DrawPoint start,
    required DrawPoint end,
    required int maxRects,
  }) {
    final dx = (end.x - start.x).abs();
    final dy = (end.y - start.y).abs();
    final baseRect = _segmentRect(start: start, end: end, padding: padding);

    final shouldSubdivide =
        dx > padding * _lineAxisAlignedToleranceFactor &&
        dy > padding * _lineAxisAlignedToleranceFactor;
    if (!shouldSubdivide || maxRects <= 1) {
      return <DrawRect>[baseRect];
    }

    final length = start.distance(end);
    if (!length.isFinite || length <= 0) {
      return <DrawRect>[baseRect];
    }

    final effectiveTargetLength = math.max(targetSegmentLength, padding * 6);
    final chunkCount = (length / effectiveTargetLength).ceil().clamp(
      1,
      maxRects,
    );
    if (chunkCount <= 1) {
      return <DrawRect>[baseRect];
    }

    final rects = <DrawRect>[];
    for (var index = 0; index < chunkCount; index++) {
      final t0 = index / chunkCount;
      final t1 = (index + 1) / chunkCount;
      final chunkStart = _lerpPoint(start, end, t0);
      final chunkEnd = _lerpPoint(start, end, t1);
      rects.add(
        _segmentRect(start: chunkStart, end: chunkEnd, padding: padding),
      );
    }
    return rects;
  }
}

DrawRect _segmentRect({
  required DrawPoint start,
  required DrawPoint end,
  required double padding,
}) => DrawRect(
  minX: math.min(start.x, end.x) - padding,
  minY: math.min(start.y, end.y) - padding,
  maxX: math.max(start.x, end.x) + padding,
  maxY: math.max(start.y, end.y) + padding,
);

DrawPoint _lerpPoint(DrawPoint start, DrawPoint end, double t) => DrawPoint(
  x: start.x + (end.x - start.x) * t,
  y: start.y + (end.y - start.y) * t,
);

double _normalizeNonNegativeFinite(double value, {required double fallback}) {
  if (!value.isFinite || value < 0) {
    return fallback;
  }
  return value;
}

double _normalizePositiveFinite(double value, {required double fallback}) {
  if (!value.isFinite || value <= 0) {
    return fallback;
  }
  return value;
}
