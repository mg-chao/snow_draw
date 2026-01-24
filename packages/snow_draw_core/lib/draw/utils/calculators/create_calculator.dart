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
    double minX = min(startPosition.x, currentPosition.x);
    double minY = min(startPosition.y, currentPosition.y);
    double maxX = max(startPosition.x, currentPosition.x);
    double maxY = max(startPosition.y, currentPosition.y);

    if (createFromCenter) {
      final dx = (currentPosition.x - startPosition.x).abs();
      final dy = (currentPosition.y - startPosition.y).abs();
      minX = startPosition.x - dx;
      minY = startPosition.y - dy;
      maxX = startPosition.x + dx;
      maxY = startPosition.y + dy;
    }

    if (maintainAspectRatio) {
      final width = maxX - minX;
      final height = maxY - minY;

      if (width > height) {
        final newHeight = width;
        if (createFromCenter) {
          minY = startPosition.y - newHeight / 2;
          maxY = startPosition.y + newHeight / 2;
        } else {
          if (startPosition.y < currentPosition.y) {
            maxY = minY + newHeight;
          } else {
            minY = maxY - newHeight;
          }
        }
      } else {
        final newWidth = height;
        if (createFromCenter) {
          minX = startPosition.x - newWidth / 2;
          maxX = startPosition.x + newWidth / 2;
        } else {
          if (startPosition.x < currentPosition.x) {
            maxX = minX + newWidth;
          } else {
            minX = maxX - newWidth;
          }
        }
      }
    }

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }
}
