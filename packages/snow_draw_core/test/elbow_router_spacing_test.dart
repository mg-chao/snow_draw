import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

import 'elbow_test_utils.dart';

void main() {
  test('elbow routing keeps bound spacing consistent across arrowheads', () {
    const rect = DrawRect(minX: 80, minY: 80, maxX: 260, maxY: 200);
    final element = elbowRectangleElement(id: 'rect-1', rect: rect);

    const startBinding = ArrowBinding(
      elementId: 'rect-1',
      anchor: DrawPoint(x: 0.4, y: 0),
    );
    const endBinding = ArrowBinding(
      elementId: 'rect-1',
      anchor: DrawPoint(x: 1, y: 0.6),
    );

    final startPoint = ArrowBindingUtils.resolveElbowBoundPoint(
      binding: startBinding,
      target: element,
      hasArrowhead: false,
    )!;
    final endPoint = ArrowBindingUtils.resolveElbowBoundPoint(
      binding: endBinding,
      target: element,
      hasArrowhead: true,
    )!;

    final result = routeElbowArrow(
      start: startPoint,
      end: endPoint,
      startBinding: startBinding,
      endBinding: endBinding,
      elementsById: {'rect-1': element},
      endArrowhead: ArrowheadStyle.triangle,
    );

    final segments = _significantSegments(result.points);
    expect(segments.length, greaterThanOrEqualTo(4));

    final headings = segments
        .take(4)
        .map((segment) => segment.heading)
        .toList();
    expect(headings, const [
      ElbowHeading.up,
      ElbowHeading.right,
      ElbowHeading.down,
      ElbowHeading.left,
    ]);

    final rightSegment = segments[1];
    final downSegment = segments[2];

    final gapA = rect.minY - rightSegment.midY;
    final gapB = downSegment.midX - rect.maxX;

    expect(gapA, greaterThan(0));
    expect(gapB, greaterThan(0));

    expect((gapA - gapB).abs(), lessThanOrEqualTo(1e-3));
  });
}

class _SegmentInfo {
  const _SegmentInfo({
    required this.heading,
    required this.midX,
    required this.midY,
  });

  final ElbowHeading heading;
  final double midX;
  final double midY;
}

List<_SegmentInfo> _significantSegments(List<DrawPoint> points) {
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
        midX: (start.x + end.x) / 2,
        midY: (start.y + end.y) / 2,
      ),
    );
  }
  return segments;
}
