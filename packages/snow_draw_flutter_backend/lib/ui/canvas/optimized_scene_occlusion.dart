import 'dart:math' as math;

import 'package:snow_draw_core/draw/core/coordinates/element_space.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

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
  final lineSeed = _resolveTwoPointLineSeed(seedElement);
  if (lineSeed == null || maxLineQueryRects <= 0) {
    return [seedAabb];
  }

  final (start, end) = _resolveTwoPointWorldPoints(
    seedElement: seedElement,
    normalizedPoints: lineSeed.normalizedPoints,
  );

  final strokeWidth = lineSeed.strokeWidth.isFinite
      ? lineSeed.strokeWidth.abs()
      : 0.0;
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
  return _buildSegmentQueryRects(
    start: start,
    end: end,
    maxRects: maxLineQueryRects,
    padding: padding,
    targetSegmentLength: safeTargetSegmentLength,
  );
}

class _TwoPointLineSeed {
  const _TwoPointLineSeed({
    required this.normalizedPoints,
    required this.strokeWidth,
  });

  final List<DrawPoint> normalizedPoints;
  final double strokeWidth;
}

_TwoPointLineSeed? _resolveTwoPointLineSeed(ElementState seedElement) {
  final data = seedElement.data;
  return switch (data) {
    LineData(:final points, :final strokeWidth) when points.length == 2 =>
      _TwoPointLineSeed(normalizedPoints: points, strokeWidth: strokeWidth),
    FreeDrawData(:final points, :final strokeWidth) when points.length == 2 =>
      _TwoPointLineSeed(normalizedPoints: points, strokeWidth: strokeWidth),
    _ => null,
  };
}

(DrawPoint, DrawPoint) _resolveTwoPointWorldPoints({
  required ElementState seedElement,
  required List<DrawPoint> normalizedPoints,
}) {
  final rawPoints = ArrowGeometry.resolveWorldPoints(
    rect: seedElement.rect,
    normalizedPoints: normalizedPoints,
  );

  final start = DrawPoint(x: rawPoints[0].dx, y: rawPoints[0].dy);
  final end = DrawPoint(x: rawPoints[1].dx, y: rawPoints[1].dy);
  if (seedElement.rotation == 0) {
    return (start, end);
  }

  final space = ElementSpace(
    rotation: seedElement.rotation,
    origin: seedElement.rect.center,
  );
  return (space.toWorld(start), space.toWorld(end));
}

List<DrawRect> _buildSegmentQueryRects({
  required DrawPoint start,
  required DrawPoint end,
  required int maxRects,
  required double padding,
  required double targetSegmentLength,
}) {
  final baseRect = _segmentRect(start: start, end: end, padding: padding);
  final dx = (end.x - start.x).abs();
  final dy = (end.y - start.y).abs();
  final shouldSubdivide =
      dx > padding * _lineAxisAlignedToleranceFactor &&
      dy > padding * _lineAxisAlignedToleranceFactor;
  if (!shouldSubdivide || maxRects == 1) {
    return <DrawRect>[baseRect];
  }

  final length = start.distance(end);
  if (!length.isFinite || length <= 0) {
    return <DrawRect>[baseRect];
  }

  final effectiveTargetLength = math.max(targetSegmentLength, padding * 6);
  var chunkCount = (length / effectiveTargetLength).ceil();
  if (chunkCount < 1) {
    chunkCount = 1;
  } else if (chunkCount > maxRects) {
    chunkCount = maxRects;
  }
  if (chunkCount == 1) {
    return <DrawRect>[baseRect];
  }

  return List<DrawRect>.generate(chunkCount, (index) {
    final t0 = index / chunkCount;
    final t1 = (index + 1) / chunkCount;
    final chunkStart = _lerpPoint(start, end, t0);
    final chunkEnd = _lerpPoint(start, end, t1);
    return _segmentRect(start: chunkStart, end: chunkEnd, padding: padding);
  }, growable: false);
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
