import 'package:flutter_test/flutter_test.dart';
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

    final startPoint =
        ArrowBindingUtils.resolveElbowBoundPoint(
          binding: binding,
          target: boundElement,
          hasArrowhead: false,
        ) ??
        const DrawPoint(x: 36, y: -10);

    final endX = rect.maxX + 180;
    final sampled = <_RouteSample>[];
    for (var y = -140.0; y <= -4.0; y += 4.0) {
      final endPoint = DrawPoint(x: endX, y: y);
      final result = routeElbowArrow(
        start: startPoint,
        end: endPoint,
        startBinding: binding,
        elementsById: {'rect-1': boundElement},
      );
      final headings = _headingSequence(result.points);
      final horizontalY = _rightSegmentY(points: result.points);
      if (horizontalY != null &&
          headings.length == 3 &&
          headings[0] == ElbowHeading.up &&
          headings[1] == ElbowHeading.right &&
          headings[2] == ElbowHeading.down) {
        sampled.add(
          _RouteSample(
            endY: y,
            horizontalY: horizontalY,
            points: result.points,
          ),
        );
      }
    }

    expect(sampled.length, greaterThanOrEqualTo(3));

    var maxDelta = 0.0;
    for (var i = 1; i < sampled.length; i++) {
      final delta = (sampled[i].horizontalY - sampled[i - 1].horizontalY).abs();
      if (delta > maxDelta) {
        maxDelta = delta;
      }
    }

    if (maxDelta > 6) {
      final details = sampled
          .map(
            (sample) =>
                'endY=${sample.endY.toStringAsFixed(1)} '
                'rightY=${sample.horizontalY.toStringAsFixed(1)} '
                'points=${sample.points}',
          )
          .join('\n');
      printOnFailure('route samples:\n$details');
    }

    expect(
      maxDelta,
      lessThanOrEqualTo(6),
      reason:
          'Rightward segment should move smoothly as the end moves downward.',
    );
  });
}

class _RouteSample {
  _RouteSample({
    required this.endY,
    required this.horizontalY,
    required this.points,
  });

  final double endY;
  final double horizontalY;
  final List<DrawPoint> points;
}

List<ElbowHeading> _headingSequence(List<DrawPoint> points) {
  if (points.length < 2) {
    return const <ElbowHeading>[];
  }
  final headings = <ElbowHeading>[];
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    if (ElbowGeometry.manhattanDistance(start, end) <=
        ElbowConstants.dedupThreshold) {
      continue;
    }
    headings.add(ElbowGeometry.headingForSegment(start, end));
  }
  return headings;
}

double? _rightSegmentY({required List<DrawPoint> points}) {
  if (points.length < 2) {
    return null;
  }
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    if (ElbowGeometry.manhattanDistance(start, end) <=
        ElbowConstants.dedupThreshold) {
      continue;
    }
    final heading = ElbowGeometry.headingForSegment(start, end);
    if (heading == ElbowHeading.right) {
      return (start.y + end.y) / 2;
    }
  }
  return null;
}
