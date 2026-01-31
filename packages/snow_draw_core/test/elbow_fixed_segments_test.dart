import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_editing.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
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

  test(
    'fixed middle segment inserts a transition to keep bound endpoint '
    'perpendicular',
    () {
      final points = <DrawPoint>[
        const DrawPoint(x: 0, y: 0),
        const DrawPoint(x: 0, y: 100),
        const DrawPoint(x: 200, y: 100),
        const DrawPoint(x: 200, y: 50),
      ];
      final fixedSegments = <ElbowFixedSegment>[
        ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
      ];
      final element = _arrowElement(points, fixedSegments: fixedSegments);
      final data = element.data as ArrowData;

      const rect = DrawRect(minX: 300, minY: 200, maxX: 360, maxY: 260);
      final boundElement = _rectangleElement(id: 'rect-1', rect: rect);
      const binding = ArrowBinding(
        elementId: 'rect-1',
        anchor: DrawPoint(x: 1, y: 0.5),
      );
      final boundPoint =
          ArrowBindingUtils.resolveElbowBoundPoint(
            binding: binding,
            target: boundElement,
            hasArrowhead: false,
          ) ??
          points.last;

      final movedPoints = List<DrawPoint>.from(points);
      movedPoints[movedPoints.length - 1] = boundPoint;

      final result = computeElbowEdit(
        element: element,
        data: data.copyWith(endBinding: binding),
        elementsById: {'rect-1': boundElement},
        localPointsOverride: movedPoints,
        fixedSegmentsOverride: fixedSegments,
        endBindingOverride: binding,
      );

      final penultimate = result.localPoints[result.localPoints.length - 2];
      final endPoint = result.localPoints.last;
      expect(
        (penultimate.y - endPoint.y).abs() <= 1,
        isTrue,
        reason: 'End segment should be horizontal toward the bound element.',
      );
      expect(
        result.localPoints.length,
        greaterThanOrEqualTo(5),
        reason: 'Expected transition points for perpendicular entry.',
      );
      expect(
        result.localPoints[2].y,
        100,
        reason: 'Fixed segment should stay on its original line.',
      );
      final segments = result.fixedSegments;
      expect(segments, isNotNull);
      expect(segments!.length, 1);
      final fixed = segments.first;
      expect(fixed.start, result.localPoints[fixed.index - 1]);
      expect(fixed.end, result.localPoints[fixed.index]);
    },
  );

  test('fixed segment keeps bottom binding approach direction correct', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 100),
      const DrawPoint(x: 200, y: 100),
      const DrawPoint(x: 200, y: 150),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    const rect = DrawRect(minX: 150, minY: 200, maxX: 250, maxY: 260);
    final boundElement = _rectangleElement(id: 'rect-1', rect: rect);
    const binding = ArrowBinding(
      elementId: 'rect-1',
      anchor: DrawPoint(x: 0.5, y: 1),
    );
    final boundPoint =
        ArrowBindingUtils.resolveElbowBoundPoint(
          binding: binding,
          target: boundElement,
          hasArrowhead: false,
        ) ??
        points.last;

    final movedPoints = List<DrawPoint>.from(points);
    movedPoints[movedPoints.length - 1] = boundPoint;

    final result = computeElbowEdit(
      element: element,
      data: data.copyWith(endBinding: binding),
      elementsById: {'rect-1': boundElement},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
      endBindingOverride: binding,
    );

    final penultimate = result.localPoints[result.localPoints.length - 2];
    final endPoint = result.localPoints.last;
    expect(
      (penultimate.x - endPoint.x).abs() <= 1,
      isTrue,
      reason: 'End segment should be vertical toward the bottom binding.',
    );
    expect(
      penultimate.y > endPoint.y,
      isTrue,
      reason: 'Bottom binding should approach from below.',
    );
  });

  test(
    'aligned bound end extends fixed segment instead of adding a collinear one',
    () {
      final points = <DrawPoint>[
        const DrawPoint(x: 0, y: 0),
        const DrawPoint(x: 0, y: 100),
        const DrawPoint(x: 200, y: 100),
        const DrawPoint(x: 300, y: 100),
      ];
      final fixedSegments = <ElbowFixedSegment>[
        ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
      ];
      final element = _arrowElement(points, fixedSegments: fixedSegments);
      final data = element.data as ArrowData;

      const rect = DrawRect(minX: 240, minY: 80, maxX: 260, maxY: 120);
      final boundElement = _rectangleElement(id: 'rect-1', rect: rect);
      const binding = ArrowBinding(
        elementId: 'rect-1',
        anchor: DrawPoint(x: 1, y: 0.5),
      );
      final boundPoint =
          ArrowBindingUtils.resolveElbowBoundPoint(
            binding: binding,
            target: boundElement,
            hasArrowhead: false,
          ) ??
          points.last;

      final movedPoints = List<DrawPoint>.from(points);
      movedPoints[movedPoints.length - 1] = boundPoint;

      final result = computeElbowEdit(
        element: element,
        data: data.copyWith(endBinding: binding),
        elementsById: {'rect-1': boundElement},
        localPointsOverride: movedPoints,
        fixedSegmentsOverride: fixedSegments,
        endBindingOverride: binding,
      );

      expect(
        result.localPoints.length,
        points.length,
        reason: 'Should extend the fixed segment instead of adding a new one.',
      );
      final neighbor = result.localPoints[result.localPoints.length - 2];
      final endPoint = result.localPoints.last;
      expect(
        neighbor.x,
        greaterThan(endPoint.x),
        reason: 'End should approach from the right for right-side binding.',
      );
    },
  );

  test('fixed segment keeps bound endpoint spacing consistent', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 100),
      const DrawPoint(x: 200, y: 100),
      const DrawPoint(x: 200, y: 50),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    const rect = DrawRect(minX: 300, minY: 200, maxX: 360, maxY: 260);
    final boundElement = _rectangleElement(id: 'rect-1', rect: rect);
    const binding = ArrowBinding(
      elementId: 'rect-1',
      anchor: DrawPoint(x: 1, y: 0.5),
    );
    final boundPoint =
        ArrowBindingUtils.resolveElbowBoundPoint(
          binding: binding,
          target: boundElement,
          hasArrowhead: data.endArrowhead != ArrowheadStyle.none,
        ) ??
        points.last;

    final movedPoints = List<DrawPoint>.from(points);
    movedPoints[movedPoints.length - 1] = boundPoint;

    final baseline = routeElbowArrow(
      start: movedPoints.first,
      end: boundPoint,
      startBinding: null,
      endBinding: binding,
      elementsById: {'rect-1': boundElement},
      startArrowhead: data.startArrowhead,
      endArrowhead: data.endArrowhead,
    ).points;

    expect(
      baseline.length,
      greaterThanOrEqualTo(3),
      reason: 'Expected a routed path with at least one turn.',
    );

    final result = computeElbowEdit(
      element: element,
      data: data.copyWith(endBinding: binding),
      elementsById: {'rect-1': boundElement},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
      endBindingOverride: binding,
    );

    final baselinePadding = _manhattanDistance(
      baseline[baseline.length - 2],
      baseline.last,
    );
    final actualPadding = _manhattanDistance(
      result.localPoints[result.localPoints.length - 2],
      result.localPoints.last,
    );

    expect(
      (actualPadding - baselinePadding).abs() <= 1,
      isTrue,
      reason: 'End spacing should match the non-fixed routed path.',
    );
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

double _manhattanDistance(DrawPoint a, DrawPoint b) =>
    (a.x - b.x).abs() + (a.y - b.y).abs();

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
