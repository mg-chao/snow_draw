import 'dart:math' as math;
import 'dart:ui';

import '../../../config/draw_config.dart';
import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/element_hit_tester.dart';
import 'free_draw_data.dart';
import 'free_draw_path_utils.dart';

class FreeDrawHitTester implements ElementHitTester {
  const FreeDrawHitTester();

  @override
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  }) {
    final data = element.data;
    if (data is! FreeDrawData) {
      throw StateError(
        'FreeDrawHitTester can only hit test FreeDrawData '
        '(got ${data.runtimeType})',
      );
    }

    if (data.strokeWidth > 0) {
      final localPosition = _toLocalPosition(element, position);
      if (_hitTestStroke(element, data, localPosition, tolerance)) {
        return true;
      }
    }

    final fillOpacity = (data.fillColor.a * element.opacity).clamp(0.0, 1.0);
    if (fillOpacity <= 0 || !_isClosed(data, element.rect)) {
      return false;
    }

    final rect = element.rect;
    final localPosition = _toLocalPosition(element, position);
    if (!_isInsideRect(rect, localPosition, 0)) {
      return false;
    }

    final localPoints = resolveFreeDrawLocalPoints(
      rect: rect,
      points: data.points,
    );
    if (localPoints.length < 3) {
      return false;
    }
    final fillPath = buildFreeDrawSmoothPath(localPoints)..close();
    final testPoint = Offset(
      localPosition.x - rect.minX,
      localPosition.y - rect.minY,
    );
    return fillPath.contains(testPoint);
  }

  DrawPoint _toLocalPosition(ElementState element, DrawPoint position) {
    if (element.rotation == 0) {
      return position;
    }
    final rect = element.rect;
    final space = ElementSpace(rotation: element.rotation, origin: rect.center);
    return space.fromWorld(position);
  }

  bool _isClosed(FreeDrawData data, DrawRect rect) {
    if (data.points.length < 3) {
      return false;
    }
    final first = data.points.first;
    final last = data.points.last;
    if (first == last) {
      return true;
    }
    const tolerance =
        ConfigDefaults.handleTolerance *
        ConfigDefaults.freeDrawCloseToleranceMultiplier;
    final dx = (first.x - last.x) * rect.width;
    final dy = (first.y - last.y) * rect.height;
    return (dx * dx + dy * dy) <= tolerance * tolerance;
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;
}

bool _hitTestStroke(
  ElementState element,
  FreeDrawData data,
  DrawPoint localPosition,
  double tolerance,
) {
  final rect = element.rect;
  final localPoints = resolveFreeDrawLocalPoints(
    rect: rect,
    points: data.points,
  );
  if (localPoints.length < 2) {
    return false;
  }
  final radius = (data.strokeWidth / 2) + tolerance;
  final boundsPadding = radius;
  if (!_isInsideRect(rect, localPosition, boundsPadding)) {
    return false;
  }

  final testPoint = Offset(
    localPosition.x - rect.minX,
    localPosition.y - rect.minY,
  );
  final smoothedPath = buildFreeDrawSmoothPath(localPoints);
  final flattened = _flattenPath(smoothedPath, _sampleStep(data.strokeWidth));
  if (flattened.length < 2) {
    return false;
  }
  final radiusSq = radius * radius;
  for (var i = 1; i < flattened.length; i++) {
    final distance = _distanceSquaredToSegment(
      testPoint,
      flattened[i - 1],
      flattened[i],
    );
    if (distance <= radiusSq) {
      return true;
    }
  }
  return false;
}

bool _isInsideRect(DrawRect rect, DrawPoint position, double padding) =>
    position.x >= rect.minX - padding &&
    position.x <= rect.maxX + padding &&
    position.y >= rect.minY - padding &&
    position.y <= rect.maxY + padding;

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

double _sampleStep(double strokeWidth) => math.max(1, strokeWidth).toDouble();

List<Offset> _flattenPath(Path path, double step) {
  if (step <= 0) {
    return const <Offset>[];
  }

  const maxPoints = 512;
  final flattened = <Offset>[];
  for (final metric in path.computeMetrics()) {
    final length = metric.length;
    var distance = 0.0;
    while (distance < length && flattened.length < maxPoints) {
      final tangent = metric.getTangentForOffset(distance);
      if (tangent != null) {
        final point = tangent.position;
        if (flattened.isEmpty || point != flattened.last) {
          flattened.add(point);
        }
      }
      distance += step;
    }
    if (flattened.length >= maxPoints) {
      break;
    }
    final endTangent = metric.getTangentForOffset(length);
    if (endTangent != null) {
      final point = endTangent.position;
      if (flattened.isEmpty || point != flattened.last) {
        flattened.add(point);
      }
    }
  }
  return flattened;
}
