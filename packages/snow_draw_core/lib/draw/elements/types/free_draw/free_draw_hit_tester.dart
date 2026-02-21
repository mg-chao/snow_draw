import '../../../config/draw_config.dart';
import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../core/element_hit_tester.dart';
import '../shared/hit_test_geometry.dart';
import 'free_draw_data.dart';

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
    final strokePoints = _resolveStrokePoints(rect: rect, data: data);
    if (strokePoints.length < 2) {
      return false;
    }

    if (hasStroke &&
        _hitTestStroke(
          rect: rect,
          data: data,
          localPosition: localPosition,
          tolerance: tolerance,
          strokePoints: strokePoints,
        )) {
      return true;
    }

    if (!hasFill ||
        strokePoints.length < 3 ||
        !isPointInsideRect(rect, localPosition, 0)) {
      return false;
    }

    final fillOutline = _resolveClosedFillOutlinePoints(
      strokePoints,
      strokeWidth: data.strokeWidth,
    );
    if (fillOutline.length < 3) {
      return false;
    }
    return isPointInsidePolygon(localPosition, fillOutline);
  }

  List<DrawPoint> _resolveStrokePoints({
    required DrawRect rect,
    required FreeDrawData data,
  }) {
    if (data.points.isEmpty) {
      return const <DrawPoint>[];
    }
    final width = rect.width;
    final height = rect.height;
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return const <DrawPoint>[];
    }
    return data.points
        .map(
          (point) => DrawPoint(
            x: rect.minX + point.x * width,
            y: rect.minY + point.y * height,
            pressure: point.pressure,
            timestamp: point.timestamp,
          ),
        )
        .toList(growable: false);
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
    if (!isPointInsideRect(rect, localPosition, radius)) {
      return false;
    }
    if (!rect.width.isFinite ||
        !rect.height.isFinite ||
        rect.width < 0 ||
        rect.height < 0) {
      return false;
    }

    final startPoint = data.points.first;
    final endPoint = data.points.last;
    final start = DrawPoint(
      x: rect.minX + (startPoint.x * rect.width),
      y: rect.minY + (startPoint.y * rect.height),
    );
    final end = DrawPoint(
      x: rect.minX + (endPoint.x * rect.width),
      y: rect.minY + (endPoint.y * rect.height),
    );
    if (!isFiniteDrawPoint(start) || !isFiniteDrawPoint(end)) {
      return false;
    }

    return distanceSquaredToSegment(localPosition, start, end) <=
        radius * radius;
  }

  bool _hitTestStroke({
    required DrawRect rect,
    required FreeDrawData data,
    required DrawPoint localPosition,
    required double tolerance,
    required List<DrawPoint> strokePoints,
  }) {
    final radius = (data.strokeWidth / 2) + tolerance;
    if (!radius.isFinite || radius <= 0) {
      return false;
    }
    if (!isPointInsideRect(rect, localPosition, radius)) {
      return false;
    }

    final flattened = _resolveFlattenedStrokePoints(
      strokePoints: strokePoints,
      strokeWidth: data.strokeWidth,
    );
    if (flattened.length < 2) {
      return false;
    }
    final radiusSq = radius * radius;
    for (var i = 1; i < flattened.length; i++) {
      final distance = distanceSquaredToSegment(
        localPosition,
        flattened[i - 1],
        flattened[i],
      );
      if (distance <= radiusSq) {
        return true;
      }
    }
    return false;
  }

  List<DrawPoint> _resolveFlattenedStrokePoints({
    required List<DrawPoint> strokePoints,
    required double strokeWidth,
  }) {
    if (strokePoints.length < 3) {
      return strokePoints;
    }
    final closed = _sameLocation(strokePoints.first, strokePoints.last);
    final source = closed && strokePoints.length > 3
        ? strokePoints.sublist(0, strokePoints.length - 1)
        : strokePoints;
    final smoothed = _smoothStrokePoints(source, closed: closed);
    final flattened = flattenCatmullRomDrawPoints(
      points: smoothed,
      strokeWidth: strokeWidth,
      maxPoints: 256,
    );
    if (flattened.length < 2) {
      return source;
    }
    if (closed && !_sameLocation(flattened.first, flattened.last)) {
      return <DrawPoint>[...flattened, flattened.first];
    }
    return flattened;
  }

  List<DrawPoint> _resolveClosedFillOutlinePoints(
    List<DrawPoint> strokePoints, {
    required double strokeWidth,
  }) {
    final flattened = _resolveFlattenedStrokePoints(
      strokePoints: strokePoints,
      strokeWidth: strokeWidth,
    );
    if (flattened.length < 3) {
      return const <DrawPoint>[];
    }
    final outline = <DrawPoint>[];
    DrawPoint? previous;
    for (final point in flattened) {
      if (previous != null && previous.x == point.x && previous.y == point.y) {
        continue;
      }
      outline.add(point);
      previous = point;
    }
    if (outline.length < 3) {
      return const <DrawPoint>[];
    }
    final first = outline.first;
    final last = outline.last;
    if (first.x != last.x || first.y != last.y) {
      outline.add(first);
    }
    return outline;
  }

  List<DrawPoint> _smoothStrokePoints(
    List<DrawPoint> points, {
    required bool closed,
  }) {
    if (points.length < 3) {
      return points;
    }

    const iterations = 3;
    final count = points.length;
    final lastIndex = count - 1;

    var src = List<DrawPoint>.of(points);
    var dst = List<DrawPoint>.filled(count, DrawPoint.zero);

    for (var iteration = 0; iteration < iterations; iteration++) {
      if (closed) {
        for (var index = 0; index <= lastIndex; index++) {
          final prev = src[(index - 1 + count) % count];
          final current = src[index];
          final next = src[(index + 1) % count];
          dst[index] = DrawPoint(
            x: (prev.x + current.x * 2 + next.x) * 0.25,
            y: (prev.y + current.y * 2 + next.y) * 0.25,
          );
        }
      } else {
        dst[0] = src[0];
        dst[lastIndex] = src[lastIndex];
        for (var index = 1; index < lastIndex; index++) {
          final prev = src[index - 1];
          final current = src[index];
          final next = src[index + 1];
          dst[index] = DrawPoint(
            x: (prev.x + current.x * 2 + next.x) * 0.25,
            y: (prev.y + current.y * 2 + next.y) * 0.25,
          );
        }
      }
      final temp = src;
      src = dst;
      dst = temp;
    }

    return src;
  }

  bool _sameLocation(DrawPoint a, DrawPoint b) => a.x == b.x && a.y == b.y;
}
