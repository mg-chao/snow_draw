import 'dart:ui';

import '../../../config/draw_config.dart';
import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/element_hit_tester.dart';
import '../shared/two_point_stroke_utils.dart';
import 'free_draw_data.dart';
import 'free_draw_visual_cache.dart';

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

    final rect = element.rect;
    final localPosition = _toLocalPosition(element, position);

    if (data.points.length == 2) {
      if (data.strokeWidth <= 0) {
        return false;
      }
      return _hitTestTwoPointStrokeFast(
        rect: rect,
        data: data,
        localPosition: localPosition,
        tolerance: tolerance,
      );
    }

    final hasStroke = data.strokeWidth > 0;
    final fillOpacity = (data.fillColor.a * element.opacity).clamp(0.0, 1.0);
    final hasFill = fillOpacity > 0 && _isClosed(data, rect);
    if (!hasStroke && !hasFill) {
      return false;
    }

    final cached = FreeDrawVisualCache.instance.resolve(
      element: element,
      data: data,
    );

    if (hasStroke &&
        _hitTestStroke(
          rect: rect,
          data: data,
          localPosition: localPosition,
          tolerance: tolerance,
          cached: cached,
        )) {
      return true;
    }

    if (!hasFill ||
        cached.pointCount < 3 ||
        !_isInsideRect(rect, localPosition, 0)) {
      return false;
    }

    final fillPath = cached.getOrBuildClosedFillPath();
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
    const closeTolerance =
        ConfigDefaults.handleTolerance *
        ConfigDefaults.freeDrawCloseToleranceMultiplier;
    final dx = (first.x - last.x) * rect.width;
    final dy = (first.y - last.y) * rect.height;
    return (dx * dx + dy * dy) <= closeTolerance * closeTolerance;
  }

  @override
  DrawRect getBounds(ElementState element) => element.rect;

  bool _hitTestTwoPointStrokeFast({
    required DrawRect rect,
    required FreeDrawData data,
    required DrawPoint localPosition,
    required double tolerance,
  }) {
    final radius = (data.strokeWidth / 2) + tolerance;
    if (!radius.isFinite || radius <= 0) {
      return false;
    }
    if (!_isInsideRect(rect, localPosition, radius)) {
      return false;
    }

    final segment = resolveTwoPointStrokeSegmentWorld(
      rect: rect,
      startPoint: data.points.first,
      endPoint: data.points.last,
    );
    if (segment == null) {
      return false;
    }

    return hitTestTwoPointStrokeSegment(
      segment: segment,
      point: Offset(localPosition.x, localPosition.y),
      radius: radius,
    );
  }

  bool _hitTestStroke({
    required DrawRect rect,
    required FreeDrawData data,
    required DrawPoint localPosition,
    required double tolerance,
    required FreeDrawVisualEntry cached,
  }) {
    final radius = (data.strokeWidth / 2) + tolerance;
    if (!radius.isFinite || radius <= 0) {
      return false;
    }
    if (!_isInsideRect(rect, localPosition, radius)) {
      return false;
    }

    final flattened = cached.getOrBuildFlattened(data.strokeWidth);
    if (flattened.length < 2) {
      return false;
    }

    final testPoint = Offset(
      localPosition.x - rect.minX,
      localPosition.y - rect.minY,
    );
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
