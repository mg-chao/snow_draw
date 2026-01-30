import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_editing.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';

void main() {
  test('endpoint drag preserves segment count and fixed segment position', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 100),
      const DrawPoint(x: 200, y: 100),
      const DrawPoint(x: 200, y: 200),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    final movedPoints = List<DrawPoint>.from(points);
    movedPoints[0] = const DrawPoint(x: 50, y: 0);

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
    );

    expect(result.localPoints.length, points.length);
    expect(result.localPoints.first, movedPoints.first);
    expect(result.localPoints[1].x, 50);
    expect(result.localPoints[1].y, 100);
    expect(result.localPoints[2].y, 100);

    final segments = result.fixedSegments;
    expect(segments, isNotNull);
    expect(segments!.length, 1);
    expect(segments.first.index, 2);
    expect(segments.first.start, result.localPoints[1]);
    expect(segments.first.end, result.localPoints[2]);
  });

  test('moving a fixed segment updates its endpoints', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 100),
      const DrawPoint(x: 200, y: 100),
      const DrawPoint(x: 200, y: 200),
    ];
    final element = _arrowElement(points);
    final data = element.data as ArrowData;

    final movedPoints = <DrawPoint>[
      points[0],
      const DrawPoint(x: 0, y: 150),
      const DrawPoint(x: 200, y: 150),
      points[3],
    ];
    final movedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: movedPoints[1], end: movedPoints[2]),
    ];

    final result = computeElbowEdit(
      element: element,
      data: data.copyWith(fixedSegments: movedSegments),
      elementsById: const {},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: movedSegments,
    );

    expect(result.localPoints[1].y, 150);
    expect(result.localPoints[2].y, 150);
    expect(result.localPoints.length, points.length);

    final segments = result.fixedSegments;
    expect(segments, isNotNull);
    expect(segments!.first.start, result.localPoints[1]);
    expect(segments.first.end, result.localPoints[2]);
  });

  test('creating a fixed segment keeps the path unchanged', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 120),
      const DrawPoint(x: 240, y: 120),
      const DrawPoint(x: 240, y: 200),
    ];
    final element = _arrowElement(points);
    final data = element.data as ArrowData;

    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: points,
      fixedSegmentsOverride: fixedSegments,
    );

    expect(result.localPoints, equals(points));
    expect(result.fixedSegments, isNotNull);
    expect(result.fixedSegments!.length, 1);
    expect(result.fixedSegments!.first.start, points[1]);
    expect(result.fixedSegments!.first.end, points[2]);
  });

  test('releasing a fixed segment reroutes only the released region', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 100),
      const DrawPoint(x: 200, y: 100),
      const DrawPoint(x: 200, y: 200),
      const DrawPoint(x: 400, y: 200),
      const DrawPoint(x: 400, y: 300),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
      ElbowFixedSegment(index: 4, start: points[3], end: points[4]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    final remainingSegments = <ElbowFixedSegment>[fixedSegments[1]];

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: points,
      fixedSegmentsOverride: remainingSegments,
    );

    final lastPoint = result.localPoints.last;
    final secondToLast = result.localPoints[result.localPoints.length - 2];
    expect(secondToLast, points[4]);
    expect(lastPoint, points[5]);

    final segments = result.fixedSegments;
    expect(segments, isNotNull);
    expect(segments!.length, 1);
    expect(segments.first.start, points[3]);
    expect(segments.first.end, points[4]);
  });

  test('diagonal fixed segments are rejected', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 100),
      const DrawPoint(x: 200, y: 100),
      const DrawPoint(x: 200, y: 200),
    ];
    final element = _arrowElement(points);
    final data = element.data as ArrowData;

    final invalidSegments = <ElbowFixedSegment>[
      const ElbowFixedSegment(
        index: 2,
        start: DrawPoint(x: 0, y: 100),
        end: DrawPoint(x: 120, y: 140),
      ),
    ];

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: points,
      fixedSegmentsOverride: invalidSegments,
    );

    expect(result.fixedSegments, isNull);
  });

  test('short fixed segments above the dedup threshold are preserved', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 50),
      const DrawPoint(x: 2, y: 50),
      const DrawPoint(x: 2, y: 120),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: points,
      fixedSegmentsOverride: fixedSegments,
    );

    final segments = result.fixedSegments;
    expect(segments, isNotNull);
    expect(segments!.length, 1);
    expect(segments.first.start, points[1]);
    expect(segments.first.end, points[2]);
  });
}

ElementState _arrowElement(
  List<DrawPoint> points, {
  List<ElbowFixedSegment>? fixedSegments,
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

DrawRect _rectForPoints(List<DrawPoint> points) {
  var minX = points.first.x;
  var maxX = points.first.x;
  var minY = points.first.y;
  var maxY = points.first.y;
  for (final point in points.skip(1)) {
    if (point.x < minX) {
      minX = point.x;
    }
    if (point.x > maxX) {
      maxX = point.x;
    }
    if (point.y < minY) {
      minY = point.y;
    }
    if (point.y > maxY) {
      maxY = point.y;
    }
  }
  if (minX == maxX) {
    maxX = minX + 1;
  }
  if (minY == maxY) {
    maxY = minY + 1;
  }
  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}
