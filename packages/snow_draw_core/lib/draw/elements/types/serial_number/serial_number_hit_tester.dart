import 'dart:math' as math;

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/element_hit_tester.dart';
import 'serial_number_data.dart';
import 'serial_number_layout.dart';

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

    final effectiveRadius =
        radius + resolveSerialNumberStrokeWidth(data: data) / 2 + tolerance;
    if (effectiveRadius <= 0) {
      return false;
    }

    final dx = position.x - rect.centerX;
    final dy = position.y - rect.centerY;
    return dx * dx + dy * dy <= effectiveRadius * effectiveRadius;
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}
