import 'dart:math' as math;
import 'dart:ui';

import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/element_hit_tester.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';

class ArrowHitTester implements ElementHitTester {
  const ArrowHitTester();

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) {
    final data = element.data;
    if (data is! ArrowData) {
      throw StateError(
        'ArrowHitTester can only hit test ArrowData (got ${data.runtimeType})',
      );
    }

    if (data.strokeWidth <= 0) {
      return false;
    }

    final localPosition = _toLocalPosition(element, position);
    final rect = element.rect;
    final testPoint = Offset(
      localPosition.x - rect.minX,
      localPosition.y - rect.minY,
    );
    final points = ArrowGeometry.resolveLocalPoints(
      rect: rect,
      normalizedPoints: data.points,
    );

    final radius = (data.strokeWidth / 2) + tolerance;
    if (_hitTestShaft(points, data.arrowType, testPoint, radius)) {
      return true;
    }

    return _hitTestArrowheads(points, data, testPoint, radius);
  }

  DrawPoint _toLocalPosition(ElementState element, DrawPoint position) {
    if (element.rotation == 0) {
      return position;
    }
    final rect = element.rect;
    final space = ElementSpace(rotation: element.rotation, origin: rect.center);
    return space.fromWorld(position);
  }

  bool _hitTestShaft(
    List<Offset> points,
    ArrowType arrowType,
    Offset position,
    double radius,
  ) {
    if (points.length < 2) {
      return false;
    }

    if (arrowType == ArrowType.curved && points.length > 2) {
      final path = ArrowGeometry.buildShaftPath(
        points: points,
        arrowType: arrowType,
      );
      return _hitTestPath(path, position, radius);
    }

    final resolvedPoints = arrowType == ArrowType.polyline
        ? ArrowGeometry.expandPolylinePoints(points)
        : points;
    final radiusSq = radius * radius;
    for (var i = 1; i < resolvedPoints.length; i++) {
      final distance = _distanceSquaredToSegment(
        position,
        resolvedPoints[i - 1],
        resolvedPoints[i],
      );
      if (distance <= radiusSq) {
        return true;
      }
    }
    return false;
  }

  bool _hitTestArrowheads(
    List<Offset> points,
    ArrowData data,
    Offset position,
    double radius,
  ) {
    final startInset = ArrowGeometry.calculateArrowheadInset(
      style: data.startArrowhead,
      strokeWidth: data.strokeWidth,
    );
    final endInset = ArrowGeometry.calculateArrowheadInset(
      style: data.endArrowhead,
      strokeWidth: data.strokeWidth,
    );
    final startDirectionOffset = ArrowGeometry.calculateArrowheadDirectionOffset(
      style: data.startArrowhead,
      strokeWidth: data.strokeWidth,
    );
    final endDirectionOffset = ArrowGeometry.calculateArrowheadDirectionOffset(
      style: data.endArrowhead,
      strokeWidth: data.strokeWidth,
    );

    final startDirection = ArrowGeometry.resolveStartDirection(
      points,
      data.arrowType,
      startInset: startInset,
      endInset: endInset,
      directionOffset: startDirectionOffset,
    );
    if (startDirection != null &&
        data.startArrowhead != ArrowheadStyle.none) {
      final path = ArrowGeometry.buildArrowheadPath(
        tip: points.first,
        direction: startDirection,
        style: data.startArrowhead,
        strokeWidth: data.strokeWidth,
      );
      if (_hitTestPath(path, position, radius)) {
        return true;
      }
    }

    final endDirection = ArrowGeometry.resolveEndDirection(
      points,
      data.arrowType,
      startInset: startInset,
      endInset: endInset,
      directionOffset: endDirectionOffset,
    );
    if (endDirection != null && data.endArrowhead != ArrowheadStyle.none) {
      final path = ArrowGeometry.buildArrowheadPath(
        tip: points.last,
        direction: endDirection,
        style: data.endArrowhead,
        strokeWidth: data.strokeWidth,
      );
      if (_hitTestPath(path, position, radius)) {
        return true;
      }
    }

    return false;
  }

  bool _hitTestPath(Path path, Offset position, double radius) {
    final radiusSq = radius * radius;
    final step = math.max(1, radius * 0.5);
    for (final metric in path.computeMetrics()) {
      final length = metric.length;
      var distance = 0.0;
      while (distance <= length) {
        final tangent = metric.getTangentForOffset(distance);
        if (tangent != null) {
          final dx = tangent.position.dx - position.dx;
          final dy = tangent.position.dy - position.dy;
          if (dx * dx + dy * dy <= radiusSq) {
            return true;
          }
        }
        distance += step;
      }
    }
    return false;
  }

  double _distanceSquaredToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final abLengthSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLengthSq == 0) {
      final dx = ap.dx;
      final dy = ap.dy;
      return dx * dx + dy * dy;
    }
    var t = (ap.dx * ab.dx + ap.dy * ab.dy) / abLengthSq;
    if (t < 0) {
      t = 0;
    } else if (t > 1) {
      t = 1;
    }
    final closest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    final dx = p.dx - closest.dx;
    final dy = p.dy - closest.dy;
    return dx * dx + dy * dy;
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}
