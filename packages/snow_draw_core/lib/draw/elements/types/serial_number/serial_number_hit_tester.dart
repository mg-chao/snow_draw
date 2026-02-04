import 'dart:math' as math;

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/element_hit_tester.dart';
import 'serial_number_data.dart';

class SerialNumberHitTester implements ElementHitTester {
  const SerialNumberHitTester();

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) {
    final data = element.data;
    if (data is! SerialNumberData) {
      throw StateError(
        'SerialNumberHitTester can only hit test SerialNumberData (got '
        '${data.runtimeType})',
      );
    }

    final rect = element.rect;
    final radius = math.min(rect.width, rect.height) / 2;
    if (radius <= 0) {
      return false;
    }

    final center = rect.center;
    final dx = position.x - center.x;
    final dy = position.y - center.y;
    final distanceSq = dx * dx + dy * dy;
    final strokeMargin = data.strokeWidth > 0 ? data.strokeWidth / 2 : 0.0;
    final effectiveRadius = radius + strokeMargin + tolerance;
    if (effectiveRadius <= 0) {
      return false;
    }

    return distanceSq <= effectiveRadius * effectiveRadius;
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}
