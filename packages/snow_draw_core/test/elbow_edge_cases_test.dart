import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_editing.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/combined_element_lookup.dart';
import 'elbow_test_utils.dart';

void main() {
  test('routeElbowArrow ignores missing binding targets', () {
    const start = DrawPoint.zero;
    const end = DrawPoint(x: 100, y: 50);
    const missingBinding = ArrowBinding(
      elementId: 'missing',
      anchor: DrawPoint(x: 0.5, y: 0),
    );

    final result = routeElbowArrow(
      start: start,
      end: end,
      startBinding: missingBinding,
      startArrowhead: ArrowheadStyle.triangle,
      elementsById: const {},
    );

    expect(result.points.length, 4);
    expect(result.points.first, start);
    expect(result.points.last, end);
    expect(result.points[1], const DrawPoint(x: 50, y: 0));
    expect(result.points[2], const DrawPoint(x: 50, y: 50));
    expect(elbowPathIsOrthogonal(result.points), isTrue);
  });

  test('computeElbowEdit returns early for insufficient points', () {
    final points = <DrawPoint>[DrawPoint.zero, const DrawPoint(x: 100, y: 0)];
    final element = _arrowElement(points);
    final data = element.data as ArrowData;

    final result = computeElbowEdit(
      element: element,
      data: data,
      lookup: const CombinedElementLookup(base: {}),
      localPointsOverride: <DrawPoint>[points.first],
    );

    expect(result.localPoints, [points.first]);
    expect(result.fixedSegments, isNull);
  });

  test('computeElbowEdit drops invalid fixed segments', () {
    final points = <DrawPoint>[
      DrawPoint.zero,
      const DrawPoint(x: 100, y: 0),
      const DrawPoint(x: 100, y: 80),
    ];
    final element = _arrowElement(points);
    final data = element.data as ArrowData;

    final invalidSegments = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 1, start: points[0], end: points[1]),
    ];

    final result = computeElbowEdit(
      element: element,
      data: data,
      lookup: const CombinedElementLookup(base: {}),
      localPointsOverride: points,
      fixedSegmentsOverride: invalidSegments,
    );

    expect(result.fixedSegments, isNull);
    expect(result.localPoints.length, greaterThanOrEqualTo(2));
    expect(elbowPathIsOrthogonal(result.localPoints), isTrue);
  });

  test('computeElbowEdit sanitizes duplicate and diagonal fixed segments', () {
    final points = <DrawPoint>[
      DrawPoint.zero,
      const DrawPoint(x: 80, y: 0),
      const DrawPoint(x: 80, y: 60),
      const DrawPoint(x: 160, y: 60),
    ];
    final element = _arrowElement(points);
    final data = element.data as ArrowData;

    final overrides = <ElbowFixedSegment>[
      ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
      ElbowFixedSegment(index: 2, start: points[0], end: points[1]),
      const ElbowFixedSegment(
        index: 3,
        start: DrawPoint.zero,
        end: DrawPoint(x: 80, y: 60),
      ),
    ];

    final result = computeElbowEdit(
      element: element,
      data: data,
      lookup: const CombinedElementLookup(base: {}),
      localPointsOverride: points,
      fixedSegmentsOverride: overrides,
    );

    expect(result.fixedSegments, isNotNull);
    expect(result.fixedSegments!.length, 1);

    final fixed = result.fixedSegments!.first;
    final dx = (fixed.start.x - fixed.end.x).abs();
    final dy = (fixed.start.y - fixed.end.y).abs();
    expect(
      dx <= ElbowConstants.dedupThreshold ||
          dy <= ElbowConstants.dedupThreshold,
      isTrue,
    );
  });
}

ElementState _arrowElement(List<DrawPoint> points) {
  final rect = elbowRectForPoints(points);
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  final data = ArrowData(points: normalized, arrowType: ArrowType.elbow);
  return ElementState(
    id: 'arrow',
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: data,
  );
}
