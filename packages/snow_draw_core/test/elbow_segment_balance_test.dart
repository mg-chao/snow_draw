import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

import 'elbow_test_utils.dart';

void main() {
  test('right-down-right path balances first and last horizontal segments', () {
    // Rectangle A on the left, Rectangle B on the right,
    // with B offset downward so the path is [right, down, right].
    const rectA = DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200);
    const rectB = DrawRect(minX: 400, minY: 150, maxX: 500, maxY: 250);

    _expectBalancedThreeSegmentPath(
      rectA: rectA,
      rectB: rectB,
      startAnchor: const DrawPoint(x: 1, y: 0.5),
      endAnchor: const DrawPoint(x: 0, y: 0.5),
      expectedHeadings: const [
        ElbowHeading.right,
        ElbowHeading.down,
        ElbowHeading.right,
      ],
    );
  });

  test('down-right-down path balances first and last vertical segments', () {
    // Rectangle A on top, Rectangle B below and to the right,
    // so the path is [down, right, down].
    const rectA = DrawRect(minX: 100, minY: 100, maxX: 200, maxY: 200);
    const rectB = DrawRect(minX: 150, minY: 400, maxX: 250, maxY: 500);

    _expectBalancedThreeSegmentPath(
      rectA: rectA,
      rectB: rectB,
      startAnchor: const DrawPoint(x: 0.5, y: 1),
      endAnchor: const DrawPoint(x: 0.5, y: 0),
      expectedHeadings: const [
        ElbowHeading.down,
        ElbowHeading.right,
        ElbowHeading.down,
      ],
    );
  });

  test('right-up-right path balances when B is above A', () {
    const rectA = DrawRect(minX: 100, minY: 200, maxX: 200, maxY: 300);
    const rectB = DrawRect(minX: 400, minY: 100, maxX: 500, maxY: 200);

    _expectBalancedThreeSegmentPath(
      rectA: rectA,
      rectB: rectB,
      startAnchor: const DrawPoint(x: 1, y: 0.5),
      endAnchor: const DrawPoint(x: 0, y: 0.5),
      expectedHeadings: const [
        ElbowHeading.right,
        ElbowHeading.up,
        ElbowHeading.right,
      ],
    );
  });
}

void _expectBalancedThreeSegmentPath({
  required DrawRect rectA,
  required DrawRect rectB,
  required DrawPoint startAnchor,
  required DrawPoint endAnchor,
  required List<ElbowHeading> expectedHeadings,
}) {
  final elementA = elbowRectangleElement(id: 'a', rect: rectA);
  final elementB = elbowRectangleElement(id: 'b', rect: rectB);

  final startBinding = ArrowBinding(elementId: 'a', anchor: startAnchor);
  final endBinding = ArrowBinding(elementId: 'b', anchor: endAnchor);

  final startPoint = ArrowBindingUtils.resolveElbowBoundPoint(
    binding: startBinding,
    target: elementA,
    hasArrowhead: false,
  )!;
  final endPoint = ArrowBindingUtils.resolveElbowBoundPoint(
    binding: endBinding,
    target: elementB,
    hasArrowhead: true,
  )!;

  final result = routeElbowArrow(
    start: startPoint,
    end: endPoint,
    startBinding: startBinding,
    endBinding: endBinding,
    elementsById: {'a': elementA, 'b': elementB},
    endArrowhead: ArrowheadStyle.triangle,
  );

  expect(elbowPathIsOrthogonal(result.points), isTrue);
  expect(elbowPathIntersectsBounds(result.points, rectA), isFalse);
  expect(elbowPathIntersectsBounds(result.points, rectB), isFalse);

  final segments = _significantSegments(result.points);
  final headings = segments.map((s) => s.heading).toList();
  expect(headings, expectedHeadings);

  final firstLen = segments.first.length;
  final lastLen = segments.last.length;
  final ratio = firstLen / lastLen;

  expect(
    ratio,
    greaterThan(0.3),
    reason:
        'First segment ($firstLen) should not be much shorter '
        'than last segment ($lastLen). Ratio: $ratio',
  );
  expect(
    ratio,
    lessThan(3.0),
    reason:
        'First segment ($firstLen) should not be much longer '
        'than last segment ($lastLen). Ratio: $ratio',
  );
}

class _SegmentInfo {
  const _SegmentInfo({
    required this.heading,
    required this.start,
    required this.end,
  });

  final ElbowHeading heading;
  final DrawPoint start;
  final DrawPoint end;

  double get length => (start.x - end.x).abs() + (start.y - end.y).abs();
}

List<_SegmentInfo> _significantSegments(List<DrawPoint> points) {
  if (points.length < 2) {
    return const <_SegmentInfo>[];
  }
  final segments = <_SegmentInfo>[];
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    if (ElbowGeometry.manhattanDistance(start, end) <=
        ElbowConstants.dedupThreshold) {
      continue;
    }
    segments.add(
      _SegmentInfo(
        heading: ElbowGeometry.headingForSegment(start, end),
        start: start,
        end: end,
      ),
    );
  }
  return segments;
}
