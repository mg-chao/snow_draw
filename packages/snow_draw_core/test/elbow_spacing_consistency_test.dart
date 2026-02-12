import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

import 'elbow_test_utils.dart';

/// Extracts significant segments from a routed path.
class _Segment {
  const _Segment({
    required this.heading,
    required this.start,
    required this.end,
  });

  final ElbowHeading heading;
  final DrawPoint start;
  final DrawPoint end;

  double get midX => (start.x + end.x) / 2;
}

List<_Segment> _segments(List<DrawPoint> points) {
  final result = <_Segment>[];
  for (var i = 0; i < points.length - 1; i++) {
    final s = points[i];
    final e = points[i + 1];
    if (ElbowGeometry.manhattanDistance(s, e) <=
        ElbowConstants.dedupThreshold) {
      continue;
    }
    result.add(
      _Segment(
        heading: ElbowGeometry.headingForSegment(s, e),
        start: s,
        end: e,
      ),
    );
  }
  return result;
}

void main() {
  // Rectangle that the arrow routes around.
  const rect = DrawRect(
    minX: 200,
    minY: 200,
    maxX: 400,
    maxY: 350,
  );

  final element = elbowRectangleElement(id: 'rect', rect: rect);
  final elementsById = {'rect': element};

  // Start is unbound, above and slightly left of the rect center.
  const startPoint = DrawPoint(x: 280, y: 100);

  test(
    'gap between a vertical segment and the rect right side '
    'stays consistent when the end anchor moves from the '
    'right side to the bottom side',
    () {
      // Scenario A: end anchored to the right side.
      final endBindingRight = const ArrowBinding(
        elementId: 'rect',
        anchor: DrawPoint(x: 1, y: 0.25),
      );
      final endPointRight = ArrowBindingUtils.resolveElbowBoundPoint(
        binding: endBindingRight,
        target: element,
        hasArrowhead: true,
      )!;

      final resultA = routeElbowArrow(
        start: startPoint,
        end: endPointRight,
        endBinding: endBindingRight,
        elementsById: elementsById,
        endArrowhead: ArrowheadStyle.triangle,
      );

      // Scenario B: end anchored to the bottom side.
      final endBindingBottom = const ArrowBinding(
        elementId: 'rect',
        anchor: DrawPoint(x: 0.75, y: 1),
      );
      final endPointBottom = ArrowBindingUtils.resolveElbowBoundPoint(
        binding: endBindingBottom,
        target: element,
        hasArrowhead: true,
      )!;

      final resultB = routeElbowArrow(
        start: startPoint,
        end: endPointBottom,
        endBinding: endBindingBottom,
        elementsById: elementsById,
        endArrowhead: ArrowheadStyle.triangle,
      );

      // Both paths must be orthogonal and avoid the rect.
      expect(elbowPathIsOrthogonal(resultA.points), isTrue);
      expect(elbowPathIsOrthogonal(resultB.points), isTrue);
      expect(
        elbowPathIntersectsBounds(resultA.points, rect),
        isFalse,
      );
      expect(
        elbowPathIntersectsBounds(resultB.points, rect),
        isFalse,
      );

      // Find the Down segment to the right of the rect in each path.
      _Segment downSegRight(List<_Segment> segs) => segs
          .where(
            (s) =>
                s.heading == ElbowHeading.down && s.midX > rect.maxX,
          )
          .reduce(
            (a, b) =>
                (a.midX - rect.maxX).abs() < (b.midX - rect.maxX).abs()
                    ? a
                    : b,
          );

      final gapA = downSegRight(_segments(resultA.points)).midX -
          rect.maxX;
      final gapB = downSegRight(_segments(resultB.points)).midX -
          rect.maxX;

      expect(
        (gapA - gapB).abs(),
        lessThan(2.0),
        reason:
            'Gap A ($gapA) and Gap B ($gapB) should be consistent.',
      );
    },
  );
}
