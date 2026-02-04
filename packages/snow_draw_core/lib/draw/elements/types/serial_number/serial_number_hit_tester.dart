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
    final distance = math.sqrt(dx * dx + dy * dy);

    final strokeHit = _testStroke(
      radius: radius,
      distance: distance,
      strokeWidth: data.strokeWidth,
      tolerance: tolerance,
    );
    if (strokeHit) {
      return true;
    }

    final fillOpacity = (data.fillColor.a * element.opacity).clamp(0.0, 1.0);
    if (fillOpacity <= 0) {
      return false;
    }

    return distance <= radius;
  }

  bool _testStroke({
    required double radius,
    required double distance,
    required double strokeWidth,
    required double tolerance,
  }) {
    if (strokeWidth <= 0) {
      return false;
    }
    final strokeMargin = (strokeWidth / 2) + tolerance;
    return distance >= radius - strokeMargin &&
        distance <= radius + strokeMargin;
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}
