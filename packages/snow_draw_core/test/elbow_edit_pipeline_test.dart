import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_editing.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('fixed segment release preserves remaining axis', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 60, y: 0),
      const DrawPoint(x: 60, y: 60),
      const DrawPoint(x: 120, y: 60),
      const DrawPoint(x: 120, y: 120),
      const DrawPoint(x: 180, y: 120),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
      ElbowFixedSegment(index: 4, start: points[3], end: points[4]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: points,
      fixedSegmentsOverride: <ElbowFixedSegment>[fixedSegments[1]],
    );

    expect(result.fixedSegments, isNotNull);
    expect(result.fixedSegments!.length, 1);
    expect(_pathIsOrthogonal(result.localPoints), isTrue);

    final before = fixedSegments[1];
    final after = result.fixedSegments!.first;
    expect(
      _isHorizontal(before.start, before.end),
      _isHorizontal(after.start, after.end),
    );

    final axisBefore = _segmentAxis(before);
    final axisAfter = _segmentAxis(after);
    expect(
      (axisAfter - axisBefore).abs() <= ElbowConstants.dedupThreshold,
      isTrue,
    );
  });

  test('endpoint drag keeps fixed segment axis', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 100, y: 0),
      const DrawPoint(x: 100, y: 80),
      const DrawPoint(x: 200, y: 80),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;
    final movedPoints = <DrawPoint>[
      const DrawPoint(x: 0, y: 40),
      points[1],
      points[2],
      points[3],
    ];

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
    );

    expect(result.fixedSegments, isNotNull);
    expect(result.fixedSegments!.length, 1);
    expect(_pathIsOrthogonal(result.localPoints), isTrue);

    final fixed = result.fixedSegments!.first;
    expect(_isHorizontal(fixed.start, fixed.end), isFalse);
    final axis = (fixed.start.x + fixed.end.x) / 2;
    expect((axis - 100).abs() <= ElbowConstants.dedupThreshold, isTrue);
  });

  test('binding edits keep a perpendicular start segment', () {
    const targetRect = DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200);
    final target = _rectangleElement(id: 'target', rect: targetRect);

    final points = <DrawPoint>[
      const DrawPoint(x: 150, y: 150),
      const DrawPoint(x: 240, y: 150),
      const DrawPoint(x: 240, y: 260),
    ];
    final element = _arrowElement(
      points,
      startBinding: const ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0.5, y: 0),
      ),
      startArrowhead: ArrowheadStyle.triangle,
    );
    final data = element.data as ArrowData;

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: {'target': target},
      localPointsOverride: points,
    );

    expect(_pathIsOrthogonal(result.localPoints), isTrue);

    final startPoint = result.localPoints.first;
    final nextPoint = result.localPoints[1];
    expect(
      (startPoint.x - nextPoint.x).abs() <=
          ElbowConstants.intersectionEpsilon,
      isTrue,
      reason: 'Top binding should depart vertically.',
    );
    expect(
      nextPoint.y < startPoint.y,
      isTrue,
      reason: 'Top binding should depart upward.',
    );
  });

  test('binding edits keep a perpendicular end segment', () {
    const targetRect = DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200);
    final target = _rectangleElement(id: 'target', rect: targetRect);

    final points = <DrawPoint>[
      const DrawPoint(x: 20, y: 150),
      const DrawPoint(x: 120, y: 150),
      const DrawPoint(x: 150, y: 150),
    ];
    final element = _arrowElement(
      points,
      endBinding: const ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 1, y: 0.5),
      ),
      endArrowhead: ArrowheadStyle.triangle,
    );
    final data = element.data as ArrowData;

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: {'target': target},
      localPointsOverride: points,
    );

    expect(_pathIsOrthogonal(result.localPoints), isTrue);

    final penultimate = result.localPoints[result.localPoints.length - 2];
    final endPoint = result.localPoints.last;
    expect(
      (penultimate.y - endPoint.y).abs() <=
          ElbowConstants.intersectionEpsilon,
      isTrue,
      reason: 'Right binding should approach horizontally.',
    );
    expect(
      penultimate.x > endPoint.x,
      isTrue,
      reason: 'Right binding should approach from the right.',
    );
  });

  test('changing a fixed segment axis re-applies points', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 100, y: 0),
      const DrawPoint(x: 100, y: 100),
      const DrawPoint(x: 200, y: 100),
      const DrawPoint(x: 200, y: 200),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 3, start: points[2], end: points[3]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    final overrideSegments = <ElbowFixedSegment>[
      const ElbowFixedSegment(
        index: 3,
        start: DrawPoint(x: 100, y: 140),
        end: DrawPoint(x: 200, y: 140),
      ),
    ];

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: points,
      fixedSegmentsOverride: overrideSegments,
    );

    expect(result.fixedSegments, isNotNull);
    expect(result.fixedSegments!.length, 1);

    final fixed = result.fixedSegments!.first;
    expect(_isHorizontal(fixed.start, fixed.end), isTrue);
    final axis = (fixed.start.y + fixed.end.y) / 2;
    expect((axis - 140).abs() <= ElbowConstants.dedupThreshold, isTrue);
  });

  test('endpoint drag snaps an unbound start neighbor orthogonally', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 100, y: 0),
      const DrawPoint(x: 100, y: 80),
      const DrawPoint(x: 200, y: 80),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;
    final movedPoints = <DrawPoint>[
      const DrawPoint(x: 30, y: 30),
      points[1],
      points[2],
      points[3],
    ];

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
    );

    expect(_pathIsOrthogonal(result.localPoints), isTrue);
    final start = result.localPoints.first;
    final neighbor = result.localPoints[1];
    expect((neighbor.y - start.y).abs() <= ElbowConstants.dedupThreshold, isTrue);
  });

  test('binding edits enforce a perpendicular start during endpoint drag', () {
    const targetRect = DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200);
    final target = _rectangleElement(id: 'target', rect: targetRect);

    final points = <DrawPoint>[
      const DrawPoint(x: 150, y: 100),
      const DrawPoint(x: 200, y: 100),
      const DrawPoint(x: 200, y: 180),
      const DrawPoint(x: 260, y: 180),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 3, start: points[2], end: points[3]),
    ];
    final element = _arrowElement(
      points,
      fixedSegments: fixedSegments,
      startBinding: const ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0.5, y: 0),
      ),
      startArrowhead: ArrowheadStyle.triangle,
    );
    final data = element.data as ArrowData;

    final dragged = <DrawPoint>[
      points.first,
      points[1],
      points[2],
      const DrawPoint(x: 260, y: 200),
    ];

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: {'target': target},
      localPointsOverride: dragged,
      fixedSegmentsOverride: fixedSegments,
    );

    final startPoint = result.localPoints.first;
    final nextPoint = result.localPoints[1];
    expect(
      (startPoint.x - nextPoint.x).abs() <=
          ElbowConstants.intersectionEpsilon,
      isTrue,
    );
    expect(nextPoint.y < startPoint.y, isTrue);
  });

  test('fixed segment release preserves prefix outside released region', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 40),
      const DrawPoint(x: 80, y: 40),
      const DrawPoint(x: 80, y: 80),
      const DrawPoint(x: 160, y: 80),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
      ElbowFixedSegment(index: 4, start: points[3], end: points[4]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: points,
      fixedSegmentsOverride: <ElbowFixedSegment>[fixedSegments[0]],
    );
    expect(result.localPoints.length, greaterThanOrEqualTo(2));
    expect(result.localPoints.first, points.first);
    expect(result.localPoints[1], points[1]);
    expect(result.fixedSegments, isNotNull);
    expect(result.fixedSegments!.length, 1);
    expect(result.localPoints.contains(points[2]), isTrue);
  });

  test('fixed segment release keeps endpoints and orthogonality with only next fixed', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 80, y: 0),
      const DrawPoint(x: 80, y: 40),
      const DrawPoint(x: 160, y: 40),
      const DrawPoint(x: 160, y: 100),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
      ElbowFixedSegment(index: 4, start: points[3], end: points[4]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: points,
      fixedSegmentsOverride: <ElbowFixedSegment>[fixedSegments[1]],
    );
    expect(result.localPoints.length, greaterThanOrEqualTo(2));
    expect(result.localPoints.first, points.first);
    expect(result.localPoints.last, points.last);
    expect(_pathIsOrthogonal(result.localPoints), isTrue);
  });
}

ElementState _arrowElement(
  List<DrawPoint> points, {
  List<ElbowFixedSegment>? fixedSegments,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
  ArrowheadStyle startArrowhead = ArrowheadStyle.none,
  ArrowheadStyle endArrowhead = ArrowheadStyle.none,
}) {
  final rect = _rectForPoints(points);
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  final data = ArrowData(
    points: normalized,
    arrowType: ArrowType.elbow,
    fixedSegments: fixedSegments,
    startBinding: startBinding,
    endBinding: endBinding,
    startArrowhead: startArrowhead,
    endArrowhead: endArrowhead,
  );
  return ElementState(
    id: 'arrow',
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: data,
  );
}

ElementState _rectangleElement({
  required String id,
  required DrawRect rect,
  double strokeWidth = 2,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: RectangleData(strokeWidth: strokeWidth),
);

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

bool _pathIsOrthogonal(List<DrawPoint> points) {
  for (var i = 0; i < points.length - 1; i++) {
    final dx = (points[i].x - points[i + 1].x).abs();
    final dy = (points[i].y - points[i + 1].y).abs();
    if (dx > ElbowConstants.intersectionEpsilon &&
        dy > ElbowConstants.intersectionEpsilon) {
      return false;
    }
  }
  return true;
}

bool _isHorizontal(DrawPoint a, DrawPoint b) =>
    (a.y - b.y).abs() <= (a.x - b.x).abs();

double _segmentAxis(ElbowFixedSegment segment) {
  if (_isHorizontal(segment.start, segment.end)) {
    return (segment.start.y + segment.end.y) / 2;
  }
  return (segment.start.x + segment.end.x) / 2;
}
