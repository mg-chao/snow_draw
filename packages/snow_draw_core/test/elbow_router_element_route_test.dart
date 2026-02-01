import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/core/coordinates/element_space.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

const _epsilon = 1e-3;

void main() {
  test('routeElbowArrowForElement keeps local/world points in sync', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 20, y: 40),
      const DrawPoint(x: 220, y: 140),
    ];
    final rect = _rectForPoints(points);
    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: points,
      rect: rect,
    );
    final data = ArrowData(
      points: normalized,
      arrowType: ArrowType.elbow,
    );
    final element = ElementState(
      id: 'arrow',
      rect: rect,
      rotation: math.pi / 6,
      opacity: 1,
      zIndex: 0,
      data: data,
    );

    final result = routeElbowArrowForElement(
      element: element,
      data: data,
      elementsById: const {},
    );

    expect(result.localPoints.length, result.worldPoints.length);
    expect(result.localPoints.length, greaterThanOrEqualTo(2));

    final space = ElementSpace(
      rotation: element.rotation,
      origin: element.rect.center,
    );
    for (var i = 0; i < result.localPoints.length; i++) {
      final projected = space.toWorld(result.localPoints[i]);
      expect(_pointsClose(projected, result.worldPoints[i]), isTrue);
    }

    expect(_pathIsOrthogonal(result.worldPoints), isTrue);
  });
}

DrawRect _rectForPoints(List<DrawPoint> points) {
  var minX = points.first.x;
  var maxX = points.first.x;
  var minY = points.first.y;
  var maxY = points.first.y;
  for (final point in points.skip(1)) {
    minX = math.min(minX, point.x);
    maxX = math.max(maxX, point.x);
    minY = math.min(minY, point.y);
    maxY = math.max(maxY, point.y);
  }
  if (minX == maxX) {
    maxX = minX + 1;
  }
  if (minY == maxY) {
    maxY = minY + 1;
  }
  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

bool _pointsClose(DrawPoint a, DrawPoint b) =>
    (a.x - b.x).abs() <= _epsilon && (a.y - b.y).abs() <= _epsilon;

bool _pathIsOrthogonal(List<DrawPoint> points) {
  for (var i = 0; i < points.length - 1; i++) {
    final dx = (points[i].x - points[i + 1].x).abs();
    final dy = (points[i].y - points[i + 1].y).abs();
    if (dx > _epsilon && dy > _epsilon) {
      return false;
    }
  }
  return true;
}
