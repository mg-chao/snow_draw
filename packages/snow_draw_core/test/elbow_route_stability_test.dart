import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

import 'elbow_test_utils.dart';

void main() {
  test('bound start keeps right segment stable as end moves downward', () {
    const rect = DrawRect(maxX: 120, maxY: 80);
    final boundElement = elbowRectangleElement(id: 'rect-1', rect: rect);
    const binding = ArrowBinding(
      elementId: 'rect-1',
      anchor: DrawPoint(x: 0.3, y: 0),
    );

    final resolvedStartPoint = ArrowBindingUtils.resolveElbowBoundPoint(
      binding: binding,
      target: boundElement,
      hasArrowhead: false,
    );
    expect(resolvedStartPoint, isNotNull);
    final startPoint = resolvedStartPoint!;

    final endX = rect.maxX + 180;
    final rightSegmentYs = <double>[];
    for (var y = -140.0; y <= -4.0; y += 4.0) {
      final endPoint = DrawPoint(x: endX, y: y);
      final result = routeElbowArrow(
        start: startPoint,
        end: endPoint,
        startBinding: binding,
        elementsById: {'rect-1': boundElement},
      );
      final horizontalY = _rightSegmentYForUpRightDown(result.points);
      if (horizontalY != null) {
        rightSegmentYs.add(horizontalY);
      }
    }

    expect(rightSegmentYs.length, greaterThanOrEqualTo(3));

    var maxDelta = 0.0;
    for (var i = 1; i < rightSegmentYs.length; i++) {
      final delta = (rightSegmentYs[i] - rightSegmentYs[i - 1]).abs();
      if (delta > maxDelta) {
        maxDelta = delta;
      }
    }

    expect(
      maxDelta,
      lessThanOrEqualTo(6),
      reason:
          'Rightward segment should move smoothly as the end moves downward.',
    );
  });
}

double? _rightSegmentYForUpRightDown(List<DrawPoint> points) {
  if (points.length < 2) {
    return null;
  }

  final headings = <ElbowHeading>[];
  double? rightSegmentY;
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    if (ElbowGeometry.manhattanDistance(start, end) <=
        ElbowConstants.dedupThreshold) {
      continue;
    }
    final heading = ElbowGeometry.headingForSegment(start, end);
    headings.add(heading);
    if (heading == ElbowHeading.right) {
      rightSegmentY = (start.y + end.y) / 2;
    }
  }

  if (headings.length != 3 ||
      headings[0] != ElbowHeading.up ||
      headings[1] != ElbowHeading.right ||
      headings[2] != ElbowHeading.down) {
    return null;
  }
  return rightSegmentY;
}
