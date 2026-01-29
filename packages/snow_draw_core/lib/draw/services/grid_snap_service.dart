import 'package:meta/meta.dart';

import '../types/draw_point.dart';
import '../types/draw_rect.dart';

/// Snapping helpers for grid-aligned geometry.
@immutable
class GridSnapService {
  const GridSnapService();

  double snapValue(double value, double gridSize) {
    if (gridSize <= 0) {
      return value;
    }
    return (value / gridSize).round() * gridSize;
  }

  DrawPoint snapPoint({required DrawPoint point, required double gridSize}) {
    if (gridSize <= 0) {
      return point;
    }
    return DrawPoint(
      x: snapValue(point.x, gridSize),
      y: snapValue(point.y, gridSize),
    );
  }

  DrawRect snapRect({
    required DrawRect rect,
    required double gridSize,
    bool snapMinX = false,
    bool snapMaxX = false,
    bool snapMinY = false,
    bool snapMaxY = false,
  }) {
    if (gridSize <= 0) {
      return rect;
    }
    return DrawRect(
      minX: snapMinX ? snapValue(rect.minX, gridSize) : rect.minX,
      minY: snapMinY ? snapValue(rect.minY, gridSize) : rect.minY,
      maxX: snapMaxX ? snapValue(rect.maxX, gridSize) : rect.maxX,
      maxY: snapMaxY ? snapValue(rect.maxY, gridSize) : rect.maxY,
    );
  }
}

const gridSnapService = GridSnapService();
