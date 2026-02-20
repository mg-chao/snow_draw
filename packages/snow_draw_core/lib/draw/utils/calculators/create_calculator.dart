import 'dart:math';

import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';

class CreateCalculator {
  CreateCalculator._();

  static DrawRect calculateCreateRect({
    required DrawPoint startPosition,
    required DrawPoint currentPosition,
    required bool maintainAspectRatio,
    required bool createFromCenter,
  }) {
    final dx = currentPosition.x - startPosition.x;
    final dy = currentPosition.y - startPosition.y;

    if (maintainAspectRatio) {
      final side = max(dx.abs(), dy.abs());

      if (createFromCenter) {
        return DrawRect(
          minX: startPosition.x - side,
          minY: startPosition.y - side,
          maxX: startPosition.x + side,
          maxY: startPosition.y + side,
        );
      }

      final endX = startPosition.x + (dx > 0 ? side : -side);
      final endY = startPosition.y + (dy > 0 ? side : -side);
      return DrawRect(
        minX: min(startPosition.x, endX),
        minY: min(startPosition.y, endY),
        maxX: max(startPosition.x, endX),
        maxY: max(startPosition.y, endY),
      );
    }

    if (createFromCenter) {
      return DrawRect(
        minX: startPosition.x - dx.abs(),
        minY: startPosition.y - dy.abs(),
        maxX: startPosition.x + dx.abs(),
        maxY: startPosition.y + dy.abs(),
      );
    }

    return DrawRect(
      minX: min(startPosition.x, currentPosition.x),
      minY: min(startPosition.y, currentPosition.y),
      maxX: max(startPosition.x, currentPosition.x),
      maxY: max(startPosition.y, currentPosition.y),
    );
  }
}
