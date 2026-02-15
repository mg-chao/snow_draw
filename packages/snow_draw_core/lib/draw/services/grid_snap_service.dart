import 'package:meta/meta.dart';

import '../types/draw_point.dart';
import '../types/draw_rect.dart';

/// Snapping helpers for grid-aligned geometry.
@immutable
class GridSnapService {
  const GridSnapService();

  double snapValue(double value, double gridSize) {
    if (!_isSnapEnabled(gridSize) || !value.isFinite) {
      return value;
    }
    final normalized = value / gridSize;
    if (!normalized.isFinite) {
      return value;
    }
    final snapped = normalized.roundToDouble() * gridSize;
    return snapped.isFinite ? snapped : value;
  }

  DrawPoint snapPoint({required DrawPoint point, required double gridSize}) {
    if (!_isSnapEnabled(gridSize)) {
      return point;
    }
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
    if (!_isSnapEnabled(gridSize)) {
      return rect;
    }
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

  bool _isSnapEnabled(double gridSize) => gridSize.isFinite && gridSize > 0;

  bool _sameCoordinate(double a, double b) => a == b || (a.isNaN && b.isNaN);
}

const gridSnapService = GridSnapService();
