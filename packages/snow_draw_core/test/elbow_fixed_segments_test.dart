import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_editing.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'elbow_test_utils.dart';

void main() {
  test('endpoint drag preserves segment count and fixed segment direction', () {
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

    final segments = result.fixedSegments;
    expect(segments, isNotNull);
    expect(segments!.length, 1);
    final fixed = segments.first;
    expect(fixed.index, 2);
    expect(_isHorizontal(fixed.start, fixed.end), isTrue);
    expect(fixed.start, result.localPoints[fixed.index - 1]);
    expect(fixed.end, result.localPoints[fixed.index]);
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
    final fixed = segments!.first;
    expect(_isHorizontal(fixed.start, fixed.end), isTrue);
    expect(fixed.start, result.localPoints[1]);
    expect(fixed.end, result.localPoints[2]);
  });

  test('fixed segment keeps its horizontal axis when points drift', () {
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

    final movedPoints = <DrawPoint>[
      points[0],
      const DrawPoint(x: 0, y: 150),
      const DrawPoint(x: 200, y: 150),
      points[3],
    ];

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
    );

    expect(
      (result.localPoints[1].y - 100).abs() <= 1,
      isTrue,
      reason: 'Fixed segment should stay on its original horizontal axis.',
    );
    expect(
      (result.localPoints[2].y - 100).abs() <= 1,
      isTrue,
      reason: 'Fixed segment should stay on its original horizontal axis.',
    );
  });

  test('fixed segment keeps its vertical axis when points drift', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 100, y: 0),
      const DrawPoint(x: 100, y: 200),
      const DrawPoint(x: 200, y: 200),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    final movedPoints = <DrawPoint>[
      points[0],
      const DrawPoint(x: 150, y: 0),
      const DrawPoint(x: 150, y: 200),
      points[3],
    ];

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
    );

    expect(
      (result.localPoints[1].x - 100).abs() <= 1,
      isTrue,
      reason: 'Fixed segment should stay on its original vertical axis.',
    );
    expect(
      (result.localPoints[2].x - 100).abs() <= 1,
      isTrue,
      reason: 'Fixed segment should stay on its original vertical axis.',
    );
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
    final fixed = segments.first;
    expect(_isHorizontal(fixed.start, fixed.end), isTrue);
    expect(fixed.start, result.localPoints[fixed.index - 1]);
    expect(fixed.end, result.localPoints[fixed.index]);
  });

  test('releasing a fixed segment merges collinear neighbor segments', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 100),
      const DrawPoint(x: 200, y: 100),
      const DrawPoint(x: 200, y: 200),
      const DrawPoint(x: 300, y: 200),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
      ElbowFixedSegment(index: 3, start: points[2], end: points[3]),
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
    // debug: print(result.localPoints);

    expect(result.fixedSegments, isNotNull);
    expect(result.fixedSegments!.length, 1);
    expect(_hasDiagonalSegments(result.localPoints), isFalse);
    expect(
      result.localPoints.length,
      4,
      reason: 'Expected released collinear segments to merge.',
    );

    final fixed = result.fixedSegments!.first;
    expect(_isHorizontal(fixed.start, fixed.end), isFalse);
    expect(fixed.start, result.localPoints[fixed.index - 1]);
    expect(fixed.end, result.localPoints[fixed.index]);
    expect((fixed.start.x - 200).abs() <= 1, isTrue);
    expect((fixed.end.x - 200).abs() <= 1, isTrue);
  });

  test('releasing a fixed segment avoids extra elbow detours', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 200, y: 0),
      const DrawPoint(x: 200, y: 200),
      const DrawPoint(x: 400, y: 200),
      const DrawPoint(x: 400, y: 0),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
      ElbowFixedSegment(index: 3, start: points[2], end: points[3]),
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

    expect(
      result.localPoints.length,
      4,
      reason: 'Released segment should collapse to a 3-segment path.',
    );
    expect(
      _hasDiagonalSegments(result.localPoints),
      isFalse,
      reason: 'Released path should remain orthogonal.',
    );

    final fixed = result.fixedSegments!.first;
    expect(_isHorizontal(fixed.start, fixed.end), isTrue);
    expect((fixed.start.y - 200).abs() <= 1, isTrue);
    expect((fixed.end.y - 200).abs() <= 1, isTrue);
    expect(result.localPoints.first, points.first);
    expect(result.localPoints.last, points.last);
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
      final boundElement = elbowRectangleElement(id: 'rect-1', rect: rect);
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
      final segments = result.fixedSegments;
      expect(segments, isNotNull);
      expect(segments!.length, 1);
      final fixed = segments.first;
      expect(_isHorizontal(fixed.start, fixed.end), isTrue);
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
    final boundElement = elbowRectangleElement(id: 'rect-1', rect: rect);
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
    'aligned bound end keeps approach direction with fixed segment',
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
      final boundElement = elbowRectangleElement(id: 'rect-1', rect: rect);
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

      final neighbor = result.localPoints[result.localPoints.length - 2];
      final endPoint = result.localPoints.last;
      expect(
        neighbor.x,
        greaterThan(endPoint.x),
        reason: 'End should approach from the right for right-side binding.',
      );
      final fixed = result.fixedSegments!.first;
      expect(_isHorizontal(fixed.start, fixed.end), isTrue);
    },
  );

  test('bound end maps fixed segment direction to baseline route', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 80),
      const DrawPoint(x: 30, y: 80),
      const DrawPoint(x: 30, y: 160),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    const rect = DrawRect(minX: 800, minY: 200, maxX: 860, maxY: 260);
    final boundElement = elbowRectangleElement(id: 'rect-1', rect: rect);
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

    final baseline = routeElbowArrow(
      start: movedPoints.first,
      end: boundPoint,
      startBinding: null,
      endBinding: binding,
      elementsById: {'rect-1': boundElement},
      startArrowhead: data.startArrowhead,
      endArrowhead: data.endArrowhead,
    ).points;

    final result = computeElbowEdit(
      element: element,
      data: data.copyWith(endBinding: binding),
      elementsById: {'rect-1': boundElement},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
      endBindingOverride: binding,
    );

    final fixed = result.fixedSegments!.first;
    final isHorizontal = _isHorizontal(fixed.start, fixed.end);
    final baselineIndex = _closestBaselineSegmentIndex(
      baseline,
      isHorizontal: isHorizontal,
      preferredIndex: fixed.index,
    );
    expect(baselineIndex, isNotNull);
  });

  test('bound start maps fixed segment direction to baseline route', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 200, y: 300),
      const DrawPoint(x: 200, y: 220),
      const DrawPoint(x: 120, y: 220),
      const DrawPoint(x: 120, y: 140),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    const rect = DrawRect(minX: -900, minY: 260, maxX: -840, maxY: 320);
    final boundElement = elbowRectangleElement(id: 'rect-1', rect: rect);
    const binding = ArrowBinding(
      elementId: 'rect-1',
      anchor: DrawPoint(x: 0, y: 0.5),
    );
    final boundPoint =
        ArrowBindingUtils.resolveElbowBoundPoint(
          binding: binding,
          target: boundElement,
          hasArrowhead: false,
        ) ??
        points.first;

    final movedPoints = List<DrawPoint>.from(points);
    movedPoints[0] = boundPoint;

    final baseline = routeElbowArrow(
      start: boundPoint,
      end: movedPoints.last,
      startBinding: binding,
      endBinding: null,
      elementsById: {'rect-1': boundElement},
      startArrowhead: data.startArrowhead,
      endArrowhead: data.endArrowhead,
    ).points;

    final result = computeElbowEdit(
      element: element,
      data: data.copyWith(startBinding: binding),
      elementsById: {'rect-1': boundElement},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
      startBindingOverride: binding,
    );

    final fixed = result.fixedSegments!.first;
    final isHorizontal = _isHorizontal(fixed.start, fixed.end);
    final baselineIndex = _closestBaselineSegmentIndex(
      baseline,
      isHorizontal: isHorizontal,
      preferredIndex: fixed.index,
    );
    expect(baselineIndex, isNotNull);
  });

  test('unbinding removes diagonal segment after bound routing', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 80),
      const DrawPoint(x: 120, y: 80),
      const DrawPoint(x: 120, y: 160),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    const rect = DrawRect(minX: 500, minY: 200, maxX: 560, maxY: 260);
    final boundElement = elbowRectangleElement(id: 'rect-1', rect: rect);
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

    final boundResult = computeElbowEdit(
      element: element,
      data: data.copyWith(endBinding: binding),
      elementsById: {'rect-1': boundElement},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
      endBindingOverride: binding,
    );
    expect(boundResult.fixedSegments, isNotNull);
    final boundFixed = boundResult.fixedSegments!.first;
    expect(boundFixed.index, greaterThan(1));
    expect(
      boundFixed.index + 1,
      lessThan(boundResult.localPoints.length),
    );

    final unboundResult = computeElbowEdit(
      element: element,
      data: data.copyWith(endBinding: null),
      elementsById: {'rect-1': boundElement},
      localPointsOverride: boundResult.localPoints,
      fixedSegmentsOverride: boundResult.fixedSegments,
      endBindingOverride: null,
    );
    expect(unboundResult.fixedSegments, isNotNull);
    final unboundFixed = unboundResult.fixedSegments!.first;
    expect(
      _isHorizontal(unboundFixed.start, unboundFixed.end),
      _isHorizontal(boundFixed.start, boundFixed.end),
    );
    expect(unboundFixed.index, greaterThan(1));
    expect(
      unboundFixed.index + 1,
      lessThan(unboundResult.localPoints.length),
    );

    expect(
      _hasDiagonalSegments(unboundResult.localPoints),
      isFalse,
      reason: 'Unbound elbow paths should remain orthogonal.',
    );
  });

  test('unbound endpoint snaps near-collinear segment to orthogonal', () {
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
    movedPoints[movedPoints.length - 1] = const DrawPoint(x: 240, y: 102);

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
    );

    expect(
      _hasDiagonalSegments(result.localPoints),
      isFalse,
      reason: 'Unbound elbow paths should stay orthogonal.',
    );

    final fixed = result.fixedSegments!.first;
    expect(
      (fixed.start.y - fixed.end.y).abs() <= 1,
      isTrue,
      reason: 'Fixed segment should remain horizontal.',
    );
  });

  test('unbound end respects adjacent fixed segment direction when near axis',
      () {
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
    movedPoints[movedPoints.length - 1] =
        const DrawPoint(x: 240, y: 100.5);

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
    );

    final fixed = result.fixedSegments!.first;
    expect(_isHorizontal(fixed.start, fixed.end), isTrue);

    final neighbor = result.localPoints[result.localPoints.length - 2];
    final endPoint = result.localPoints.last;
    expect(
      neighbor.x,
      endPoint.x,
      reason: 'End segment should be vertical off the horizontal fixed axis.',
    );
  });

  test(
    'unbound start respects adjacent fixed segment direction when near axis',
    () {
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
      movedPoints[0] = const DrawPoint(x: -40, y: 100.5);

      final result = computeElbowEdit(
        element: element,
        data: data,
        elementsById: const {},
        localPointsOverride: movedPoints,
        fixedSegmentsOverride: fixedSegments,
      );

      final fixed = result.fixedSegments!.first;
      expect(_isHorizontal(fixed.start, fixed.end), isTrue);

      final start = result.localPoints.first;
      final neighbor = result.localPoints[1];
      expect(
        neighbor.x,
        start.x,
        reason: 'Start segment should be vertical off the horizontal axis.',
      );
    },
  );

  test(
    'unbound end respects vertical fixed segment direction when near axis',
    () {
      final points = <DrawPoint>[
        const DrawPoint(x: 0, y: 0),
        const DrawPoint(x: 100, y: 0),
        const DrawPoint(x: 100, y: 200),
        const DrawPoint(x: 200, y: 200),
      ];
      final fixedSegments = <ElbowFixedSegment>[
        ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
      ];
      final element = _arrowElement(points, fixedSegments: fixedSegments);
      final data = element.data as ArrowData;

      final movedPoints = List<DrawPoint>.from(points);
      movedPoints[movedPoints.length - 1] =
          const DrawPoint(x: 100.5, y: 260);

      final result = computeElbowEdit(
        element: element,
        data: data,
        elementsById: const {},
        localPointsOverride: movedPoints,
        fixedSegmentsOverride: fixedSegments,
      );

      final fixed = result.fixedSegments!.first;
      expect(_isHorizontal(fixed.start, fixed.end), isFalse);

      final neighbor = result.localPoints[result.localPoints.length - 2];
      final endPoint = result.localPoints.last;
      expect(
        neighbor.y,
        endPoint.y,
        reason: 'End segment should be horizontal off the vertical axis.',
      );
    },
  );

  test(
    'unbound start respects vertical fixed segment direction when near axis',
    () {
      final points = <DrawPoint>[
        const DrawPoint(x: 0, y: 0),
        const DrawPoint(x: 100, y: 0),
        const DrawPoint(x: 100, y: 200),
        const DrawPoint(x: 200, y: 200),
      ];
      final fixedSegments = <ElbowFixedSegment>[
        ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
      ];
      final element = _arrowElement(points, fixedSegments: fixedSegments);
      final data = element.data as ArrowData;

      final movedPoints = List<DrawPoint>.from(points);
      movedPoints[0] = const DrawPoint(x: 100.5, y: -40);

      final result = computeElbowEdit(
        element: element,
        data: data,
        elementsById: const {},
        localPointsOverride: movedPoints,
        fixedSegmentsOverride: fixedSegments,
      );

      final fixed = result.fixedSegments!.first;
      expect(_isHorizontal(fixed.start, fixed.end), isFalse);

      final start = result.localPoints.first;
      final neighbor = result.localPoints[1];
      expect(
        neighbor.y,
        start.y,
        reason: 'Start segment should be horizontal off the vertical axis.',
      );
    },
  );

  test('collinear unbound end keeps fixed segment direction', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 50),
      const DrawPoint(x: 100, y: 50),
      const DrawPoint(x: 200, y: 50),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    final movedPoints = List<DrawPoint>.from(points);
    movedPoints[movedPoints.length - 1] = const DrawPoint(x: 260, y: 50);

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
    );

    final fixed = result.fixedSegments!.first;
    expect(_isHorizontal(fixed.start, fixed.end), isTrue);
    expect(_hasDiagonalSegments(result.localPoints), isFalse);
    final endSegmentHorizontal = _isHorizontal(
      result.localPoints[result.localPoints.length - 2],
      result.localPoints.last,
    );
    expect(endSegmentHorizontal, isTrue);
  });

  test('end drag keeps fixed segment direction with perpendicular hop', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 0, y: 100),
      const DrawPoint(x: 200, y: 100),
      const DrawPoint(x: 200, y: 0),
      const DrawPoint(x: 400, y: 0),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    final movedPoints = List<DrawPoint>.from(points);
    movedPoints[movedPoints.length - 1] = const DrawPoint(x: 600, y: 0);

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
    );

    final fixed = result.fixedSegments!.first;
    expect(_isHorizontal(fixed.start, fixed.end), isTrue);
    expect(_hasDiagonalSegments(result.localPoints), isFalse);
    expect(
      result.localPoints[2].x,
      result.localPoints[3].x,
      reason: 'Perpendicular segment should stay vertical after shifting.',
    );
  });

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
    final boundElement = elbowRectangleElement(id: 'rect-1', rect: rect);
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

  test('bound end preserves prefix before fixed segment', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 200, y: 0),
      const DrawPoint(x: 200, y: 200),
      const DrawPoint(x: 100, y: 200),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    final unbound = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: points,
      fixedSegmentsOverride: fixedSegments,
    );
    expect(unbound.fixedSegments, isNotNull);
    final unboundFixed = unbound.fixedSegments!.first;
    final unboundPrefix = _prefixThroughPoint(
      unbound.localPoints,
      unboundFixed.start,
    );

    const rect = DrawRect(minX: 80, minY: 550, maxX: 120, maxY: 650);
    final boundElement = elbowRectangleElement(id: 'rect-1', rect: rect);
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

    final bound = computeElbowEdit(
      element: element,
      data: data.copyWith(endBinding: binding),
      elementsById: {'rect-1': boundElement},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
      endBindingOverride: binding,
    );
    expect(bound.fixedSegments, isNotNull);
    final boundFixed = bound.fixedSegments!.first;
    final boundPrefix = _prefixThroughPoint(
      bound.localPoints,
      boundFixed.start,
    );

    _expectPointSequenceClose(
      boundPrefix,
      unboundPrefix,
      reason: 'Prefix before fixed segment should stay stable.',
    );

    final baseline = routeElbowArrow(
      start: movedPoints.first,
      end: boundPoint,
      startBinding: null,
      endBinding: binding,
      elementsById: {'rect-1': boundElement},
      startArrowhead: data.startArrowhead,
      endArrowhead: data.endArrowhead,
    ).points;
    if (baseline.length > 1 &&
        !elbowPointsClose(baseline[1], unboundPrefix[1])) {
      expect(
        elbowPointsClose(boundPrefix[1], baseline[1]),
        isFalse,
        reason: 'Prefix should not adopt the bound baseline route.',
      );
    }
  });

  test('bound start preserves suffix after fixed segment', () {
    final points = <DrawPoint>[
      const DrawPoint(x: 0, y: 0),
      const DrawPoint(x: 200, y: 0),
      const DrawPoint(x: 200, y: 200),
      const DrawPoint(x: 100, y: 200),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
    ];
    final element = _arrowElement(points, fixedSegments: fixedSegments);
    final data = element.data as ArrowData;

    final unbound = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: points,
      fixedSegmentsOverride: fixedSegments,
    );
    expect(unbound.fixedSegments, isNotNull);
    final unboundFixed = unbound.fixedSegments!.first;
    final unboundSuffix = _suffixFromPoint(
      unbound.localPoints,
      unboundFixed.end,
    );

    const rect = DrawRect(minX: -220, minY: -40, maxX: -140, maxY: 40);
    final boundElement = elbowRectangleElement(id: 'rect-1', rect: rect);
    const binding = ArrowBinding(
      elementId: 'rect-1',
      anchor: DrawPoint(x: 0, y: 0.5),
    );
    final boundPoint =
        ArrowBindingUtils.resolveElbowBoundPoint(
          binding: binding,
          target: boundElement,
          hasArrowhead: false,
        ) ??
        points.first;

    final movedPoints = List<DrawPoint>.from(points);
    movedPoints[0] = boundPoint;

    final bound = computeElbowEdit(
      element: element,
      data: data.copyWith(startBinding: binding),
      elementsById: {'rect-1': boundElement},
      localPointsOverride: movedPoints,
      fixedSegmentsOverride: fixedSegments,
      startBindingOverride: binding,
    );
    expect(bound.fixedSegments, isNotNull);
    final boundFixed = bound.fixedSegments!.first;
    final boundSuffix = _suffixFromPoint(
      bound.localPoints,
      boundFixed.end,
    );

    _expectPointSequenceClose(
      boundSuffix,
      unboundSuffix,
      reason: 'Suffix after fixed segment should stay stable.',
    );

    final baseline = routeElbowArrow(
      start: boundPoint,
      end: movedPoints.last,
      startBinding: binding,
      endBinding: null,
      elementsById: {'rect-1': boundElement},
      startArrowhead: data.startArrowhead,
      endArrowhead: data.endArrowhead,
    ).points;
    if (baseline.length > 1 &&
        !elbowPointsClose(
          baseline[baseline.length - 2],
          unboundSuffix[unboundSuffix.length - 2],
        )) {
      expect(
        elbowPointsClose(
          boundSuffix[boundSuffix.length - 2],
          baseline[baseline.length - 2],
        ),
        isFalse,
        reason: 'Suffix should not adopt the bound baseline route.',
      );
    }
  });
}

ElementState _arrowElement(
  List<DrawPoint> points, {
  List<ElbowFixedSegment>? fixedSegments,
}) {
  final rect = elbowRectForPoints(points);
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

double _manhattanDistance(DrawPoint a, DrawPoint b) =>
    (a.x - b.x).abs() + (a.y - b.y).abs();

bool _isHorizontal(DrawPoint a, DrawPoint b) =>
    (a.y - b.y).abs() <= (a.x - b.x).abs();

bool _hasDiagonalSegments(List<DrawPoint> points) {
  if (points.length < 2) {
    return false;
  }
  for (var i = 1; i < points.length; i++) {
    final dx = (points[i].x - points[i - 1].x).abs();
    final dy = (points[i].y - points[i - 1].y).abs();
    if (dx > 1 && dy > 1) {
      return true;
    }
  }
  return false;
}

int? _closestBaselineSegmentIndex(
  List<DrawPoint> baseline, {
  required bool isHorizontal,
  required int preferredIndex,
}) {
  if (baseline.length < 2) {
    return null;
  }
  int? bestIndex;
  var bestIndexDelta = double.infinity;
  for (var i = 1; i < baseline.length; i++) {
    if (_isHorizontal(baseline[i - 1], baseline[i]) != isHorizontal) {
      continue;
    }
    final indexDelta = (i - preferredIndex).abs().toDouble();
    if (indexDelta < bestIndexDelta) {
      bestIndexDelta = indexDelta;
      bestIndex = i;
    }
  }
  return bestIndex;
}

int _indexOfPoint(List<DrawPoint> points, DrawPoint target) {
  for (var i = 0; i < points.length; i++) {
    if (elbowPointsClose(points[i], target)) {
      return i;
    }
  }
  return -1;
}

List<DrawPoint> _prefixThroughPoint(
  List<DrawPoint> points,
  DrawPoint target,
) {
  final index = _indexOfPoint(points, target);
  expect(index, isNot(-1));
  return points.sublist(0, index + 1);
}

List<DrawPoint> _suffixFromPoint(
  List<DrawPoint> points,
  DrawPoint target,
) {
  final index = _indexOfPoint(points, target);
  expect(index, isNot(-1));
  return points.sublist(index);
}

void _expectPointSequenceClose(
  List<DrawPoint> actual,
  List<DrawPoint> expected, {
  String? reason,
}) {
  expect(actual.length, expected.length, reason: reason);
  final baseReason = reason ?? 'Point sequence mismatch.';
  for (var i = 0; i < expected.length; i++) {
    expect(
      elbowPointsClose(actual[i], expected[i]),
      isTrue,
      reason: '$baseReason (point $i).',
    );
  }
}

