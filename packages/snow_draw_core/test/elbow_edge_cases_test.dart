import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_editing.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/combined_element_lookup.dart';
import 'elbow_test_utils.dart';

void main() {
  const lookup = CombinedElementLookup(base: {});

  test('routeElbowArrow ignores missing binding targets', () {
    final result = routeElbowArrow(
      start: DrawPoint.zero,
      end: const DrawPoint(x: 100, y: 50),
      startBinding: const ArrowBinding(
        elementId: 'missing',
        anchor: DrawPoint(x: 0.5, y: 0),
      ),
      startArrowhead: ArrowheadStyle.triangle,
      elementsById: const {},
    );

    expect(result.points, const <DrawPoint>[
      DrawPoint.zero,
      DrawPoint(x: 50, y: 0),
      DrawPoint(x: 50, y: 50),
      DrawPoint(x: 100, y: 50),
    ]);
    expect(elbowPathIsOrthogonal(result.points), isTrue);
  });

  test('computeElbowEdit returns early for insufficient points', () {
    final points = <DrawPoint>[DrawPoint.zero, const DrawPoint(x: 100, y: 0)];
    final element = _arrowElement(points);

    final result = computeElbowEdit(
      element: element,
      data: element.data as ArrowData,
      lookup: lookup,
      localPointsOverride: <DrawPoint>[points.first],
    );

    expect(result.localPoints, <DrawPoint>[points.first]);
    expect(result.fixedSegments, isNull);
  });

  test('computeElbowEdit drops invalid fixed segments', () {
    final points = <DrawPoint>[
      DrawPoint.zero,
      const DrawPoint(x: 100, y: 0),
      const DrawPoint(x: 100, y: 80),
    ];
    final element = _arrowElement(points);

    final result = computeElbowEdit(
      element: element,
      data: element.data as ArrowData,
      lookup: lookup,
      localPointsOverride: points,
      fixedSegmentsOverride: <ElbowFixedSegment>[
        ElbowFixedSegment(index: 1, start: points[0], end: points[1]),
      ],
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

    final result = computeElbowEdit(
      element: element,
      data: element.data as ArrowData,
      lookup: lookup,
      localPointsOverride: points,
      fixedSegmentsOverride: <ElbowFixedSegment>[
        ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
        ElbowFixedSegment(index: 2, start: points[0], end: points[1]),
        const ElbowFixedSegment(
          index: 3,
          start: DrawPoint.zero,
          end: DrawPoint(x: 80, y: 60),
        ),
      ],
    );

    expect(result.fixedSegments, isNotNull);
    expect(result.fixedSegments, hasLength(1));
    final fixed = result.fixedSegments!.first;
    expect(elbowPathIsOrthogonal(<DrawPoint>[fixed.start, fixed.end]), isTrue);
  });
}

ElementState _arrowElement(List<DrawPoint> points) {
  final rect = elbowRectForPoints(points);
  return ElementState(
    id: 'arrow',
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: ArrowData(
      points: ArrowGeometry.normalizePoints(worldPoints: points, rect: rect),
      arrowType: ArrowType.elbow,
    ),
  );
}
