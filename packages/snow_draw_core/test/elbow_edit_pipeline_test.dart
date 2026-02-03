import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_editing.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'elbow_test_utils.dart';

void main() {
  test('computeElbowEdit reroutes diagonal input when no fixed segments', () {
    final points = <DrawPoint>[DrawPoint.zero, const DrawPoint(x: 120, y: 80)];
    final element = _arrowElement(points);
    final data = element.data as ArrowData;

    final result = computeElbowEdit(
      element: element,
      data: data,
      elementsById: const {},
      localPointsOverride: points,
    );

    expect(result.localPoints.length, greaterThan(2));
    expect(elbowPathIsOrthogonal(result.localPoints), isTrue);
  });

  test('fixed segment release preserves remaining axis', () {
    final points = <DrawPoint>[
      DrawPoint.zero,
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
    expect(elbowPathIsOrthogonal(result.localPoints), isTrue);

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
      DrawPoint.zero,
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
    expect(elbowPathIsOrthogonal(result.localPoints), isTrue);

    final fixed = result.fixedSegments!.first;
    expect(_isHorizontal(fixed.start, fixed.end), isFalse);
    final axis = (fixed.start.x + fixed.end.x) / 2;
    expect((axis - 100).abs() <= ElbowConstants.dedupThreshold, isTrue);
  });

  test('binding edits keep a perpendicular start segment', () {
    const targetRect = DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200);
    final target = elbowRectangleElement(id: 'target', rect: targetRect);

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

    expect(elbowPathIsOrthogonal(result.localPoints), isTrue);

    final startPoint = result.localPoints.first;
    final nextPoint = result.localPoints[1];
    expect(
      (startPoint.x - nextPoint.x).abs() <= ElbowConstants.intersectionEpsilon,
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
    final target = elbowRectangleElement(id: 'target', rect: targetRect);

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

    expect(elbowPathIsOrthogonal(result.localPoints), isTrue);

    final penultimate = result.localPoints[result.localPoints.length - 2];
    final endPoint = result.localPoints.last;
    expect(
      (penultimate.y - endPoint.y).abs() <= ElbowConstants.intersectionEpsilon,
      isTrue,
      reason: 'Right binding should approach horizontally.',
    );
    expect(
      penultimate.x > endPoint.x,
      isTrue,
      reason: 'Right binding should approach from the right.',
    );
  });

  test('binding switch resets active end span', () {
    const targetRect = DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200);
    final target = elbowRectangleElement(id: 'target', rect: targetRect);

    final basePoints = <DrawPoint>[
      const DrawPoint(x: 0, y: 40),
      const DrawPoint(x: 80, y: 40),
      const DrawPoint(x: 80, y: 80),
      const DrawPoint(x: 160, y: 80),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: basePoints[1], end: basePoints[2]),
    ];
    final element = _arrowElement(
      basePoints,
      fixedSegments: fixedSegments,
      endArrowhead: ArrowheadStyle.triangle,
    );
    final data = element.data as ArrowData;

    const bottomBinding = ArrowBinding(
      elementId: 'target',
      anchor: DrawPoint(x: 0.8, y: 1),
    );
    final bottomPoint = ArrowBindingUtils.resolveElbowBoundPoint(
      binding: bottomBinding,
      target: target,
      hasArrowhead: true,
    )!;
    final toBottom = List<DrawPoint>.from(basePoints)
      ..[basePoints.length - 1] = bottomPoint;

    final bottomResult = computeElbowEdit(
      element: element,
      data: data.copyWith(endBinding: bottomBinding),
      elementsById: {'target': target},
      localPointsOverride: toBottom,
      fixedSegmentsOverride: fixedSegments,
      endBindingOverride: bottomBinding,
    );

    final bottomElement = _arrowElement(
      bottomResult.localPoints,
      fixedSegments: bottomResult.fixedSegments,
      endBinding: bottomBinding,
      endArrowhead: ArrowheadStyle.triangle,
    );
    final bottomData = bottomElement.data as ArrowData;

    const topBinding = ArrowBinding(
      elementId: 'target',
      anchor: DrawPoint(x: 0.8, y: 0),
    );
    final topPoint = ArrowBindingUtils.resolveElbowBoundPoint(
      binding: topBinding,
      target: target,
      hasArrowhead: true,
    )!;
    final toTop = List<DrawPoint>.from(bottomResult.localPoints)
      ..[bottomResult.localPoints.length - 1] = topPoint;

    final topResult = computeElbowEdit(
      element: bottomElement,
      data: bottomData.copyWith(endBinding: topBinding),
      elementsById: {'target': target},
      localPointsOverride: toTop,
      fixedSegmentsOverride: bottomResult.fixedSegments,
      endBindingOverride: topBinding,
    );

    expect(elbowPathIsOrthogonal(topResult.localPoints), isTrue);
    expect(elbowPathHasOnlyCorners(topResult.localPoints), isTrue);
    expect(topResult.localPoints.length, lessThanOrEqualTo(5));

    final penultimate = topResult.localPoints[topResult.localPoints.length - 2];
    final endPoint = topResult.localPoints.last;
    expect(
      (penultimate.x - endPoint.x).abs() <= ElbowConstants.dedupThreshold,
      isTrue,
    );
    expect(
      penultimate.y < endPoint.y,
      isTrue,
      reason: 'Top binding should approach downward.',
    );

    final fixed = topResult.fixedSegments!.first;
    final axis = (fixed.start.x + fixed.end.x) / 2;
    expect(
      (axis - basePoints[1].x).abs() <= ElbowConstants.dedupThreshold,
      isTrue,
    );
  });

  test(
    'binding switch resets active end span with multiple fixed segments',
    () {
      const targetRect = DrawRect(minX: 100, minY: 200, maxX: 200, maxY: 300);
      final target = elbowRectangleElement(id: 'target', rect: targetRect);

      final basePoints = <DrawPoint>[
        const DrawPoint(x: 0, y: 40),
        const DrawPoint(x: 80, y: 40),
        const DrawPoint(x: 80, y: 100),
        const DrawPoint(x: 160, y: 100),
        const DrawPoint(x: 160, y: 60),
        const DrawPoint(x: 220, y: 60),
      ];
      final fixedSegments = <ElbowFixedSegment>[
        ElbowFixedSegment(index: 2, start: basePoints[1], end: basePoints[2]),
        ElbowFixedSegment(index: 4, start: basePoints[3], end: basePoints[4]),
      ];
      final element = _arrowElement(
        basePoints,
        fixedSegments: fixedSegments,
        endArrowhead: ArrowheadStyle.triangle,
      );
      final data = element.data as ArrowData;

      const bottomBinding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0.8, y: 1),
      );
      final bottomPoint = ArrowBindingUtils.resolveElbowBoundPoint(
        binding: bottomBinding,
        target: target,
        hasArrowhead: true,
      )!;
      final toBottom = List<DrawPoint>.from(basePoints)
        ..[basePoints.length - 1] = bottomPoint;

      final bottomResult = computeElbowEdit(
        element: element,
        data: data.copyWith(endBinding: bottomBinding),
        elementsById: {'target': target},
        localPointsOverride: toBottom,
        fixedSegmentsOverride: fixedSegments,
        endBindingOverride: bottomBinding,
      );

      final bottomElement = _arrowElement(
        bottomResult.localPoints,
        fixedSegments: bottomResult.fixedSegments,
        endBinding: bottomBinding,
        endArrowhead: ArrowheadStyle.triangle,
      );
      final bottomData = bottomElement.data as ArrowData;

      const topBinding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0.8, y: 0),
      );
      final topPoint = ArrowBindingUtils.resolveElbowBoundPoint(
        binding: topBinding,
        target: target,
        hasArrowhead: true,
      )!;
      final toTop = List<DrawPoint>.from(bottomResult.localPoints)
        ..[bottomResult.localPoints.length - 1] = topPoint;

      final topResult = computeElbowEdit(
        element: bottomElement,
        data: bottomData.copyWith(endBinding: topBinding),
        elementsById: {'target': target},
        localPointsOverride: toTop,
        fixedSegmentsOverride: bottomResult.fixedSegments,
        endBindingOverride: topBinding,
      );

      expect(elbowPathIsOrthogonal(topResult.localPoints), isTrue);
      expect(topResult.localPoints.length, lessThanOrEqualTo(8));

      final penultimate =
          topResult.localPoints[topResult.localPoints.length - 2];
      final endPoint = topResult.localPoints.last;
      expect(
        (penultimate.x - endPoint.x).abs() <= ElbowConstants.dedupThreshold,
        isTrue,
      );
      expect(
        penultimate.y < endPoint.y,
        isTrue,
        reason: 'Top binding should approach downward.',
      );

      final fixed = topResult.fixedSegments!;
      expect(fixed.length, 2);
      expect(_isHorizontal(fixed[0].start, fixed[0].end), isFalse);
      expect(_isHorizontal(fixed[1].start, fixed[1].end), isFalse);
      final axis0 = (fixed[0].start.x + fixed[0].end.x) / 2;
      final axis1 = (fixed[1].start.x + fixed[1].end.x) / 2;
      expect(
        (axis0 - basePoints[1].x).abs() <= ElbowConstants.dedupThreshold,
        isTrue,
      );
      expect(
        (axis1 - basePoints[3].x).abs() <= ElbowConstants.dedupThreshold,
        isTrue,
      );
    },
  );

  test('binding switch resets active start span', () {
    const targetRect = DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200);
    final target = elbowRectangleElement(id: 'target', rect: targetRect);

    final basePoints = <DrawPoint>[
      const DrawPoint(x: 160, y: 80),
      const DrawPoint(x: 80, y: 80),
      const DrawPoint(x: 80, y: 40),
      const DrawPoint(x: 0, y: 40),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: basePoints[1], end: basePoints[2]),
    ];
    final element = _arrowElement(
      basePoints,
      fixedSegments: fixedSegments,
      startArrowhead: ArrowheadStyle.triangle,
    );
    final data = element.data as ArrowData;

    const bottomBinding = ArrowBinding(
      elementId: 'target',
      anchor: DrawPoint(x: 0.8, y: 1),
    );
    final bottomPoint = ArrowBindingUtils.resolveElbowBoundPoint(
      binding: bottomBinding,
      target: target,
      hasArrowhead: true,
    )!;
    final toBottom = List<DrawPoint>.from(basePoints)..[0] = bottomPoint;

    final bottomResult = computeElbowEdit(
      element: element,
      data: data.copyWith(startBinding: bottomBinding),
      elementsById: {'target': target},
      localPointsOverride: toBottom,
      fixedSegmentsOverride: fixedSegments,
      startBindingOverride: bottomBinding,
    );

    final bottomElement = _arrowElement(
      bottomResult.localPoints,
      fixedSegments: bottomResult.fixedSegments,
      startBinding: bottomBinding,
      startArrowhead: ArrowheadStyle.triangle,
    );
    final bottomData = bottomElement.data as ArrowData;

    const topBinding = ArrowBinding(
      elementId: 'target',
      anchor: DrawPoint(x: 0.8, y: 0),
    );
    final topPoint = ArrowBindingUtils.resolveElbowBoundPoint(
      binding: topBinding,
      target: target,
      hasArrowhead: true,
    )!;
    final toTop = List<DrawPoint>.from(bottomResult.localPoints)
      ..[0] = topPoint;

    final topResult = computeElbowEdit(
      element: bottomElement,
      data: bottomData.copyWith(startBinding: topBinding),
      elementsById: {'target': target},
      localPointsOverride: toTop,
      fixedSegmentsOverride: bottomResult.fixedSegments,
      startBindingOverride: topBinding,
    );

    expect(
      elbowPathIsOrthogonal(topResult.localPoints),
      isTrue,
      reason: 'points: ${topResult.localPoints}',
    );
    expect(elbowPathHasOnlyCorners(topResult.localPoints), isTrue);
    expect(topResult.localPoints.length, lessThanOrEqualTo(5));

    final startPoint = topResult.localPoints.first;
    final nextPoint = topResult.localPoints[1];
    expect(
      (startPoint.x - nextPoint.x).abs() <= ElbowConstants.dedupThreshold,
      isTrue,
    );
    expect(
      nextPoint.y < startPoint.y,
      isTrue,
      reason: 'Top binding should depart upward.',
    );

    final fixed = topResult.fixedSegments!.first;
    final axis = (fixed.start.x + fixed.end.x) / 2;
    expect(
      (axis - basePoints[1].x).abs() <= ElbowConstants.dedupThreshold,
      isTrue,
    );
  });

  test(
    'binding switch resets active start span with multiple fixed segments',
    () {
      const targetRect = DrawRect(minX: 100, minY: 200, maxX: 200, maxY: 300);
      final target = elbowRectangleElement(id: 'target', rect: targetRect);

      final basePoints = <DrawPoint>[
        const DrawPoint(x: 220, y: 60),
        const DrawPoint(x: 160, y: 60),
        const DrawPoint(x: 160, y: 100),
        const DrawPoint(x: 80, y: 100),
        const DrawPoint(x: 80, y: 40),
        const DrawPoint(x: 0, y: 40),
      ];
      final fixedSegments = <ElbowFixedSegment>[
        ElbowFixedSegment(index: 2, start: basePoints[1], end: basePoints[2]),
        ElbowFixedSegment(index: 4, start: basePoints[3], end: basePoints[4]),
      ];
      final element = _arrowElement(
        basePoints,
        fixedSegments: fixedSegments,
        startArrowhead: ArrowheadStyle.triangle,
      );
      final data = element.data as ArrowData;

      const bottomBinding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0.8, y: 1),
      );
      final bottomPoint = ArrowBindingUtils.resolveElbowBoundPoint(
        binding: bottomBinding,
        target: target,
        hasArrowhead: true,
      )!;
      final toBottom = List<DrawPoint>.from(basePoints)..[0] = bottomPoint;

      final bottomResult = computeElbowEdit(
        element: element,
        data: data.copyWith(startBinding: bottomBinding),
        elementsById: {'target': target},
        localPointsOverride: toBottom,
        fixedSegmentsOverride: fixedSegments,
        startBindingOverride: bottomBinding,
      );

      final bottomElement = _arrowElement(
        bottomResult.localPoints,
        fixedSegments: bottomResult.fixedSegments,
        startBinding: bottomBinding,
        startArrowhead: ArrowheadStyle.triangle,
      );
      final bottomData = bottomElement.data as ArrowData;

      const topBinding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0.8, y: 0),
      );
      final topPoint = ArrowBindingUtils.resolveElbowBoundPoint(
        binding: topBinding,
        target: target,
        hasArrowhead: true,
      )!;
      final toTop = List<DrawPoint>.from(bottomResult.localPoints)
        ..[0] = topPoint;

      final topResult = computeElbowEdit(
        element: bottomElement,
        data: bottomData.copyWith(startBinding: topBinding),
        elementsById: {'target': target},
        localPointsOverride: toTop,
        fixedSegmentsOverride: bottomResult.fixedSegments,
        startBindingOverride: topBinding,
      );

      expect(elbowPathIsOrthogonal(topResult.localPoints), isTrue);
      expect(topResult.localPoints.length, lessThanOrEqualTo(8));

      final startPoint = topResult.localPoints.first;
      final nextPoint = topResult.localPoints[1];
      expect(
        (startPoint.x - nextPoint.x).abs() <= ElbowConstants.dedupThreshold,
        isTrue,
      );
      expect(
        nextPoint.y < startPoint.y,
        isTrue,
        reason: 'Top binding should depart upward.',
      );

      final fixed = topResult.fixedSegments!;
      expect(fixed.length, 2);
      expect(_isHorizontal(fixed[0].start, fixed[0].end), isFalse);
      expect(_isHorizontal(fixed[1].start, fixed[1].end), isFalse);
      final axis0 = (fixed[0].start.x + fixed[0].end.x) / 2;
      final axis1 = (fixed[1].start.x + fixed[1].end.x) / 2;
      expect(
        (axis0 - basePoints[1].x).abs() <= ElbowConstants.dedupThreshold,
        isTrue,
      );
      expect(
        (axis1 - basePoints[3].x).abs() <= ElbowConstants.dedupThreshold,
        isTrue,
      );
    },
  );

  test('binding removal reroutes a freed end span', () {
    const targetRect = DrawRect(minY: 100, maxX: 40, maxY: 140);
    final target = elbowRectangleElement(id: 'target', rect: targetRect);

    final boundPoints = <DrawPoint>[
      DrawPoint.zero,
      const DrawPoint(x: 100, y: 0),
      const DrawPoint(x: 100, y: 60),
      const DrawPoint(x: 180, y: 60),
      const DrawPoint(x: 180, y: 120),
      const DrawPoint(x: 40, y: 120),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: boundPoints[1], end: boundPoints[2]),
    ];
    final element = _arrowElement(
      boundPoints,
      fixedSegments: fixedSegments,
      endBinding: const ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 1, y: 0.5),
      ),
      endArrowhead: ArrowheadStyle.triangle,
    );
    final data = element.data as ArrowData;

    final unboundPoints = List<DrawPoint>.from(boundPoints);
    unboundPoints[unboundPoints.length - 1] = const DrawPoint(x: 20, y: 120);

    final result = computeElbowEdit(
      element: element,
      data: data.copyWith(endBinding: null),
      elementsById: {'target': target},
      localPointsOverride: unboundPoints,
      fixedSegmentsOverride: fixedSegments,
    );

    expect(elbowPathIsOrthogonal(result.localPoints), isTrue);
    expect(
      result.localPoints,
      equals(const <DrawPoint>[
        DrawPoint.zero,
        DrawPoint(x: 100, y: 0),
        DrawPoint(x: 100, y: 120),
        DrawPoint(x: 20, y: 120),
      ]),
    );
  });

  test('binding removal reroutes a freed start span', () {
    const targetRect = DrawRect(minX: 40, minY: 100, maxX: 80, maxY: 140);
    final target = elbowRectangleElement(id: 'target', rect: targetRect);

    final boundPoints = <DrawPoint>[
      const DrawPoint(x: 40, y: 120),
      const DrawPoint(x: 180, y: 120),
      const DrawPoint(x: 180, y: 60),
      const DrawPoint(x: 100, y: 60),
      const DrawPoint(x: 100, y: 0),
      const DrawPoint(x: 180, y: 0),
    ];
    final fixedSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 4, start: boundPoints[3], end: boundPoints[4]),
    ];
    final element = _arrowElement(
      boundPoints,
      fixedSegments: fixedSegments,
      startBinding: const ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0, y: 0.5),
      ),
      startArrowhead: ArrowheadStyle.triangle,
    );
    final data = element.data as ArrowData;

    final unboundPoints = List<DrawPoint>.from(boundPoints);
    unboundPoints[0] = const DrawPoint(x: 20, y: 120);

    final result = computeElbowEdit(
      element: element,
      data: data.copyWith(startBinding: null),
      elementsById: {'target': target},
      localPointsOverride: unboundPoints,
      fixedSegmentsOverride: fixedSegments,
    );

    expect(elbowPathIsOrthogonal(result.localPoints), isTrue);
    expect(
      result.localPoints,
      equals(const <DrawPoint>[
        DrawPoint(x: 20, y: 120),
        DrawPoint(x: 100, y: 120),
        DrawPoint(x: 100, y: 0),
        DrawPoint(x: 180, y: 0),
      ]),
    );
  });

  test('changing a fixed segment axis re-applies points', () {
    final points = <DrawPoint>[
      DrawPoint.zero,
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
      DrawPoint.zero,
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

    expect(elbowPathIsOrthogonal(result.localPoints), isTrue);
    final start = result.localPoints.first;
    final neighbor = result.localPoints[1];
    expect(
      (neighbor.y - start.y).abs() <= ElbowConstants.dedupThreshold,
      isTrue,
    );
  });

  test('binding edits enforce a perpendicular start during endpoint drag', () {
    const targetRect = DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200);
    final target = elbowRectangleElement(id: 'target', rect: targetRect);

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
      (startPoint.x - nextPoint.x).abs() <= ElbowConstants.intersectionEpsilon,
      isTrue,
    );
    expect(nextPoint.y < startPoint.y, isTrue);
  });

  test('fixed segment release preserves prefix outside released region', () {
    final points = <DrawPoint>[
      DrawPoint.zero,
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

  test('fixed segment release keeps endpoints '
      'and orthogonality with only next fixed', () {
    final points = <DrawPoint>[
      DrawPoint.zero,
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
    expect(elbowPathIsOrthogonal(result.localPoints), isTrue);
  });

  test('fixed segment release clears fixed segments when none remain', () {
    final points = <DrawPoint>[
      DrawPoint.zero,
      const DrawPoint(x: 60, y: 0),
      const DrawPoint(x: 60, y: 60),
      const DrawPoint(x: 120, y: 60),
      const DrawPoint(x: 120, y: 120),
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
      fixedSegmentsOverride: const <ElbowFixedSegment>[],
    );

    expect(result.fixedSegments, isNull);
    expect(result.localPoints.first, points.first);
    expect(result.localPoints.last, points.last);
    expect(elbowPathIsOrthogonal(result.localPoints), isTrue);
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
  final rect = elbowRectForPoints(points);
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

bool _isHorizontal(DrawPoint a, DrawPoint b) =>
    (a.y - b.y).abs() <= (a.x - b.x).abs();

double _segmentAxis(ElbowFixedSegment segment) {
  if (_isHorizontal(segment.start, segment.end)) {
    return (segment.start.y + segment.end.y) / 2;
  }
  return (segment.start.x + segment.end.x) / 2;
}
