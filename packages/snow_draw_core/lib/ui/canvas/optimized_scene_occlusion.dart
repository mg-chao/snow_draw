import 'dart:math' as math;

import '../../draw/core/coordinates/element_space.dart';
import '../../draw/elements/types/arrow/arrow_geometry.dart';
import '../../draw/elements/types/line/line_data.dart';
import '../../draw/models/element_state.dart';
import '../../draw/types/draw_point.dart';
import '../../draw/types/draw_rect.dart';

const _defaultMaxLineOccluderQueryRects = 12;
const _defaultLineOccluderPaddingFloor = 3.0;
const _defaultLineOccluderPaddingStrokeFactor = 0.75;

/// Resolves occluder query rects for localized optimized-scene rendering.
///
/// Non-line seeds and complex lines fall back to [seedAabb]. Two-point lines
/// return segment-tight rects expanded by stroke-aware padding so the dynamic
/// scene includes only nearby top-order occluders.
List<DrawRect> resolveOptimizedOccluderQueryRects({
  required ElementState seedElement,
  required DrawRect seedAabb,
  int maxLineQueryRects = _defaultMaxLineOccluderQueryRects,
  double linePaddingFloor = _defaultLineOccluderPaddingFloor,
  double linePaddingStrokeFactor = _defaultLineOccluderPaddingStrokeFactor,
}) {
  final data = seedElement.data;
  if (data is! LineData || data.points.length != 2) {
    return [seedAabb];
  }

  final worldPoints = _resolveLineWorldPoints(
    seedElement: seedElement,
    data: data,
  );
  if (worldPoints.length < 2) {
    return [seedAabb];
  }

  final padding = math.max(
    linePaddingFloor,
    data.strokeWidth * linePaddingStrokeFactor,
  );
  final queryRects = <DrawRect>[];
  for (var index = 1; index < worldPoints.length; index++) {
    final start = worldPoints[index - 1];
    final end = worldPoints[index];
    queryRects.add(
      DrawRect(
        minX: math.min(start.x, end.x) - padding,
        minY: math.min(start.y, end.y) - padding,
        maxX: math.max(start.x, end.x) + padding,
        maxY: math.max(start.y, end.y) + padding,
      ),
    );
    if (queryRects.length >= maxLineQueryRects) {
      return [seedAabb];
    }
  }
  return queryRects.isEmpty ? [seedAabb] : queryRects;
}

List<DrawPoint> _resolveLineWorldPoints({
  required ElementState seedElement,
  required LineData data,
}) {
  final rawPoints = ArrowGeometry.resolveWorldPoints(
    rect: seedElement.rect,
    normalizedPoints: data.points,
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
