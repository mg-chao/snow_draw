import 'package:meta/meta.dart';

import '../types/draw_point.dart';
import '../types/draw_rect.dart';

/// Snapping helpers for grid-aligned geometry.
@immutable
class GridSnapService {
  const GridSnapService();

  double snapValue(double value, double gridSize) {
    if (!value.isFinite || !gridSize.isFinite || gridSize <= 0) {
      return value;
    }

    final snapped = (value / gridSize).roundToDouble() * gridSize;
    return snapped.isFinite ? snapped : value;
  }

  DrawPoint snapPoint({required DrawPoint point, required double gridSize}) {
    final snappedX = snapValue(point.x, gridSize);
    final snappedY = snapValue(point.y, gridSize);
    if (_sameCoordinate(snappedX, point.x) &&
        _sameCoordinate(snappedY, point.y)) {
      return point;
    }
    return DrawPoint(x: snappedX, y: snappedY);
  }

  DrawRect snapRect({
    required DrawRect rect,
    required double gridSize,
    bool snapMinX = false,
    bool snapMaxX = false,
    bool snapMinY = false,
    bool snapMaxY = false,
  }) {
    if (!snapMinX && !snapMaxX && !snapMinY && !snapMaxY) {
      return rect;
    }

    final snappedMinX = snapMinX ? snapValue(rect.minX, gridSize) : rect.minX;
    final snappedMinY = snapMinY ? snapValue(rect.minY, gridSize) : rect.minY;
    final snappedMaxX = snapMaxX ? snapValue(rect.maxX, gridSize) : rect.maxX;
    final snappedMaxY = snapMaxY ? snapValue(rect.maxY, gridSize) : rect.maxY;

    if (_sameCoordinate(snappedMinX, rect.minX) &&
        _sameCoordinate(snappedMinY, rect.minY) &&
        _sameCoordinate(snappedMaxX, rect.maxX) &&
        _sameCoordinate(snappedMaxY, rect.maxY)) {
      return rect;
    }

    return DrawRect(
      minX: snappedMinX,
      minY: snappedMinY,
      maxX: snappedMaxX,
      maxY: snappedMaxY,
    );
  }

  bool _sameCoordinate(double a, double b) => a == b || (a.isNaN && b.isNaN);
}

const gridSnapService = GridSnapService();
