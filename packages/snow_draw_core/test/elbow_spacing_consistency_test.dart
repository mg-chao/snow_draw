import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:test/test.dart';

import 'elbow_test_utils.dart';

double _closestDownGapToRectRight({
  required List<DrawPoint> points,
  required DrawRect rect,
}) {
  double? bestGap;
  double? bestDistance;
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    if (ElbowGeometry.manhattanDistance(start, end) <=
        ElbowConstants.dedupThreshold) {
      continue;
    }
    if (ElbowGeometry.headingForSegment(start, end) != ElbowHeading.down) {
      continue;
    }
    final midX = (start.x + end.x) / 2;
    if (midX <= rect.maxX) {
      continue;
    }

    final distanceToRect = (midX - rect.maxX).abs();
    if (bestDistance == null || distanceToRect < bestDistance) {
      bestDistance = distanceToRect;
      bestGap = midX - rect.maxX;
    }
  }

  expect(
    bestGap,
    isNotNull,
    reason: 'Expected a downward segment to the right of the rectangle.',
  );
  return bestGap!;
}

void main() {
  const rect = DrawRect(minX: 200, minY: 200, maxX: 400, maxY: 350);
  final element = elbowRectangleElement(id: 'rect', rect: rect);
  final elementsById = {'rect': element};
  const startPoint = DrawPoint(x: 280, y: 100);

  test('gap between a vertical segment and the rect right side '
      'stays consistent when the end anchor moves from the '
      'right side to the bottom side', () {
    List<DrawPoint> routeForEndBinding(ArrowBinding endBinding) {
      final endPoint = ArrowBindingUtils.resolveElbowBoundPoint(
        binding: endBinding,
        target: element,
        hasArrowhead: true,
      )!;

      final result = routeElbowArrow(
        start: startPoint,
        end: endPoint,
        endBinding: endBinding,
        elementsById: elementsById,
        endArrowhead: ArrowheadStyle.triangle,
      );

      expect(elbowPathIsOrthogonal(result.points), isTrue);
      expect(elbowPathIntersectsBounds(result.points, rect), isFalse);
      return result.points;
    }

    const endBindingRight = ArrowBinding(
      elementId: 'rect',
      anchor: DrawPoint(x: 1, y: 0.25),
    );
    const endBindingBottom = ArrowBinding(
      elementId: 'rect',
      anchor: DrawPoint(x: 0.75, y: 1),
    );

    final pointsA = routeForEndBinding(endBindingRight);
    final pointsB = routeForEndBinding(endBindingBottom);

    final gapA = _closestDownGapToRectRight(points: pointsA, rect: rect);
    final gapB = _closestDownGapToRectRight(points: pointsB, rect: rect);

    expect(
      (gapA - gapB).abs(),
      lessThan(2.0),
      reason: 'Gap A ($gapA) and Gap B ($gapB) should be consistent.',
    );
  });
}
