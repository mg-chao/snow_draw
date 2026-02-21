import 'dart:ui' show Offset;

import 'package:snow_draw_core/draw/services/coordinate_service.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';

/// Flutter offset adapters for core [CoordinateService].
extension CoordinateServiceOffsetExtensions on CoordinateService {
  /// Converts a Flutter [Offset] in screen/widget space to world coordinates.
  DrawPoint screenOffsetToWorld(Offset offset) =>
      screenToWorld(DrawPoint(x: offset.dx, y: offset.dy));

  /// Converts world coordinates to a Flutter [Offset] in screen/widget space.
  Offset worldPointToScreenOffset(DrawPoint worldPoint) {
    final screenPoint = worldToScreen(worldPoint);
    return Offset(screenPoint.x, screenPoint.y);
  }
}
